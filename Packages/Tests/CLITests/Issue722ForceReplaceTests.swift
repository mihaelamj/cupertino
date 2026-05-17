@testable import CLI
import Darwin
import Foundation
import LoggingModels
import Testing

// MARK: - #722 follow-up — SaveSiblingGate.--force-replace

//
// PR #577 (#253) shipped the must-have gate (sibling-detection +
// [c]/[w]/[a] prompt + non-TTY abort). This file pins the #722
// follow-up: the `--force-replace` opt-in path that authorises
// SIGTERMing the sibling save.
//
// Test surface stays at the pure-logic + parser layer. The actual
// SIGTERM ladder (`terminateSiblings`) takes real PIDs + Thread.sleep;
// covering it would require spawning real sleep processes which the
// existing test suite shape doesn't. The pure parts the rest of the
// gate decision tree depends on:
//
//   1. `parseTypedReplaceConfirmation(_:)` — accepts `replace` (case-
//      insensitive + whitespace-tolerant); rejects anything else
//      (including nil + empty)
//   2. New `Action.forceReplaceSiblings(pids:)` case — added without
//      breaking the existing `.proceed` / `.waitForSiblingsThenProceed`
//      / `.abort` cases; Equatable conformance preserved

@Suite("#722 — SaveSiblingGate.parseTypedReplaceConfirmation", .serialized)
struct Issue722TypedConfirmationParserTests {
    // MARK: - 1. Accept path

    @Test(
        "accepts 'replace' (case-insensitive + whitespace-tolerant)",
        arguments: [
            "replace",
            "REPLACE",
            "Replace",
            "  replace",
            "replace  ",
            "  replace  ",
            "\treplace\n",
        ]
    )
    func acceptsCanonicalShapes(input: String) {
        let result = SaveSiblingGate.parseTypedReplaceConfirmation(input)
        #expect(
            result == .accepted,
            "expected .accepted for '\(input)', got: \(result)"
        )
    }

    // MARK: - 2. Reject path

    @Test(
        "rejects everything that isn't exactly 'replace' after normalisation",
        arguments: [
            "", // empty
            "y", // single-keystroke yes — explicitly not enough
            "yes", // affirmative but wrong word
            "replac", // typo
            "replaced", // adjacent shape
            "REP LACE", // internal whitespace breaks
            "replace!", // punctuation breaks
            "abort", // explicit other choice
            "c", // the [c]/[w]/[a] keys are not the typed gate
        ]
    )
    func rejectsOtherShapes(input: String) {
        let result = SaveSiblingGate.parseTypedReplaceConfirmation(input)
        guard case let .rejected(echoed) = result else {
            Issue.record("expected .rejected for '\(input)', got: \(result)")
            return
        }
        #expect(echoed == input, "echoed input should round-trip; got: '\(echoed)'")
    }

    @Test("nil (EOF on stdin) rejects with empty echoed input")
    func nilInputRejects() {
        switch SaveSiblingGate.parseTypedReplaceConfirmation(nil) {
        case .accepted:
            Issue.record("nil must not be accepted")
        case .rejected(let echoed):
            #expect(echoed.isEmpty, "nil rejection should echo empty input; got: '\(echoed)'")
        }
    }

    // MARK: - 3. Idempotency

    @Test("parser is pure — same input yields same outcome across multiple calls")
    func parserIsPure() {
        let input = "replace"
        let first = SaveSiblingGate.parseTypedReplaceConfirmation(input)
        let second = SaveSiblingGate.parseTypedReplaceConfirmation(input)
        let third = SaveSiblingGate.parseTypedReplaceConfirmation(input)
        #expect(first == second)
        #expect(second == third)
        #expect(first == .accepted)
    }
}

// MARK: - Action shape

@Suite("#722 — SaveSiblingGate.Action.forceReplaceSiblings shape", .serialized)
struct Issue722ActionShapeTests {
    @Test("forceReplaceSiblings preserves the supplied PID list")
    func preservesPids() {
        let action = SaveSiblingGate.Action.forceReplaceSiblings(pids: [12345, 67890])
        guard case let .forceReplaceSiblings(pids) = action else {
            Issue.record("expected .forceReplaceSiblings, got: \(action)")
            return
        }
        #expect(pids == [12345, 67890])
    }

    @Test("forceReplaceSiblings is Equatable — same PIDs equal, different PIDs unequal")
    func equatable() {
        let a = SaveSiblingGate.Action.forceReplaceSiblings(pids: [42])
        let b = SaveSiblingGate.Action.forceReplaceSiblings(pids: [42])
        let c = SaveSiblingGate.Action.forceReplaceSiblings(pids: [99])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("forceReplaceSiblings is distinguishable from the other Action cases")
    func distinguishableFromOtherCases() {
        let force = SaveSiblingGate.Action.forceReplaceSiblings(pids: [1])
        let proceed = SaveSiblingGate.Action.proceed
        let wait = SaveSiblingGate.Action.waitForSiblingsThenProceed(pids: [1])
        let abort = SaveSiblingGate.Action.abort(reason: "test")

        #expect(force != proceed)
        #expect(force != wait)
        #expect(force != abort)
    }
}

// MARK: - terminateSiblings safe-with-no-PIDs

@Suite("#722 — SaveSiblingGate.terminateSiblings safety", .serialized)
struct Issue722TerminateSiblingsTests {
    /// In-memory recorder — captures every record + output line for
    /// assertions without driving real OSLog output.
    private final class CapturingRecording: LoggingModels.Logging.Recording, @unchecked Sendable {
        private let lock = NSLock()
        private var _records: [String] = []

        func record(_ message: String, level _: LoggingModels.Logging.Level, category _: LoggingModels.Logging.Category) {
            lock.lock(); defer { lock.unlock() }
            _records.append(message)
        }

        func output(_ message: String) {
            lock.lock(); defer { lock.unlock() }
            _records.append(message)
        }

        var records: [String] {
            lock.lock(); defer { lock.unlock() }
            return _records
        }
    }

    @Test("terminateSiblings([]) is a no-op (early return, no kill calls, no log noise)")
    func emptyPidsIsNoOp() {
        let recorder = CapturingRecording()
        SaveSiblingGate.terminateSiblings(
            pids: [],
            graceSeconds: 5,
            pollInterval: 0.1,
            recording: recorder
        )
        // No "Sending SIGTERM..." should appear because the empty-PID
        // path short-circuits before logging anything.
        let saw = recorder.records.joined(separator: "\n")
        #expect(
            !saw.contains("Sending SIGTERM"),
            "empty-PID call must short-circuit before logging — got:\n\(saw)"
        )
    }

    @Test("terminateSiblings against a dead PID logs the SIGTERM attempt without hanging")
    func deadPidDoesNotHang() throws {
        // PID 1 is launchd on macOS — alive but not killable by us
        // (we'd get EPERM). A dead PID would return ESRCH which the
        // gate explicitly tolerates. To get a guaranteed-dead PID:
        // fork a `sleep 0`, wait, then call terminateSiblings against
        // its now-defunct PID. The call must complete within the
        // grace window without throwing or hanging.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["0"]
        try task.run()
        task.waitUntilExit()
        let deadPid = task.processIdentifier

        let recorder = CapturingRecording()
        let start = Date()
        SaveSiblingGate.terminateSiblings(
            pids: [deadPid],
            graceSeconds: 2,
            pollInterval: 0.1,
            recording: recorder
        )
        let elapsed = Date().timeIntervalSince(start)

        // The dead PID should pass `kill(pid, 0) != 0` (ESRCH) on the
        // first poll → loop exits immediately. The total call should
        // complete well below `graceSeconds`.
        #expect(elapsed < 1.0, "dead-PID call must short-circuit fast; got \(elapsed)s")
        let saw = recorder.records.joined(separator: "\n")
        #expect(saw.contains("Sibling save(s) terminated"), "completion log missing")
    }
}

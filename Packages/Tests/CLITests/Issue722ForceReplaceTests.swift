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

    @Test("terminateSiblings against a dead PID short-circuits via the verifier (Bug-1 fix)")
    func deadPidShortCircuitsViaVerifier() throws {
        // Fork a `sleep 0`, wait, capture its now-defunct PID.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["0"]
        try task.run()
        task.waitUntilExit()
        let deadPid = task.processIdentifier

        let recorder = CapturingRecording()
        let start = Date()
        let outcome = SaveSiblingGate.terminateSiblings(
            pids: [deadPid],
            graceSeconds: 2,
            pollInterval: 0.1,
            recording: recorder
        )
        let elapsed = Date().timeIntervalSince(start)

        // The dead-PID verifier short-circuits BEFORE the SIGTERM loop
        // (Bug-1 mitigation). Should complete in well under the grace
        // window.
        #expect(elapsed < 1.0, "dead-PID call must short-circuit fast; got \(elapsed)s")
        #expect(outcome == .allTerminated, "dead-PID should report allTerminated; got: \(outcome)")
    }

    @Test("terminateSiblings drops PIDs that fail the verifier (PID-reuse-race mitigation)")
    func verifierDropsPidsThatFailReverification() {
        let recorder = CapturingRecording()
        // Inject a verifier that rejects everything — simulates the
        // PID-reuse race where every PID detected at scan time has
        // now been recycled into an unrelated process.
        let outcome = SaveSiblingGate.terminateSiblings(
            pids: [99991, 99992, 99993],
            graceSeconds: 1,
            pollInterval: 0.1,
            recording: recorder,
            verifier: { _ in false }
        )

        #expect(outcome == .allTerminated, "verifier rejecting every PID should yield allTerminated (empty kill set)")
        let saw = recorder.records.joined(separator: "\n")
        #expect(
            saw.contains("no longer a cupertino save sibling"),
            "must log the verifier-drop reason — got:\n\(saw)"
        )
        // No SIGTERM should have been attempted (every PID dropped).
        #expect(
            !saw.contains("Sending SIGTERM"),
            "no PIDs should reach the kill loop when verifier rejects all — got:\n\(saw)"
        )
    }

    @Test("terminateSiblings honours the verifier — only verified PIDs reach the kill loop")
    func verifierPartiallyFilters() throws {
        // Spawn one real /bin/sleep we can kill, capture its PID. The
        // verifier accepts only this PID; bogus PID 99_991 gets dropped.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["30"]
        try task.run()
        defer { task.terminate() }
        let realPid = task.processIdentifier

        let recorder = CapturingRecording()
        let outcome = SaveSiblingGate.terminateSiblings(
            pids: [realPid, 99991],
            graceSeconds: 3,
            pollInterval: 0.1,
            recording: recorder,
            verifier: { $0 == realPid }
        )

        // The real PID gets SIGTERM (then exits), the bogus PID is
        // verifier-dropped. Result: allTerminated, with both behaviours
        // surfaced in the log.
        #expect(outcome == .allTerminated, "expected allTerminated; got: \(outcome)")
        let saw = recorder.records.joined(separator: "\n")
        #expect(saw.contains("99991"), "verifier-rejection log must name the dropped PID — got:\n\(saw)")
        #expect(saw.contains("Sending SIGTERM"), "real PID should reach kill loop — got:\n\(saw)")
    }
}

// MARK: - Gate decision tree (Bug-3 fix — full forceReplace × assumeYes × TTY × conflict matrix)

@Suite("#722 — SaveSiblingGate.gate decision tree (forceReplace path)", .serialized)
struct Issue722GateDecisionTreeTests {
    /// Sibling fixture — a synthetic save process targeting search.db.
    private static func makeSibling(pid: pid_t = 12345, target: SaveSiblingGate.Target = .search) -> SaveSiblingGate.Sibling {
        SaveSiblingGate.Sibling(
            pid: pid,
            targets: [target],
            elapsed: "2h 30m",
            argv: ["/usr/local/bin/cupertino", "save"]
        )
    }

    /// Minimal noop recorder — the decision tree tests don't assert
    /// on log output, just on the returned Action.
    private final class NoopRecording: LoggingModels.Logging.Recording, @unchecked Sendable {
        func record(_: String, level _: LoggingModels.Logging.Level, category _: LoggingModels.Logging.Category) {}
        func output(_: String) {}
    }

    // MARK: - No conflict → proceed (regression guard for the existing path)

    @Test("forceReplace=true, assumeYes=false, no sibling → .proceed (regression guard)")
    func noConflictProceeds() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: false,
            isInteractive: { true },
            readConfirmation: { "should not be read" },
            siblingDetector: { [] }
        )
        #expect(action == .proceed)
    }

    @Test("forceReplace=true, sibling on different target → .proceed (no overlap)")
    func differentTargetSiblingProceeds() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: false,
            isInteractive: { true },
            readConfirmation: { "should not be read" },
            siblingDetector: { [Self.makeSibling(target: .samples)] }
        )
        #expect(action == .proceed)
    }

    // MARK: - Conflict + forceReplace=true paths

    @Test("forceReplace=true, assumeYes=true, conflict → .forceReplaceSiblings (CI bypass)")
    func assumeYesBypassesTypedGate() {
        var readConfirmationCalls = 0
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: true,
            isInteractive: { false }, // non-TTY — proves --yes works even non-interactively
            readConfirmation: {
                readConfirmationCalls += 1
                return "replace"
            },
            siblingDetector: { [Self.makeSibling(pid: 12345)] }
        )
        guard case let .forceReplaceSiblings(pids) = action else {
            Issue.record("expected .forceReplaceSiblings, got: \(action)")
            return
        }
        #expect(pids == [12345])
        #expect(readConfirmationCalls == 0, "--yes must bypass the typed-confirmation prompt; got \(readConfirmationCalls) read calls")
    }

    @Test("forceReplace=true, assumeYes=false, non-TTY, conflict → .abort (refuses unattended force-kill)")
    func nonTTYWithoutYesAborts() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: false,
            isInteractive: { false },
            readConfirmation: { fatalError("should not be called") },
            siblingDetector: { [Self.makeSibling(pid: 99)] }
        )
        guard case let .abort(reason) = action else {
            Issue.record("expected .abort, got: \(action)")
            return
        }
        #expect(reason.contains("--force-replace"))
        #expect(reason.contains("--yes"), "abort reason must point users at the --yes bypass; got: \(reason)")
        #expect(reason.contains("99"), "abort reason must name the PID(s); got: \(reason)")
    }

    @Test("forceReplace=true, TTY, typed 'replace' → .forceReplaceSiblings")
    func ttyTypedReplaceAccepts() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: false,
            isInteractive: { true },
            readConfirmation: { "replace" },
            siblingDetector: { [Self.makeSibling(pid: 4242)] }
        )
        guard case let .forceReplaceSiblings(pids) = action else {
            Issue.record("expected .forceReplaceSiblings, got: \(action)")
            return
        }
        #expect(pids == [4242])
    }

    @Test("forceReplace=true, TTY, typed 'cancel' (or any non-replace string) → .abort")
    func ttyTypedNonReplaceAborts() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: false,
            isInteractive: { true },
            readConfirmation: { "cancel" },
            siblingDetector: { [Self.makeSibling()] }
        )
        guard case let .abort(reason) = action else {
            Issue.record("expected .abort, got: \(action)")
            return
        }
        #expect(reason.contains("cancel"), "abort reason should echo the rejected input; got: \(reason)")
        #expect(reason.contains("'replace'"), "abort reason should name the expected token; got: \(reason)")
    }

    @Test("forceReplace=true, TTY, EOF on stdin → .abort (nil readConfirmation)")
    func ttyEOFAborts() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: true,
            assumeYes: false,
            isInteractive: { true },
            readConfirmation: { nil },
            siblingDetector: { [Self.makeSibling()] }
        )
        guard case .abort = action else {
            Issue.record("expected .abort on EOF, got: \(action)")
            return
        }
    }

    // MARK: - forceReplace=false sanity (the existing #253 path stays intact)

    @Test("forceReplace=false, TTY, conflict → falls into existing [c]/[w]/[a] prompt (not the typed gate)")
    func forceReplaceFalseUsesExistingPrompt() {
        // Inject a confirmation function that returns "c" (continue) —
        // the existing #253 [c]/[w]/[a] handler should consume it and
        // return .proceed. If our refactor accidentally rerouted to
        // the typed-confirmation gate, "c" would be rejected and we'd
        // get .abort instead.
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: false,
            assumeYes: false,
            isInteractive: { true },
            readConfirmation: { "c" },
            siblingDetector: { [Self.makeSibling()] }
        )
        #expect(action == .proceed, "existing [c]/[w]/[a] path must still resolve 'c' → .proceed; got: \(action)")
    }

    @Test("forceReplace=false, non-TTY, conflict → .abort (existing #253 behaviour preserved)")
    func forceReplaceFalseNonTTYAborts() {
        let action = SaveSiblingGate.gate(
            myTargets: [.search],
            recording: NoopRecording(),
            forceReplace: false,
            assumeYes: false,
            isInteractive: { false },
            readConfirmation: { fatalError("should not be called") },
            siblingDetector: { [Self.makeSibling(pid: 88)] }
        )
        guard case let .abort(reason) = action else {
            Issue.record("expected .abort, got: \(action)")
            return
        }
        #expect(!reason.contains("--force-replace"), "non-force path should NOT mention --force-replace; got: \(reason)")
    }
}

// MARK: - TerminationOutcome shape

@Suite("#722 — SaveSiblingGate.TerminationOutcome shape", .serialized)
struct Issue722TerminationOutcomeShapeTests {
    @Test("allTerminated equals itself")
    func allTerminatedEquatable() {
        #expect(SaveSiblingGate.TerminationOutcome.allTerminated == SaveSiblingGate.TerminationOutcome.allTerminated)
    }

    @Test("stragglers(pids:) preserves the PID list + Equatable on identical PID sets")
    func stragglersEquatable() {
        let a = SaveSiblingGate.TerminationOutcome.stragglers(pids: [42, 99])
        let b = SaveSiblingGate.TerminationOutcome.stragglers(pids: [42, 99])
        let c = SaveSiblingGate.TerminationOutcome.stragglers(pids: [42])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("allTerminated != stragglers (even when stragglers is empty — distinct cases by intent)")
    func distinctCases() {
        let allTerm = SaveSiblingGate.TerminationOutcome.allTerminated
        let empty = SaveSiblingGate.TerminationOutcome.stragglers(pids: [])
        #expect(allTerm != empty, "the cases mean different things and must not collapse")
    }
}

// MARK: - Pass-2 fix: graceSeconds=0 = no-grace SIGKILL-immediately

@Suite("#722 — SaveSiblingGate.terminateSiblings graceSeconds boundary", .serialized)
struct Issue722GraceSecondsBoundaryTests {
    private final class NoopRecording: LoggingModels.Logging.Recording, @unchecked Sendable {
        func record(_: String, level _: LoggingModels.Logging.Level, category _: LoggingModels.Logging.Category) {}
        func output(_: String) {}
    }

    @Test("graceSeconds=0 skips the SIGTERM grace window — SIGKILL-immediately path")
    func zeroGraceImmediate() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["30"]
        try task.run()
        defer { task.terminate() }
        let pid = task.processIdentifier

        let start = Date()
        let outcome = SaveSiblingGate.terminateSiblings(
            pids: [pid],
            graceSeconds: 0,
            pollInterval: 0.1,
            recording: NoopRecording(),
            verifier: { $0 == pid }
        )
        let elapsed = Date().timeIntervalSince(start)

        // graceSeconds=0 → deadline equals "now" → while-loop never
        // enters → straight to SIGKILL → settle window (1 poll = 0.1s).
        // Total elapsed should be well below a full second.
        #expect(elapsed < 0.5, "graceSeconds=0 should fall through to SIGKILL immediately; got \(elapsed)s")
        #expect(outcome == .allTerminated, "SIGKILL on a real /bin/sleep should succeed; got: \(outcome)")
    }
}

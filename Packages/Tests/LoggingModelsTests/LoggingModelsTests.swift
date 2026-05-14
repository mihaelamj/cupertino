import Foundation
import LoggingModels
import Testing

// Tests pin the `Logging.Recording` GoF Strategy seam (1994 p. 315):
// the protocol + level/category value types + the NoopRecording test
// stub. Concrete production behaviour (`Logging.LiveRecording` in the
// `Logging` target) is covered by the LoggingTests bundle.

// MARK: - Namespace

@Suite("Logging namespace anchor")
struct LoggingNamespaceTests {
    @Test("Logging enum is accessible from LoggingModels (Foundation-only)")
    func namespaceExists() {
        let _: Logging.Type = Logging.self
    }
}

// MARK: - Logging.Level

@Suite("Logging.Level")
struct LoggingLevelTests {
    @Test("Raw values run 0..3 ascending by severity")
    func rawValuesAscending() {
        #expect(Logging.Level.debug.rawValue == 0)
        #expect(Logging.Level.info.rawValue == 1)
        #expect(Logging.Level.warning.rawValue == 2)
        #expect(Logging.Level.error.rawValue == 3)
    }

    @Test("Comparable preserves severity ordering")
    func comparableOrder() {
        #expect(Logging.Level.debug < Logging.Level.info)
        #expect(Logging.Level.info < Logging.Level.warning)
        #expect(Logging.Level.warning < Logging.Level.error)
        #expect(Logging.Level.error > Logging.Level.debug)
    }

    @Test("description is the canonical token used by file output lines")
    func descriptionTokens() {
        #expect(Logging.Level.debug.description == "DEBUG")
        #expect(Logging.Level.info.description == "INFO")
        #expect(Logging.Level.warning.description == "WARN")
        #expect(Logging.Level.error.description == "ERROR")
    }
}

// MARK: - Logging.Category

@Suite("Logging.Category")
struct LoggingCategoryTests {
    @Test("Canonical cases cover every subsystem the OSLog backend routes")
    func canonicalCases() {
        let values = Set(Logging.Category.allCases.map(\.rawValue))
        #expect(values == [
            "crawler", "mcp", "search", "cli", "transport",
            "evolution", "samples", "packages", "archive", "hig",
        ])
    }

    @Test("Raw values are stable identifiers (don't free-rename them)")
    func stableRawValues() {
        #expect(Logging.Category.crawler.rawValue == "crawler")
        #expect(Logging.Category.cli.rawValue == "cli")
        #expect(Logging.Category.mcp.rawValue == "mcp")
        #expect(Logging.Category.search.rawValue == "search")
    }
}

// MARK: - Logging.Recording protocol

@Suite("Logging.Recording protocol")
struct LoggingRecordingProtocolTests {
    /// Spy recorder that captures everything it sees.
    private final class CapturingRecorder: Logging.Recording, @unchecked Sendable {
        struct Record {
            let message: String
            let level: Logging.Level
            let category: Logging.Category
        }

        private let lock = NSLock()
        private var _records: [Record] = []
        private var _outputs: [String] = []

        var records: [Record] {
            lock.lock(); defer { lock.unlock() }
            return _records
        }

        var outputs: [String] {
            lock.lock(); defer { lock.unlock() }
            return _outputs
        }

        func record(_ message: String, level: Logging.Level, category: Logging.Category) {
            lock.lock(); defer { lock.unlock() }
            _records.append(Record(message: message, level: level, category: category))
        }

        func output(_ message: String) {
            lock.lock(); defer { lock.unlock() }
            _outputs.append(message)
        }
    }

    @Test("Convenience methods route to record() with the correct level")
    func conveniencesRouteByLevel() {
        let spy = CapturingRecorder()
        let recorder: any Logging.Recording = spy
        recorder.debug("d", category: .crawler)
        recorder.info("i", category: .cli)
        recorder.warning("w", category: .mcp)
        recorder.error("e", category: .search)
        #expect(spy.records.count == 4)
        #expect(spy.records[0].level == .debug && spy.records[0].message == "d" && spy.records[0].category == .crawler)
        #expect(spy.records[1].level == .info && spy.records[1].message == "i" && spy.records[1].category == .cli)
        #expect(spy.records[2].level == .warning && spy.records[2].message == "w" && spy.records[2].category == .mcp)
        #expect(spy.records[3].level == .error && spy.records[3].message == "e" && spy.records[3].category == .search)
    }

    @Test("Convenience methods default the category to .cli when not provided")
    func defaultCategoryIsCLI() {
        let spy = CapturingRecorder()
        let recorder: any Logging.Recording = spy
        recorder.info("x")
        #expect(spy.records.count == 1)
        #expect(spy.records.first?.category == .cli)
    }

    @Test("output() bypasses level/category and lands in a separate sink")
    func outputBypassesLevels() {
        let spy = CapturingRecorder()
        let recorder: any Logging.Recording = spy
        recorder.output("user-facing line")
        #expect(spy.outputs == ["user-facing line"])
        #expect(spy.records.isEmpty)
    }
}

// MARK: - Logging.NoopRecording

@Suite("Logging.NoopRecording")
struct LoggingNoopRecordingTests {
    @Test("record() drops every input, never throws")
    func recordIsInert() {
        let noop = Logging.NoopRecording()
        // Run every level through every category; the contract is "no
        // side effects, no crash". Nothing to assert except that we
        // make it through the loop.
        for category in Logging.Category.allCases {
            noop.debug("d", category: category)
            noop.info("i", category: category)
            noop.warning("w", category: category)
            noop.error("e", category: category)
        }
    }

    @Test("output() drops every input, never throws")
    func outputIsInert() {
        let noop = Logging.NoopRecording()
        noop.output("a")
        noop.output("")
        noop.output(String(repeating: "x", count: 10_000))
    }

    @Test("Conforms to Logging.Recording (witness check)")
    func conformsToRecording() {
        let _: any Logging.Recording = Logging.NoopRecording()
    }
}

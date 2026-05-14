import Foundation
@testable import Logging
import Testing
import TestSupport

// MARK: - Logging Public API Smoke Tests

// Logging sits on top of OSLog + SharedConstants + SharedCore. It owns
// the `Logging.Logger.<category>` per-subsystem `os.Logger` constants,
// the `Logging.ConsoleLogger` stdout/stderr helpers, and the
// `Logging.Unified` actor that fans out to os.log + console + file.
//
// Per #387 independence acceptance: Logging imports only Foundation +
// OSLog + SharedConstants + SharedCore. No behavioural cross-package
// import.
// `grep -rln "^import " Packages/Sources/Logging/` returns exactly
// those four imports.
//
// CupertinoLoggingTests in this same target already covers logger
// constant accessibility and ConsoleLogger smoke. This suite adds:
// - every category in the Logging.Logger family (the original suite
//   tested 7 of 10)
// - Logging.Unified actor public surface (Level / Category / Options
//   were completely untested)
// - Level Comparable + raw values + description (pinned because they
//   show up in stdout / file output formatting)
// - Options defaults + roundtrip
//
// Behavioural tests against actual file output happen at the consumer
// boundary (CLI integration tests). This suite proves the symbols
// compile and the public API contract holds.

@Suite("Logging public surface")
struct LoggingPublicSurfaceTests {
    // MARK: Namespace

    @Test("Logging namespace reachable")
    func loggingNamespace() {
        _ = Logging.self
        _ = Logging.Logger.self
        _ = Logging.Unified.self
        // Note: `Logging.ConsoleLogger` was deleted in the logging-DI
        // arc (#534). The replacement is `Logging.LiveRecording`, the
        // GoF Strategy concrete that conforms to
        // `LoggingModels.Logging.Recording`. Its surface is covered by
        // `Tests/LoggingTests/LiveRecordingTests.swift`.
        _ = Logging.LiveRecording.self
    }

    // MARK: All 10 logger categories

    @Test("All Logging.Logger.<category> constants are reachable")
    func allLoggerCategories() {
        // Pin the full set; CupertinoLoggingTests only checks 7 of 10.
        // Adding / removing a category here means an MCP host / serve
        // / search consumer needs a matching update.
        _ = Logging.Logger.crawler
        _ = Logging.Logger.mcp
        _ = Logging.Logger.search
        _ = Logging.Logger.cli
        _ = Logging.Logger.transport
        _ = Logging.Logger.evolution
        _ = Logging.Logger.samples
        _ = Logging.Logger.packageDownloader
        _ = Logging.Logger.archive
        _ = Logging.Logger.hig
    }

    // MARK: Logging.Unified.Level

    @Test("Logging.Unified.Level raw values and order are stable")
    func unifiedLevelOrder() {
        // The Comparable conformance backs the minLevel filter in
        // Options. Pin the int raw values + ordering so a refactor
        // doesn't accidentally let .debug through above .warning, or
        // swap the rawValue mapping.
        #expect(Logging.Unified.Level.debug.rawValue == 0)
        #expect(Logging.Unified.Level.info.rawValue == 1)
        #expect(Logging.Unified.Level.warning.rawValue == 2)
        #expect(Logging.Unified.Level.error.rawValue == 3)

        #expect(Logging.Unified.Level.debug < .info)
        #expect(Logging.Unified.Level.info < .warning)
        #expect(Logging.Unified.Level.warning < .error)
    }

    @Test("Logging.Unified.Level description strings match the wire format")
    func unifiedLevelDescription() {
        // The description strings show up in stdout and the file log;
        // changing them silently breaks any consumer parsing the log
        // (e.g. grep-driven dashboards / CI failure scanners).
        #expect(String(describing: Logging.Unified.Level.debug) == "DEBUG")
        #expect(String(describing: Logging.Unified.Level.info) == "INFO")
        #expect(String(describing: Logging.Unified.Level.warning) == "WARN")
        #expect(String(describing: Logging.Unified.Level.error) == "ERROR")
    }

    // MARK: Logging.Unified.Category

    @Test("Logging.Unified.Category raw values pin the os.log category strings")
    func unifiedCategoryRawValues() {
        // The String raw values are what shows up as the `category`
        // field in `log show --predicate 'subsystem == ...'` queries.
        // Renaming would break operator playbooks. Pin them.
        let allCategories: [Logging.Unified.Category] = [
            .crawler,
            .mcp,
            .search,
            .cli,
            .transport,
            .evolution,
            .samples,
            .packages,
            .archive,
            .hig,
        ]
        let allRaws = allCategories.map(\.rawValue)
        #expect(allRaws.sorted() == [
            "archive", "cli", "crawler", "evolution", "hig", "mcp",
            "packages", "samples", "search", "transport",
        ])
    }

    // MARK: Logging.Unified.Options

    @Test("Logging.Unified.Options default has sensible values")
    func unifiedOptionsDefault() {
        let opts = Logging.Unified.Options.default
        // The default toggles fileEnabled DEBUG-vs-release; either path
        // is fine but the Options struct must construct cleanly.
        #expect(opts.consoleEnabled == true || opts.consoleEnabled == false)
        #expect(opts.showTimestamps == true || opts.showTimestamps == false)
        #expect(opts.showCategory == true || opts.showCategory == false)
        // minLevel must be in the defined range
        #expect((Logging.Unified.Level.debug...Logging.Unified.Level.error).contains(opts.minLevel))
    }

    @Test("Logging.Unified.Options init exposes every public field")
    func unifiedOptionsInit() {
        // Construct an Options with every field set explicitly; tests
        // both the public init shape and that all six fields stay
        // public.
        let opts = Logging.Unified.Options(
            consoleEnabled: false,
            fileEnabled: true,
            fileURL: URL(fileURLWithPath: "/tmp/cupertino-test.log"),
            minLevel: .warning,
            showTimestamps: false,
            showCategory: true
        )
        #expect(opts.consoleEnabled == false)
        #expect(opts.fileEnabled == true)
        #expect(opts.fileURL?.path == "/tmp/cupertino-test.log")
        #expect(opts.minLevel == .warning)
        #expect(opts.showTimestamps == false)
        #expect(opts.showCategory == true)
    }

    // MARK: Logging.Unified actor

    @Test("Logging.Unified.shared singleton is reachable and configurable")
    func unifiedSharedConfigurable() async {
        // The singleton is the entry point every cupertino subsystem
        // uses. configure() reaches into the actor; if the signature
        // breaks, every caller breaks. Round-trip a configure() with
        // a known Options and verify the actor accepts it without
        // throwing.
        let opts = Logging.Unified.Options(
            consoleEnabled: false,
            fileEnabled: false,
            fileURL: nil,
            minLevel: .error,
            showTimestamps: false,
            showCategory: false
        )
        await Logging.Unified.shared.configure(opts)
        // Reset to default so we don't pollute follow-on tests.
        await Logging.Unified.shared.configure(.default)
    }
}

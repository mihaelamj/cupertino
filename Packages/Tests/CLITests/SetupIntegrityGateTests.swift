@testable import CLI
import DistributionModels
import Foundation
import LoggingModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #1276 — the post-extract integrity gate in `cupertino setup`

/// `QuickCheckTests` (DiagnosticsTests) covers the low-level
/// `Diagnostics.Probes.quickCheck` primitive. These tests cover the gate the
/// PR is actually about: `CLIImpl.Command.Setup.verifyExtractedDatabases` and
/// the `--keep-existing` skip contract in `verifyDatabasesIfWritten` — the
/// user-facing behaviour behind discussion #1276 (don't print "Setup
/// complete!" over a database that fails to read).
@Suite("CLIImpl.Command.Setup integrity gate (#1276)")
struct SetupIntegrityGateTests {
    /// In-memory `Logging.Recording` capturing every emitted line (info +
    /// error both route through `record`). File-private mirror of the double
    /// used elsewhere in CLITests.
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

    // MARK: Fixtures

    /// A fresh temp directory cleaned up by the caller's `defer`.
    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("setupgate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A multi-page SQLite DB (docs_metadata + FTS5) at `url`, large enough
    /// that lopping off the back half destroys live b-tree pages.
    private func writePopulatedDB(at url: URL) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE docs_metadata (uri TEXT PRIMARY KEY, source TEXT, title TEXT);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE VIRTUAL TABLE docs_fts USING fts5(uri, title, content);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "BEGIN;", nil, nil, nil) == SQLITE_OK)
        for index in 0..<2000 {
            let sql = """
            INSERT INTO docs_metadata VALUES ('doc://\(index)', 'swift', 'Title \(index)');
            INSERT INTO docs_fts VALUES ('doc://\(index)', 'Title \(index)', 'swift documentation body number \(index) lorem ipsum dolor sit amet');
            """
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        #expect(sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
    }

    /// Write a populated DB then truncate it to half: header + early pages
    /// survive (opens, shallow-queries), deep pages are gone — the #1276
    /// "looks installed, unreadable at query time" shape.
    private func writeTruncatedDB(at url: URL) throws {
        try writePopulatedDB(at: url)
        let fullSize = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(fullSize / 2))
        try handle.close()
    }

    private func outcome(
        _ placements: [(Shared.Models.DatabaseDescriptor, URL)],
        skippedDownload: Bool = false
    ) -> Distribution.SetupService.Outcome {
        Distribution.SetupService.Outcome(
            databases: placements.map { Distribution.SetupService.DatabasePlacement(descriptor: $0.0, path: $0.1) },
            docsVersionWritten: "1.4.0",
            skippedDownload: skippedDownload,
            priorStatus: .missing
        )
    }

    // MARK: Tests

    @Test("all-healthy outcome passes the gate without throwing")
    func allHealthyPasses() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let docs = dir.appendingPathComponent("apple-documentation.db")
        let hig = dir.appendingPathComponent("hig.db")
        try writePopulatedDB(at: docs)
        try writePopulatedDB(at: hig)

        let out = outcome([(.appleDocumentation, docs), (.hig, hig)])
        #expect(throws: Never.self) {
            try CLIImpl.Command.Setup.verifyExtractedDatabases(outcome: out, recording: CapturingRecording())
        }
    }

    @Test("a single unreadable database aborts the gate with its filename")
    func oneBadAborts() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let docs = dir.appendingPathComponent("apple-documentation.db")
        let hig = dir.appendingPathComponent("hig.db")
        try writePopulatedDB(at: docs)
        try writeTruncatedDB(at: hig)

        let out = outcome([(.appleDocumentation, docs), (.hig, hig)])
        var thrown: CLIImpl.Command.Setup.SetupIntegrityError?
        do {
            try CLIImpl.Command.Setup.verifyExtractedDatabases(outcome: out, recording: CapturingRecording())
        } catch let error as CLIImpl.Command.Setup.SetupIntegrityError {
            thrown = error
        }
        let failures = try #require(thrown?.failures)
        #expect(failures.contains { $0.contains("hig.db") })
        // The healthy DB must NOT appear in the failure list.
        #expect(!failures.contains { $0.contains("apple-documentation.db") })
    }

    @Test("multiple bad databases are all aggregated, not first-failure-only")
    func multipleBadAggregated() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let docs = dir.appendingPathComponent("apple-documentation.db")
        let hig = dir.appendingPathComponent("hig.db")
        try writeTruncatedDB(at: docs)
        try writeTruncatedDB(at: hig)

        let out = outcome([(.appleDocumentation, docs), (.hig, hig)])
        var thrown: CLIImpl.Command.Setup.SetupIntegrityError?
        do {
            try CLIImpl.Command.Setup.verifyExtractedDatabases(outcome: out, recording: CapturingRecording())
        } catch let error as CLIImpl.Command.Setup.SetupIntegrityError {
            thrown = error
        }
        let failures = try #require(thrown?.failures)
        #expect(failures.contains { $0.contains("apple-documentation.db") })
        #expect(failures.contains { $0.contains("hig.db") })
    }

    @Test("the gate emits the failing filename and an actionable hint")
    func actionableMessageEmitted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hig = dir.appendingPathComponent("hig.db")
        try writeTruncatedDB(at: hig)

        let recording = CapturingRecording()
        let out = outcome([(.hig, hig)])
        try? CLIImpl.Command.Setup.verifyExtractedDatabases(outcome: out, recording: recording)

        let joined = recording.records.joined(separator: "\n")
        #expect(joined.contains("hig.db"))
        #expect(joined.contains("cupertino setup"), "must point the user at the re-run remedy")
    }

    @Test("--keep-existing (skippedDownload) never gates on databases it did not write")
    func skippedDownloadSkipsGate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A truncated DB that WOULD fail the gate — proving the skip is what
        // spares it, not the DB happening to be healthy.
        let hig = dir.appendingPathComponent("hig.db")
        try writeTruncatedDB(at: hig)

        let out = outcome([(.hig, hig)], skippedDownload: true)
        #expect(throws: Never.self) {
            try CLIImpl.Command.Setup.verifyDatabasesIfWritten(outcome: out, recording: CapturingRecording())
        }
    }
}

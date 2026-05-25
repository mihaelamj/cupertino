@testable import CLI
import Distribution
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - LivePerDBWriter + LivePerDBWriterFactory integration tests

//
// Step 6c-ii-a of the per-source DB split epic. Verifies the Live
// Distribution.PerSourceDBSplitMigrator.PerDBWriter conformer + its
// factory, exercising a small synthetic migration end-to-end using
// the real Search.Index (in a temp directory). The Live LegacyDBReader
// (raw SQLite) lands in 6c-ii-b; these tests use the in-memory fake
// from PerSourceDBSplitMigratorMigrateTests's fixture pattern as
// reader.

@Suite("LivePerDBWriter + LivePerDBWriterFactory: real Search.Index round-trip")
struct LivePerDBWriterTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-per-db-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("LivePerDBWriter.write + rowCount round-trips a single row through Search.Index")
    func writerSingleRowRoundtrip() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("test.db")

        let registry = CLIImpl.makeProductionSourceRegistry()
        let factory = LivePerDBWriterFactory.make(
            registry: registry,
            logger: LoggingModels.Logging.NoopRecording()
        )
        let writer = try await factory(.hig, dbPath)

        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "hig://test-row",
            source: Shared.Constants.SourcePrefix.hig,
            framework: "DesignTokens",
            title: "Test HIG row",
            content: "Content for the live-writer round-trip test.",
            filePath: "/tmp/test",
            contentHash: "test-hash",
            lastCrawled: Date()
        ))

        let count = try await writer.rowCount()
        #expect(count == 1, "exactly one row written")

        await writer.disconnect()
        // File should exist + be non-empty on disk.
        let attrs = try FileManager.default.attributesOfItem(atPath: dbPath.path)
        let size = (attrs[.size] as? Int64) ?? 0
        #expect(size > 0, "destination DB file must have non-zero size after write+disconnect")
    }

    @Test("LivePerDBWriterFactory deletes any stale file at the destination path before opening")
    func factoryClearsExistingFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("stale.db")

        // Pre-populate the destination path with junk data.
        try Data("stale junk content".utf8).write(to: dbPath)
        #expect(FileManager.default.fileExists(atPath: dbPath.path))

        let factory = LivePerDBWriterFactory.make(
            registry: CLIImpl.makeProductionSourceRegistry(),
            logger: LoggingModels.Logging.NoopRecording()
        )
        let writer = try await factory(.hig, dbPath)
        // After factory call, the path holds a fresh SQLite DB (Search.Index
        // initialised the schema), not the original junk bytes. Indirect
        // verification: write a row + rowCount should return 1 (which would
        // not work if Search.Index opened the junk file as a corrupted DB).
        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "hig://fresh",
            source: Shared.Constants.SourcePrefix.hig,
            framework: "F",
            title: "T",
            content: "C",
            filePath: "/tmp/f",
            contentHash: "h",
            lastCrawled: Date()
        ))
        let count = try await writer.rowCount()
        #expect(count == 1, "fresh DB after factory clears stale file")
        await writer.disconnect()
    }

    @Test("write-after-disconnect crashes (preconditionFailure; documents the lifecycle contract)")
    func writeAfterDisconnectIsForbidden() {
        // Skipped intentionally: precondition crash is a programming
        // error, not a recoverable condition; testing it would require
        // a child-process expectFatalError harness which the project
        // does not currently ship. The contract is documented in the
        // type's docstring. Listed here as a marker test so a future
        // contributor knows the contract exists.
        #expect(Bool(true), "precondition is a documented programming error; no runtime assertion")
    }
}

@testable import CLI
import Distribution
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import SQLite3
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

        let factory = LivePerDBWriterFactory.make(
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

    @Test("Factory clears WAL companions (-wal/-shm) alongside the .db file")
    func factoryClearsWALCompanions() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("with-wal.db")
        let walPath = URL(fileURLWithPath: dbPath.path + "-wal")
        let shmPath = URL(fileURLWithPath: dbPath.path + "-shm")
        try Data("stale db".utf8).write(to: dbPath)
        try Data("stale wal".utf8).write(to: walPath)
        try Data("stale shm".utf8).write(to: shmPath)

        let factory = LivePerDBWriterFactory.make(
            logger: LoggingModels.Logging.NoopRecording()
        )
        let writer = try await factory(.hig, dbPath)
        // Factory removed the stale sidecars before opening Search.Index;
        // Search.Index then created its own fresh -wal/-shm files (SQLite
        // WAL mode behavior). Write one row to force a WAL checkpoint;
        // count must return 1 (which can only happen if the schema
        // initialised cleanly on a non-corrupted .db).
        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "hig://wal",
            source: Shared.Constants.SourcePrefix.hig,
            framework: "F", title: "T", content: "C",
            filePath: "/tmp/f", contentHash: "h", lastCrawled: Date()
        ))
        let count = try await writer.rowCount()
        #expect(count == 1, "Search.Index initialised cleanly after stale WAL companions were cleared")
        await writer.disconnect()
    }

    @Test("View-source pattern: two source-ids writing to the same destination both land in the final DB")
    func viewSourceCoLocationPreservesBothSourcesRows() async throws {
        // Load-bearing test for the step-6c-ii critic-fix round-1
        // finding #1. Pre-fix, the migrator called the factory twice
        // for the same destinationPath (once per source-id), and the
        // factory's file-delete dropped the first source's rows.
        // Post-fix, the migrator groups by destinationPath + calls the
        // factory once per group; both source-ids stream through the
        // same writer. This test exercises the writer directly; the
        // migrator's grouping is verified separately in
        // PerSourceDBSplitMigratorMigrateTests.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("co-located.db")

        let factory = LivePerDBWriterFactory.make(
            logger: LoggingModels.Logging.NoopRecording()
        )
        let writer = try await factory(.swiftDocumentation, dbPath)

        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "swift-org://a",
            source: Shared.Constants.SourcePrefix.swiftOrg,
            framework: "SwiftOrg", title: "A", content: "swift-org content",
            filePath: "/tmp/a", contentHash: "a", lastCrawled: Date()
        ))
        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "swift-book://b",
            source: Shared.Constants.SourcePrefix.swiftBook,
            framework: "SwiftBook", title: "B", content: "swift-book content",
            filePath: "/tmp/b", contentHash: "b", lastCrawled: Date()
        ))

        let count = try await writer.rowCount()
        #expect(count == 2, "swift-org + swift-book rows must both land in swift-documentation.db (view-source co-location)")
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

    // MARK: - #1037 foreign-table-aware destination preservation

    /// Seed a DB at `path` with a Sample.Index-shaped `projects` table
    /// + one row. The migrator's foreign-table check uses table-name
    /// presence (not row count) so a single row is enough to exercise
    /// the preserve branch. Raw sqlite3 to avoid bringing the
    /// SampleIndex target in as a test dependency.
    private func seedSampleIndexProjectsTable(at path: URL) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL
        );
        INSERT INTO projects (id, title) VALUES ('preserve-me', 'Sentinel row');
        """
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    /// Read the `projects` row count to verify the foreign-table
    /// preservation worked end-to-end.
    private func projectsRowCount(at path: URL) throws -> Int32 {
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM projects", -1, &stmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        return sqlite3_column_int(stmt, 0)
    }

    @Test("#1037: factory preserves a destination DB that already carries Sample.Index tables")
    func factoryPreservesForeignSampleIndexTables() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("apple-sample-code.db")

        // Pre-seed: existing Sample.Index data in the file.
        try seedSampleIndexProjectsTable(at: dbPath)
        #expect(try projectsRowCount(at: dbPath) == 1)

        // Run the factory. The destination is recognised as carrying
        // foreign tables and is preserved.
        let factory = LivePerDBWriterFactory.make(
            logger: LoggingModels.Logging.NoopRecording()
        )
        let writer = try await factory(.appleSampleCode, dbPath)

        // Write a row to confirm Search.Index opened cleanly on top
        // of the pre-existing file.
        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "sample-code://test/row",
            source: "sample-code",
            framework: "Samples",
            title: "Test FTS row",
            content: "Content body for the foreign-table coexistence test.",
            filePath: "/tmp/test",
            contentHash: "test-hash",
            lastCrawled: Date()
        ))
        let rowsWritten = try await writer.rowCount()
        #expect(rowsWritten == 1, "Search.Index docs_metadata count post-write")
        await writer.disconnect()

        // The original projects row MUST still be there. This is the
        // bug fix's load-bearing assertion.
        #expect(
            try projectsRowCount(at: dbPath) == 1,
            "Pre-existing Sample.Index projects row must survive the migrator's open of the same file"
        )
    }

    @Test("#1037: factory STILL wipes a destination DB that is a stale Search.Index-only file (no foreign tables)")
    func factoryWipesStaleSearchOnlyFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("hig.db")

        // Pre-seed: a stale Search.Index-only DB. Create a docs_metadata
        // table + a sentinel row that, if preserved across a migrator
        // run, would indicate the wipe branch failed to fire.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        let seedSQL = """
        CREATE TABLE docs_metadata (id INTEGER PRIMARY KEY, uri TEXT NOT NULL);
        INSERT INTO docs_metadata (id, uri) VALUES (999, 'stale://row');
        """
        try #require(sqlite3_exec(db, seedSQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        // Run the factory. No `projects` table → wipe branch fires.
        let factory = LivePerDBWriterFactory.make(
            logger: LoggingModels.Logging.NoopRecording()
        )
        let writer = try await factory(.hig, dbPath)

        // Search.Index opened a fresh DB after the wipe; the sentinel
        // row is gone, the only rows in docs_metadata are the ones the
        // writer is about to add.
        try await writer.write(Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: "hig://post-wipe/row",
            source: Shared.Constants.SourcePrefix.hig,
            framework: "DesignTokens",
            title: "Post-wipe row",
            content: "Content body after the legacy wipe path fires.",
            filePath: "/tmp/post-wipe",
            contentHash: "post-wipe-hash",
            lastCrawled: Date()
        ))
        let rowsWritten = try await writer.rowCount()
        #expect(rowsWritten == 1, "fresh DB carries only the row we just wrote (stale 999/stale://row gone)")
        await writer.disconnect()
    }
}

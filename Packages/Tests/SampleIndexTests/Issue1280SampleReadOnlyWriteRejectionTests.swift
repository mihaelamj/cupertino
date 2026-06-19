import Foundation
import LoggingModels
@testable import SampleIndex
import SampleIndexModels
@testable import SampleIndexSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #1280 — sample reader rejects writes on the read path

/// Sibling of `Issue1280SearchReadOnlyWriteRejectionTests` for the
/// `apple-sample-code.db` reader. `Sample.Index.Database` declares
/// `readOnly: Bool = false` (default OPEN-FOR-WRITE), so its read-only
/// guarantee rests on every read / serve / list caller passing
/// `readOnly: true`. This hermetic, CI-runnable test constructs the reader
/// the production read path's way, attempts INSERT / UPDATE / DELETE through
/// the reader's own connection, asserts `SQLITE_READONLY`, and proves the
/// on-disk row count is unchanged via an independent handle. Related: #1194,
/// #1280.
@Suite("#1280 — Sample.Index.Database rejects writes on the read path", .serialized)
struct Issue1280SampleReadOnlyWriteRejectionTests {
    private static let currentSchemaVersion: Int32 = 4

    /// A samples-shaped, rollback-mode DB: a `projects` table with two rows and
    /// a `samples_schema_version` row stamped at the current version (so it
    /// passes the #1279 read-open gate). No sidecars.
    private func makeSamplesDB() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ro-1280-samples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("apple-sample-code.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        let sql = """
        CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL);
        INSERT INTO projects (id, title) VALUES ('p1', 'One'), ('p2', 'Two');
        CREATE TABLE samples_schema_version (version INTEGER NOT NULL);
        INSERT INTO samples_schema_version (version) VALUES (\(Self.currentSchemaVersion));
        PRAGMA journal_mode=DELETE;
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }

    private func projectCount(at url: URL) -> Int32 {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM projects;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW
        else { return -1 }
        return sqlite3_column_int(stmt, 0)
    }

    @Test("Sample.Index.Database(readOnly: true) rejects INSERT/UPDATE/DELETE and leaves rows intact")
    func sampleReaderRejectsWrites() async throws {
        let dbURL = try makeSamplesDB()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let db = try await Sample.Index.Database(dbPath: dbURL, logger: Logging.NoopRecording(), readOnly: true)
        defer { Task { await db.disconnect() } }

        #expect(await db.attemptWriteForReadOnlyAudit("INSERT INTO projects (id, title) VALUES ('p3', 'Three');") == SQLITE_READONLY)
        #expect(await db.attemptWriteForReadOnlyAudit("UPDATE projects SET title = 'X' WHERE id = 'p1';") == SQLITE_READONLY)
        #expect(await db.attemptWriteForReadOnlyAudit("DELETE FROM projects WHERE id = 'p1';") == SQLITE_READONLY)
        #expect(projectCount(at: dbURL) == 2)
    }
}

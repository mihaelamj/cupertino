import Foundation
import SQLite3
import SQLiteSupport
import Testing

// MARK: - SQLiteSupport.openReadOnly contract (#1194)

// Every cupertino reader (`Search.Index`, `Sample.Index.Database`,
// `Search.PackageQuery`) opens through this one helper, so proving the helper
// returns a connection that can read but cannot write or delete rows proves
// the read-only guarantee for every database uniformly.

@Suite("SQLiteSupport.openReadOnly read-only contract (#1194)")
struct SQLiteSupportReadOnlyTests {
    /// Build a small rollback-mode DB with one row and no sidecars (the shipped
    /// shape, #1192), returning its URL.
    private func makeFixtureDB() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sqlitesupport-1194-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("fixture.db")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "INSERT INTO t (id, name) VALUES (1, 'a'), (2, 'b');", nil, nil, nil) == SQLITE_OK)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }

    @Test("a read-only connection can SELECT but cannot INSERT or DELETE")
    func readOnlyConnectionRejectsWrites() throws {
        let dbURL = try makeFixtureDB()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let db = try SQLiteSupport.openReadOnly(at: dbURL)
        defer { sqlite3_close(db) }

        // SELECT works.
        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM t;", -1, &stmt, nil) == SQLITE_OK)
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == 2)
        sqlite3_finalize(stmt)

        // INSERT is rejected: the handle is physically read-only.
        let insertRC = sqlite3_exec(db, "INSERT INTO t (id, name) VALUES (3, 'c');", nil, nil, nil)
        #expect(insertRC == SQLITE_READONLY)

        // DELETE is rejected.
        let deleteRC = sqlite3_exec(db, "DELETE FROM t WHERE id = 1;", nil, nil, nil)
        #expect(deleteRC == SQLITE_READONLY)

        // UPDATE is rejected.
        let updateRC = sqlite3_exec(db, "UPDATE t SET name = 'z' WHERE id = 1;", nil, nil, nil)
        #expect(updateRC == SQLITE_READONLY)

        // Row count is unchanged after the rejected writes.
        var verify: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM t;", -1, &verify, nil) == SQLITE_OK)
        #expect(sqlite3_step(verify) == SQLITE_ROW)
        #expect(sqlite3_column_int(verify, 0) == 2)
        sqlite3_finalize(verify)
    }
}

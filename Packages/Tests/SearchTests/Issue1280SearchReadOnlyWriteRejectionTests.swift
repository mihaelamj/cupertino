import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #1280 — read-only write-rejection asserted at the reader object level

/// The #1194 release headline is "an end user cannot write or delete rows in
/// any shipped database". Before #1280 that was tested only on the
/// `SQLiteSupport.openReadOnly` helper in isolation; nothing attempted a write
/// through the real reader objects the production read / serve path
/// constructs. The guarantee rested on a per-call-site contract:
/// `Search.Connection` declares `readOnly: Bool = false` (default
/// OPEN-FOR-WRITE), so the read-only chokepoint is only reached if every
/// caller passes `readOnly: true`. A refactor that dropped the flag would ship
/// a writable user DB with every other test still green.
///
/// These hermetic, CI-runnable tests (no snapshot, no `CupertinoCLI.available`
/// gate) construct each Search-family reader the way production does, attempt
/// INSERT / UPDATE / DELETE through the reader's OWN connection, assert
/// `SQLITE_READONLY`, and prove the on-disk row count is unchanged via an
/// independent handle. The sample reader is covered by the sibling suite
/// `Issue1280SampleReadOnlyWriteRejectionTests`. Related: #1194.
@Suite("#1280 — Search-family readers reject writes on the read path")
struct Issue1280SearchReadOnlyWriteRejectionTests {
    // MARK: - Fixtures

    /// A rollback-mode (DELETE journal) DB with a `t(id, name)` table holding
    /// two rows, optionally stamped at `userVersion`. No sidecars: the on-disk
    /// shape of a freshly-extracted shipped bundle DB.
    private func makeDocShapedDB(userVersion: Int32?) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ro-1280-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("doc.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        var sql = """
        CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
        INSERT INTO t (id, name) VALUES (1, 'a'), (2, 'b');
        """
        if let userVersion { sql += "\nPRAGMA user_version = \(userVersion);" }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }

    /// A packages-shaped, rollback-mode DB stamped at the current packages
    /// schema version (5) so it passes the #1279 read-open gate, with one FTS
    /// row. No sidecars.
    private func makePackagesDB() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ro-1280-pkg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("packages.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        let sql = """
        CREATE VIRTUAL TABLE package_files_fts USING fts5(
            package_id UNINDEXED, owner UNINDEXED, repo UNINDEXED, module UNINDEXED,
            relpath UNINDEXED, kind UNINDEXED, title, content, symbols,
            tokenize='porter unicode61'
        );
        INSERT INTO package_files_fts
            (package_id, owner, repo, module, relpath, kind, title, content, symbols)
        VALUES (1, 'apple', 'swift-log', 'Logging', 'Sources/Logging/Logging.swift',
                'source', 'Logging', 'public struct Logger', 'Logger');
        PRAGMA user_version = 5;
        """ // packages.db schema version (PackageIndex.schemaVersion), so the #1279 read-open gate passes
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }

    /// Count rows in `table` via a fresh independent read-only handle, proving
    /// the on-disk state is unchanged (not just that one connection saw no
    /// write).
    private func rowCount(at url: URL, table: String) -> Int32 {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM \(table);", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW
        else { return -1 }
        return sqlite3_column_int(stmt, 0)
    }

    // MARK: - Search.Connection (the chokepoint with the dangerous `readOnly = false` default)

    @Test("Search.Connection(readOnly: true) rejects INSERT/UPDATE/DELETE and leaves rows intact")
    func searchConnectionRejectsWrites() throws {
        let dbURL = try makeDocShapedDB(userVersion: nil)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let connection = Search.Connection(dbPath: dbURL, logger: Logging.NoopRecording(), readOnly: true)
        try connection.connect()
        defer { connection.disconnect() }

        #expect(sqlite3_exec(connection.database, "INSERT INTO t (id, name) VALUES (3, 'c');", nil, nil, nil) == SQLITE_READONLY)
        #expect(sqlite3_exec(connection.database, "UPDATE t SET name = 'z' WHERE id = 1;", nil, nil, nil) == SQLITE_READONLY)
        #expect(sqlite3_exec(connection.database, "DELETE FROM t WHERE id = 1;", nil, nil, nil) == SQLITE_READONLY)
        #expect(throws: (any Error).self) { try connection.execute("INSERT INTO t (id, name) VALUES (4, 'd');") }
        #expect(rowCount(at: dbURL, table: "t") == 2)
    }

    // MARK: - Search.Index (the doc-source reader for all six doc DBs)

    @Test("Search.Index(readOnly: true) rejects writes through its own connection")
    func searchIndexRejectsWrites() async throws {
        // Stamped at the doc schema version so the read-open schema gate passes.
        let dbURL = try makeDocShapedDB(userVersion: Search.Index.schemaVersion)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty,
            readOnly: true
        )
        defer { Task { await index.disconnect() } }

        let connection = index.connection
        #expect(sqlite3_exec(connection.database, "INSERT INTO t (id, name) VALUES (3, 'c');", nil, nil, nil) == SQLITE_READONLY)
        #expect(sqlite3_exec(connection.database, "DELETE FROM t WHERE id = 1;", nil, nil, nil) == SQLITE_READONLY)
        #expect(rowCount(at: dbURL, table: "t") == 2)
    }

    // MARK: - Search.PackageQuery (the packages-source reader)

    @Test("Search.PackageQuery rejects writes through its own connection")
    func packageQueryRejectsWrites() async throws {
        let dbURL = try makePackagesDB()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let query = try await Search.PackageQuery(dbPath: dbURL)
        defer { Task { await query.disconnect() } }

        let insert = "INSERT INTO package_files_fts (package_id, owner, repo, relpath, kind, title, content, symbols) "
            + "VALUES (2, 'x', 'y', 'z', 'source', 't', 'c', 's');"
        #expect(await query.attemptWriteForReadOnlyAudit(insert) == SQLITE_READONLY)
        #expect(await query.attemptWriteForReadOnlyAudit("DELETE FROM package_files_fts;") == SQLITE_READONLY)
        #expect(rowCount(at: dbURL, table: "package_files_fts") == 1)
    }
}

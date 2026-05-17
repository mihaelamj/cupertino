import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Regression suite for [#749](https://github.com/mihaelamj/cupertino/issues/749).
///
/// `migrateToVersion16()` added `implementation_swift_version` to `docs_metadata`
/// but omitted the final `PRAGMA user_version = 16` stamp. A v16 binary opening a
/// v15 DB ran the migration successfully (column landed on disk) but left
/// `user_version = 15`. `setSchemaVersion()` then saw a non-zero mismatch and
/// threw the #635 guard error — "Refusing to stamp PRAGMA user_version=16 on a DB
/// at user_version=15" — leaving the DB half-migrated and the binary unable to
/// open any pre-existing v15 database.
///
/// The fix appends `PRAGMA user_version = 16` as the last statement in
/// `migrateToVersion16()`. The same omission existed in v3/v6/v7/v10/v11
/// migrators; those receive the same fix here.
@Suite("#749 v15→v16 in-place migration", .serialized)
struct Issue749V15ToV16MigrationTests {
    // MARK: - Helpers

    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue749-\(UUID().uuidString).db")
    }

    private static func writeRawUserVersion(_ value: Int32, at dbURL: URL) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbURL.path)) failed",
            ])
        }
        guard sqlite3_exec(db, "PRAGMA user_version = \(value)", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db)),
            ])
        }
    }

    private static func readRawUserVersion(at dbURL: URL) throws -> Int32 {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestRead", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbURL.path)) failed",
            ])
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW
        else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

    /// Create a minimal v15-shaped docs_metadata without implementation_swift_version.
    private static func buildV15Schema(at dbURL: URL) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "open for v15 schema failed",
            ])
        }
        let ddl = """
        CREATE TABLE docs_metadata (
            uri TEXT PRIMARY KEY,
            source TEXT NOT NULL DEFAULT 'apple-docs',
            framework TEXT NOT NULL,
            language TEXT NOT NULL DEFAULT 'swift',
            kind TEXT NOT NULL DEFAULT 'unknown',
            symbols TEXT,
            file_path TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            last_crawled INTEGER NOT NULL,
            word_count INTEGER NOT NULL,
            source_type TEXT DEFAULT 'apple',
            package_id INTEGER,
            json_data TEXT,
            min_ios TEXT,
            min_macos TEXT,
            min_tvos TEXT,
            min_watchos TEXT,
            min_visionos TEXT,
            availability_source TEXT
        );
        PRAGMA user_version = 15;
        """
        guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "v15 DDL failed: \(String(cString: sqlite3_errmsg(db)))",
            ])
        }
    }

    private static func columnExists(_ column: String, in table: String, at dbURL: URL) throws -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return false }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1), String(cString: name) == column {
                return true
            }
        }
        return false
    }

    // MARK: - A. v15→v16 migration stamps user_version = 16

    @Test("v15 DB opens cleanly under v16 binary and is stamped at user_version=16")
    func v15ToV16MigrationStampsVersion() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        try Self.buildV15Schema(at: dbPath)
        let preMigration = try Self.readRawUserVersion(at: dbPath)
        try #require(preMigration == 15, "pre-condition: DB must start at v15")

        _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        let postMigration = try Self.readRawUserVersion(at: dbPath)
        #expect(
            postMigration == 16,
            "v15→v16 migration must stamp user_version=16, got \(postMigration)"
        )
    }

    // MARK: - B. implementation_swift_version column is reachable post-migration

    @Test("implementation_swift_version column exists in docs_metadata after v15→v16 migration")
    func v15ToV16MigrationAddsColumn() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        try Self.buildV15Schema(at: dbPath)
        let hasColumnBefore = try Self.columnExists("implementation_swift_version",
                                                    in: "docs_metadata", at: dbPath)
        #expect(!hasColumnBefore, "pre-condition: column must not exist in v15 schema")

        _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        let hasColumnAfter = try Self.columnExists("implementation_swift_version",
                                                   in: "docs_metadata", at: dbPath)
        #expect(hasColumnAfter, "implementation_swift_version must exist after v15→v16 migration")
    }

    // MARK: - C. implementation_swift_version column is writable post-migration

    @Test("implementation_swift_version column accepts writes after v15→v16 migration")
    func v15ToV16MigrationColumnIsWritable() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        try Self.buildV15Schema(at: dbPath)
        _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("Failed to open DB for write verification")
            return
        }

        let insertSQL = """
        INSERT INTO docs_metadata
            (uri, framework, file_path, content_hash, last_crawled, word_count,
             implementation_swift_version)
        VALUES ('apple-docs://swiftui/view', 'swiftui', '/docs/view.json',
                'abc123', 0, 10, '5.9');
        """
        guard sqlite3_exec(db, insertSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            Issue.record("INSERT with implementation_swift_version failed: \(msg)")
            return
        }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let selectSQL = "SELECT implementation_swift_version FROM docs_metadata WHERE uri = 'apple-docs://swiftui/view';"
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              let raw = sqlite3_column_text(stmt, 0)
        else {
            Issue.record("SELECT implementation_swift_version returned no row")
            return
        }
        let readBack = String(cString: raw)
        #expect(readBack == "5.9", "round-trip must preserve the written value, got \(readBack)")
    }

    // MARK: - D. migration is idempotent (column already present)

    @Test("v15→v16 migration is idempotent when column already exists")
    func v15ToV16MigrationIsIdempotent() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        try Self.buildV15Schema(at: dbPath)

        // First open: runs migration, stamps v16
        _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        let afterFirst = try Self.readRawUserVersion(at: dbPath)
        try #require(afterFirst == 16)

        // Second open: migration guard fires (currentVersion == schemaVersion), no re-run
        await #expect(throws: Never.self) {
            _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        }
        let afterSecond = try Self.readRawUserVersion(at: dbPath)
        #expect(afterSecond == 16, "second open must not alter user_version")
    }
}

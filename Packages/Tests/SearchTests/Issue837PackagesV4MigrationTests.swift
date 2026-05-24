import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #837 / #849 — packages.db v3 → v4 migration round-trip

/// Pinned per `docs/design/837-pre-index-test-plan.md` §9.7.
/// Seeds a v3 packages.db with the v3-era schema and data, opens it
/// with the v4 `Search.PackageIndex` actor, then asserts:
///   - `PRAGMA user_version` advances to 4
///   - the two new columns on `package_metadata` (`apple_imports_json`,
///     `enrichment_version`) exist
///   - the new `package_symbols` table exists with the expected
///     columns + indexes
///   - the original v3 row survives (in-place ALTER, no wipe)
///   - re-running the migration on the now-v4 DB is idempotent
@Suite("#837 / #849 — packages.db v3 → v4 migration", .serialized)
struct Issue837PackagesV4MigrationTests {
    /// Create a tmp dir and return its URL; caller cleans up via defer.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-849-pkg-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Create a packages.db at v3 with a single row in `package_metadata`
    /// and `package_files`. Schema mirrors the v3 shape (post-#225 Part A
    /// `swift_tools_version` column, but pre-#837's `apple_imports_json` +
    /// `enrichment_version` + `package_symbols`).
    private static func seedV3(at path: URL) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let v3SQL = """
        CREATE TABLE package_metadata (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner TEXT NOT NULL,
            repo TEXT NOT NULL,
            url TEXT NOT NULL,
            branch_used TEXT,
            stars INTEGER,
            is_apple_official INTEGER NOT NULL DEFAULT 0,
            tarball_bytes INTEGER,
            total_bytes INTEGER,
            fetched_at INTEGER NOT NULL,
            cupertino_version TEXT,
            hosted_doc_url TEXT,
            parents_json TEXT,
            min_ios TEXT,
            min_macos TEXT,
            min_tvos TEXT,
            min_watchos TEXT,
            min_visionos TEXT,
            availability_source TEXT,
            swift_tools_version TEXT,
            UNIQUE(owner, repo)
        );

        CREATE TABLE package_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            package_id INTEGER NOT NULL,
            relpath TEXT NOT NULL,
            kind TEXT NOT NULL,
            module TEXT,
            size_bytes INTEGER NOT NULL,
            indexed_at INTEGER NOT NULL,
            available_attrs_json TEXT,
            FOREIGN KEY(package_id) REFERENCES package_metadata(id) ON DELETE CASCADE,
            UNIQUE(package_id, relpath)
        );

        INSERT INTO package_metadata
            (owner, repo, url, fetched_at, is_apple_official, swift_tools_version)
            VALUES ('legacy-owner', 'legacy-repo', 'https://example.test/legacy', 1, 0, '5.9');

        INSERT INTO package_files
            (package_id, relpath, kind, module, size_bytes, indexed_at)
            VALUES (1, 'Sources/Foo.swift', 'source', 'LegacyModule', 100, 1);

        PRAGMA user_version = 3;
        """
        var errPtr: UnsafeMutablePointer<CChar>?
        try #require(sqlite3_exec(db, v3SQL, nil, nil, &errPtr) == SQLITE_OK)
        sqlite3_free(errPtr)
    }

    private static func readPragma(at dbPath: URL, sql: String) throws -> [[String]] {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        var rows: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cols = sqlite3_column_count(stmt)
            var row: [String] = []
            for index in 0..<cols {
                if let ptr = sqlite3_column_text(stmt, index) {
                    row.append(String(cString: ptr))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - 1. Migration advances user_version + adds new columns

    @Test("v3 DB advances to current schema (5), two new columns + package_symbols + package_imports tables land")
    func migratesV3ToCurrent() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("packages.db")
        try Self.seedV3(at: path)
        #expect(try (Self.readPragma(at: path, sql: "PRAGMA user_version;").first?.first ?? "") == "3")

        // Trigger the migration by opening with the current binary.
        let index = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        await index.disconnect()

        let version = try Self.readPragma(at: path, sql: "PRAGMA user_version;").first?.first ?? ""
        #expect(version == String(Search.PackageIndex.schemaVersion))
        // Current schema is v5 (#860 added `package_imports`).
        #expect(version == "5")

        // New columns on package_metadata
        let metaCols = try Self.readPragma(at: path, sql: "PRAGMA table_info(package_metadata);")
            .compactMap { $0.count >= 2 ? $0[1] : nil }
        #expect(metaCols.contains("apple_imports_json"))
        #expect(metaCols.contains("enrichment_version"))

        // New tables: package_symbols (v4) + package_imports (v5).
        let tables = try Self.readPragma(at: path, sql: "SELECT name FROM sqlite_master WHERE type='table';")
            .compactMap(\.first)
        #expect(tables.contains("package_symbols"))
        #expect(tables.contains("package_imports"))

        let symbolCols = try Self.readPragma(at: path, sql: "PRAGMA table_info(package_symbols);")
            .compactMap { $0.count >= 2 ? $0[1] : nil }
        for expected in [
            "id", "file_id", "name", "kind", "line", "column", "signature",
            "is_async", "is_throws", "is_public", "is_static",
            "attributes", "conformances", "generic_params",
            "generic_constraints", "enrichment_version",
        ] {
            #expect(symbolCols.contains(expected), "expected column \(expected) on package_symbols; got \(symbolCols)")
        }

        let importCols = try Self.readPragma(at: path, sql: "PRAGMA table_info(package_imports);")
            .compactMap { $0.count >= 2 ? $0[1] : nil }
        for expected in ["id", "file_id", "module_name", "line", "is_exported"] {
            #expect(importCols.contains(expected), "expected column \(expected) on package_imports; got \(importCols)")
        }
    }

    // MARK: - 2. Original v3 row survives the migration (in-place ALTER, no wipe)

    @Test("pre-existing v3 row data is intact after migration")
    func preMigrationDataSurvives() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("packages.db")
        try Self.seedV3(at: path)

        let index = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        await index.disconnect()

        let rows = try Self.readPragma(
            at: path,
            sql: "SELECT owner, repo, swift_tools_version FROM package_metadata WHERE owner = 'legacy-owner';"
        )
        #expect(rows.count == 1)
        #expect(rows[0][0] == "legacy-owner")
        #expect(rows[0][1] == "legacy-repo")
        #expect(rows[0][2] == "5.9")
    }

    // MARK: - 3. Re-running the migration on the now-v4 DB is idempotent

    @Test("re-opening a migrated DB does not re-migrate or error")
    func idempotentReopen() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("packages.db")
        try Self.seedV3(at: path)

        let first = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        await first.disconnect()

        let second = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        await second.disconnect()

        let version = try Self.readPragma(at: path, sql: "PRAGMA user_version;").first?.first ?? ""
        #expect(version == String(Search.PackageIndex.schemaVersion))
        #expect(version == "5")

        let metaCount = try Self.readPragma(at: path, sql: "SELECT COUNT(*) FROM package_metadata;")
            .first?.first ?? ""
        #expect(metaCount == "1")
    }
}

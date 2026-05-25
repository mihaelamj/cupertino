import Foundation
import LoggingModels
@testable import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #837 / #849 — samples.db v3 → v4 wipe-and-rebuild round-trip

/// Pinned per `docs/design/837-pre-index-test-plan.md` §9.7.
/// samples.db's migration policy is wipe-and-rebuild on schema change
/// (see `Sample.Index.Database.swift:54-69`). This suite seeds a v3
/// samples.db, opens it with the v4 binary, and asserts:
///   - the wipe-and-rebuild fired (the seeded v3 row is gone)
///   - the resulting DB stamps version 4 in the `samples_schema_version`
///     table (post-#1037 the pipeline no longer writes `PRAGMA
///     user_version`; the per-pipeline tracking table is the source of
///     truth)
///   - the fresh schema includes the new `generic_constraints` and
///     `enrichment_version` columns on `file_symbols`
@Suite("#837 / #849 — samples.db v3 → v4 wipe-and-rebuild", .serialized)
struct Issue837SamplesV4MigrationTests {
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-849-samples-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Create a samples.db file on disk with a v3-shaped schema +
    /// one row in `projects`. Stamps `PRAGMA user_version = 3` so
    /// the open-time check in `Sample.Index.Database` triggers the
    /// wipe.
    private static func seedV3(at path: URL) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let v3SQL = """
        CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            frameworks TEXT NOT NULL,
            readme TEXT,
            web_url TEXT NOT NULL,
            zip_filename TEXT NOT NULL,
            file_count INTEGER NOT NULL,
            total_size INTEGER NOT NULL,
            indexed_at INTEGER NOT NULL
        );
        INSERT INTO projects
            (id, title, description, frameworks, readme, web_url, zip_filename,
             file_count, total_size, indexed_at)
            VALUES ('legacy-v3', 'Legacy', 'v3 row', 'SwiftUI', NULL, 'https://example.test', 'l.zip', 0, 0, 0);
        PRAGMA user_version = 3;
        """
        var errPtr: UnsafeMutablePointer<CChar>?
        try #require(sqlite3_exec(db, v3SQL, nil, nil, &errPtr) == SQLITE_OK)
        sqlite3_free(errPtr)
    }

    private static func readScalar(at dbPath: URL, sql: String) throws -> String {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        if let ptr = sqlite3_column_text(stmt, 0) {
            return String(cString: ptr)
        }
        return ""
    }

    private static func columnNames(at dbPath: URL, table: String) throws -> [String] {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK)
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(stmt, 1) {
                names.append(String(cString: ptr))
            }
        }
        return names
    }

    // MARK: - 1. The wipe-and-rebuild fires and stamps the new version

    @Test("v3 samples.db is wiped and rebuilt at v4 on open")
    func wipeAndRebuildOnSchemaBump() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("samples.db")
        try Self.seedV3(at: path)
        #expect(try Self.readScalar(at: path, sql: "PRAGMA user_version;") == "3")
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1")

        // Open with v4 — the policy is wipe-and-rebuild.
        let db = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        await db.disconnect()

        // Post-#1037: the per-pipeline `samples_schema_version` table is
        // the source of truth. `PRAGMA user_version` is no longer
        // written by this pipeline (so it stays at 0 on a freshly-wiped
        // file, distinct from the rebuilt schema's actual version).
        #expect(try Self.readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == String(Sample.Index.Database.schemaVersion))
        #expect(try Self.readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")
        // Wipe semantics: the seeded v3 row must be gone.
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "0")
    }

    // MARK: - 2. Fresh schema carries the new columns

    @Test("post-migration file_symbols schema includes generic_constraints + enrichment_version")
    func newColumnsExistOnFileSymbols() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("samples.db")
        try Self.seedV3(at: path)
        let db = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        await db.disconnect()

        let cols = try Self.columnNames(at: path, table: "file_symbols")
        #expect(cols.contains("generic_constraints"))
        #expect(cols.contains("enrichment_version"))
    }

    // MARK: - 3. Re-opening an already-v4 DB is a no-op (no spurious wipe)

    @Test("re-opening an already-v4 samples.db does not re-wipe")
    func idempotentReopenAtV4() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("samples.db")

        // First open creates a fresh v4 DB.
        let first = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())

        // Seed a project so we can detect a wipe.
        let project = Sample.Index.Project(
            id: "keep-me",
            title: "T",
            description: "T",
            frameworks: ["SwiftUI"],
            readme: nil,
            webURL: "https://example.test/keep",
            zipFilename: "k.zip",
            fileCount: 0,
            totalSize: 0
        )
        try await first.indexProject(project)
        await first.disconnect()
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1")

        // Re-open. Same schemaVersion, so the wipe MUST NOT fire.
        let second = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        await second.disconnect()

        // Post-#1037: per-pipeline tracking table; PRAGMA user_version
        // is no longer written by Sample.Index (stays at 0 here).
        #expect(try Self.readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1")
    }

    // MARK: - 4. #1037: shared-file safety (the trample-prevention case)

    /// Regression guard for the round-4 critic finding: pre-#1037
    /// `Sample.Index.Database.init` wiped any file whose `PRAGMA
    /// user_version` did not match its own `schemaVersion`. In the
    /// one-DB collapse target state, Search.Index would have stamped
    /// `user_version = 18` first; opening the file with Sample.Index
    /// would then have wiped both pipelines' tables. Post-#1037 the
    /// wipe gates on `projects` table presence (not user_version), so
    /// foreign tables in the same file are preserved.
    @Test("#1037: shared-file path, Sample.Index opens a DB whose user_version was set by another pipeline (no wipe)")
    func sharedFileForeignUserVersionIsHonoured() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("apple-sample-code.db")

        // Seed a file with foreign tables + a high user_version (mimics
        // Search.Index having stamped its v18 schema before Sample.Index
        // opens). No `projects` table, so this file is NOT a samples DB.
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        let seedSQL = """
        CREATE TABLE docs_metadata (id INTEGER PRIMARY KEY, uri TEXT NOT NULL);
        INSERT INTO docs_metadata (id, uri) VALUES (1, 'foreign://row');
        PRAGMA user_version = 18;
        """
        try #require(sqlite3_exec(db, seedSQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        #expect(try Self.readScalar(at: path, sql: "PRAGMA user_version;") == "18")
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM docs_metadata;") == "1")

        // Open with Sample.Index. The foreign user_version=18 must NOT
        // trip a wipe (no `projects` table = no samples data to be wrong
        // about). The foreign docs_metadata table must survive.
        let sampleIndex = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        await sampleIndex.disconnect()

        // Foreign data preserved.
        #expect(
            try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM docs_metadata;") == "1",
            "Search.Index's pre-existing docs_metadata row must NOT be wiped by Sample.Index opening the shared file"
        )
        // Sample.Index now has its own tables.
        #expect(
            try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "0",
            "Sample.Index's projects table must be created fresh (no samples data yet, but the table is ready)"
        )
        // Sample.Index stamped its version in the per-pipeline table.
        #expect(try Self.readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")
        // Foreign PRAGMA user_version untouched.
        #expect(
            try Self.readScalar(at: path, sql: "PRAGMA user_version;") == "18",
            "Sample.Index post-#1037 no longer writes PRAGMA user_version; another pipeline's stamp survives"
        )
    }

    // MARK: - 5. #1037: legacy samples.db migration into samples_schema_version

    /// Regression guard for the one-time fallback: existing samples.db
    /// files built by pre-#1037 binaries carry `PRAGMA user_version = 4`
    /// but no `samples_schema_version` table. On first open by a
    /// post-#1037 binary the new table must be populated from the
    /// legacy PRAGMA so the version read returns the correct value
    /// (not 0, which would trigger a spurious wipe-and-rebuild on the
    /// NEXT open if `projects` is present).
    @Test("#1037: manual `DELETE FROM samples_schema_version` does NOT wipe the projects table (critic round 5 finding #14)")
    func emptyTrackingTableDoesNotTriggerWipe() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("apple-sample-code.db")

        // First open: creates fresh DB at v4. Seed a sentinel project so
        // we can detect the wipe.
        let first = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        try await first.indexProject(.init(
            id: "sentinel",
            title: "Sentinel",
            description: "Pre-truncation sentinel",
            frameworks: ["SwiftUI"],
            readme: nil,
            webURL: "https://example.test/sentinel",
            zipFilename: "s.zip",
            fileCount: 0,
            totalSize: 0
        ))
        await first.disconnect()
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1")

        // Simulate an operator running `DELETE FROM samples_schema_version`
        // as part of debug recovery. Plus simulate a foreign Search.Index
        // PRAGMA stamp on the same file (shared-file world) to exercise
        // the worst case: PRAGMA mismatches schemaVersion.
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        let trash = """
        DELETE FROM samples_schema_version;
        PRAGMA user_version = 18;
        """
        try #require(sqlite3_exec(db, trash, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM samples_schema_version;") == "0")
        #expect(try Self.readScalar(at: path, sql: "PRAGMA user_version;") == "18")

        // Reopen with the post-#1037 binary. The wipe MUST NOT fire:
        // the tracking table is empty (debug action), and falling back
        // to PRAGMA=18 on a shared file would mis-classify the schema
        // as stale. The sentinel project must survive.
        let second = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        await second.disconnect()

        #expect(
            try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1",
            "sentinel project must survive: empty tracking table is ambiguous, NOT a wipe trigger"
        )
        // setSchemaVersion restored the row at the correct version.
        #expect(try Self.readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")
    }

    @Test("#1037: legacy samples.db (user_version=4, no tracking table) migrates seamlessly to samples_schema_version")
    func legacyDBMigratesPragmaIntoTrackingTable() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("samples.db")

        // Seed a "v4-shaped" samples.db without the new tracking table.
        // Pre-#1037 binaries stamped only PRAGMA user_version.
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        let seedSQL = """
        CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            frameworks TEXT NOT NULL,
            readme TEXT,
            web_url TEXT NOT NULL,
            zip_filename TEXT NOT NULL,
            file_count INTEGER NOT NULL,
            total_size INTEGER NOT NULL,
            indexed_at INTEGER NOT NULL,
            min_ios TEXT, min_macos TEXT, min_tvos TEXT, min_watchos TEXT,
            min_visionos TEXT, availability_source TEXT
        );
        INSERT INTO projects
            (id, title, description, frameworks, readme, web_url, zip_filename,
             file_count, total_size, indexed_at, min_ios, min_macos, min_tvos,
             min_watchos, min_visionos, availability_source)
            VALUES ('legacy', 'L', 'L', 'SwiftUI', NULL, 'https://example.test',
                    'l.zip', 0, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL);
        PRAGMA user_version = 4;
        """
        try #require(sqlite3_exec(db, seedSQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        // Open with the post-#1037 binary. Migration MUST recognise the
        // legacy stamp, populate `samples_schema_version`, NOT wipe.
        let sampleIndex = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        await sampleIndex.disconnect()

        // The pre-existing legacy project row survives (no spurious wipe).
        #expect(
            try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1",
            "Legacy v4 samples.db must not be wiped on first post-#1037 open"
        )
        // The tracking table is populated from the legacy PRAGMA.
        #expect(
            try Self.readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4",
            "samples_schema_version must carry the legacy user_version value after one-time migration"
        )
    }
}

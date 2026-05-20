import Foundation
import LoggingModels
@testable import SampleIndex
import SampleIndexModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #837 / #849 — samples.db v3 → v4 wipe-and-rebuild round-trip

/// Pinned per `docs/design/837-pre-index-test-plan.md` §9.7.
/// samples.db's migration policy is wipe-and-rebuild on schema change
/// (see `Sample.Index.Database.swift:54-69`). This suite seeds a v3
/// samples.db, opens it with the v4 binary, and asserts:
///   - the wipe-and-rebuild fired (the seeded v3 row is gone)
///   - the resulting DB stamps `PRAGMA user_version = 4`
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

        #expect(try Self.readScalar(at: path, sql: "PRAGMA user_version;") == String(Sample.Index.Database.schemaVersion))
        #expect(try Self.readScalar(at: path, sql: "PRAGMA user_version;") == "4")
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

        #expect(try Self.readScalar(at: path, sql: "PRAGMA user_version;") == "4")
        #expect(try Self.readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "1")
    }
}

import Foundation
import LoggingModels
@testable import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #1279 — read-only samples.db open gates on schema version

/// Isolation of the #1279 bug: `Sample.Index.Database`'s read-only branch
/// opened the file and returned with NO schema-version check, so a present
/// but version-skewed `apple-sample-code.db` (e.g. an old bundle left in
/// place after a binary upgrade) opened silently and served results from a
/// schema this binary does not understand. The read path is strictly
/// read-only (#1194) and cannot wipe-and-rebuild the way the write path
/// does, so the only correct behaviour is to fail loudly with an actionable
/// remediation. These tests fail on the pre-#1279 readOnly branch (no throw)
/// and pass once the gate is in place. The write path's wipe-and-rebuild is
/// unchanged and is exercised by `Issue837SamplesV4MigrationTests`.
@Suite("#1279 — read-only samples.db schema gate", .serialized)
struct Issue1279SampleSchemaGateTests {
    private static let currentSchemaVersion: Int32 = 4

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1279-samples-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Seed a samples-shaped file: a `projects` table (so the file reads as a
    /// genuine samples DB) plus a post-#1037 `samples_schema_version` tracking
    /// row stamped with `trackedVersion`. Rollback journal mode, no sidecars,
    /// the on-disk shape of a shipped bundle DB.
    private static func seed(at path: URL, trackedVersion: Int32) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL);
        INSERT INTO projects (id, title) VALUES ('p1', 'Demo');
        CREATE TABLE samples_schema_version (version INTEGER NOT NULL);
        INSERT INTO samples_schema_version (version) VALUES (\(trackedVersion));
        PRAGMA journal_mode=DELETE;
        """
        var errPtr: UnsafeMutablePointer<CChar>?
        try #require(sqlite3_exec(db, sql, nil, nil, &errPtr) == SQLITE_OK)
        sqlite3_free(errPtr)
    }

    /// Seed a pre-#1037 legacy samples file: a `projects` table and the legacy
    /// `PRAGMA user_version` stamp, with NO `samples_schema_version` table.
    private static func seedLegacy(at path: URL, pragmaVersion: Int32) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL);
        INSERT INTO projects (id, title) VALUES ('p1', 'Demo');
        PRAGMA user_version = \(pragmaVersion);
        PRAGMA journal_mode=DELETE;
        """
        var errPtr: UnsafeMutablePointer<CChar>?
        try #require(sqlite3_exec(db, sql, nil, nil, &errPtr) == SQLITE_OK)
        sqlite3_free(errPtr)
    }

    @Test("read-only open of an older-version samples.db throws an actionable setup mismatch")
    func olderTrackedVersionThrowsSetupRemediation() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("apple-sample-code.db")
        try Self.seed(at: path, trackedVersion: 2)

        await #expect(throws: Sample.Index.Error.self) {
            _ = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording(), readOnly: true)
        }
        do {
            _ = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording(), readOnly: true)
            Issue.record("expected a schema mismatch throw")
        } catch let error as Sample.Index.Error {
            let message = error.errorDescription ?? ""
            #expect(message.contains("cupertino setup"))
            #expect(message.contains(path.path))
            #expect(message.contains("2"))
            #expect(message.contains("4"))
        }
    }

    @Test("read-only open of a newer-version samples.db throws an actionable upgrade mismatch")
    func newerTrackedVersionThrowsUpgradeRemediation() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("apple-sample-code.db")
        try Self.seed(at: path, trackedVersion: 99)

        do {
            _ = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording(), readOnly: true)
            Issue.record("expected a schema mismatch throw")
        } catch let error as Sample.Index.Error {
            let message = error.errorDescription ?? ""
            #expect(message.contains("brew upgrade"))
            #expect(message.contains("99"))
        }
    }

    @Test("read-only open of a matching-version samples.db succeeds")
    func matchingTrackedVersionOpens() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("apple-sample-code.db")
        try Self.seed(at: path, trackedVersion: Self.currentSchemaVersion)

        let db = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording(), readOnly: true)
        await db.disconnect()
    }

    @Test("read-only open of a legacy (PRAGMA-stamped) skewed samples.db throws")
    func legacyPragmaSkewThrows() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("apple-sample-code.db")
        try Self.seedLegacy(at: path, pragmaVersion: 3)

        await #expect(throws: Sample.Index.Error.self) {
            _ = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording(), readOnly: true)
        }
    }
}

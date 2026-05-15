import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Regression suite for [#635](https://github.com/mihaelamj/cupertino/issues/635).
///
/// Before this PR, `Search.Index.setSchemaVersion()` wrote
/// `PRAGMA user_version = <constant>` whenever the on-disk value
/// differed from `Self.schemaVersion`, with no check on what the
/// existing value was. The only skip-path was an exact match (to
/// avoid the write-lock cost on steady-state opens).
///
/// On 2026-05-16, develop's binary built from the `fix/77` branch
/// (which bumped `schemaVersion: Int32 = 13 → 14` without adding
/// the matching v13→v14 throw to `checkAndMigrateSchema`) opened
/// the user's `~/.cupertino/search.db` (v13) and silently stamped
/// it at user_version=14. The homebrew-installed binary (v1.1.0,
/// schema 13) then refused to open the same DB, breaking 16 of 27
/// CLI commands until the user ran `cupertino setup` to redownload
/// a v13 bundle. Documented in
/// `mihaela-agents/sessions/2026-05-15-16-cupertino-bug-hunt/REPORT.md`.
///
/// Two coordinated fixes ship together:
///
/// 1. **`checkAndMigrateSchema`** now carries the v13→v14 throw entry
///    that #634 should have shipped with. Matches the existing pattern
///    for v11→v12 and v12→v13 — FTS5 ALTER TABLE ADD COLUMN is not
///    supported, so the only safe upgrade path is `cupertino setup`
///    to redownload a matching bundle.
/// 2. **`setSchemaVersion`** now guards against silent stamping. A
///    write is only allowed when the on-disk version is 0 (fresh DB).
///    Any other mismatch throws a clear error — either a future
///    schema bump forgot a migrator entry (the #634 mistake) or the
///    binary is being run against a DB produced by a different build.
@Suite("#635 Schema-stamp safety guard", .serialized)
struct Issue635SchemaStampGuardTests {
    // MARK: - Helpers

    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue635-\(UUID().uuidString).db")
    }

    /// Open an arbitrary SQLite file at `path` and write a raw
    /// `PRAGMA user_version`. Used to fabricate the "stale binary"
    /// shape — a DB whose schema slot doesn't match the binary's
    /// `Self.schemaVersion`.
    private static func writeRawUserVersion(_ value: Int32, at dbURL: URL) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbURL.path)) failed",
            ])
        }
        let sql = "PRAGMA user_version = \(value)"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db)),
            ])
        }
    }

    /// Read `PRAGMA user_version` directly so the test isn't reading
    /// through `getSchemaVersion()` (which is package-internal and
    /// could be subject to future refactors).
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
        else {
            return 0
        }
        return sqlite3_column_int(stmt, 0)
    }

    // MARK: - A. fresh DB still gets stamped

    @Test("Fresh DB (user_version=0) is stamped at the binary's expected version")
    func freshDBGetsStamped() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Opening a fresh DB through Search.Index runs the full init
        // path: openDatabase → checkAndMigrateSchema (no-op for v0)
        // → createTables → setSchemaVersion. The DB must end up
        // stamped at `Self.schemaVersion`.
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await idx.disconnect()

        let onDisk = try Self.readRawUserVersion(at: dbPath)
        #expect(
            onDisk == Search.Index.schemaVersion,
            "fresh DB should be stamped at \(Search.Index.schemaVersion), got \(onDisk)"
        )
    }

    // MARK: - B. matching version is a no-op (no write-lock contention)

    @Test("DB at user_version == schemaVersion opens cleanly without re-stamping")
    func matchingVersionIsNoOp() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // First open stamps the fresh DB to `schemaVersion`.
        let idx1 = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await idx1.disconnect()
        let stampedAt = try Self.readRawUserVersion(at: dbPath)
        try #require(stampedAt == Search.Index.schemaVersion)

        // Second open with a matching binary must be a clean no-op —
        // no throw, version unchanged. The guard's skip-path runs
        // before the stamp guard fires.
        let idx2 = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await idx2.disconnect()
        let afterReopen = try Self.readRawUserVersion(at: dbPath)
        #expect(afterReopen == stampedAt, "reopen must not change user_version")
    }

    // MARK: - C. older mismatched version throws via migrator entry

    @Test("DB at user_version=13 (post-#283, pre-#77) is rejected with a clear migration error")
    func olderVersionRejectedByMigrator() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Create an empty file, stamp it at user_version=13. Open via
        // Search.Index — `checkAndMigrateSchema` must throw the
        // v13→v14 entry with a `cupertino setup` remediation hint.
        try Data().write(to: dbPath)
        try Self.writeRawUserVersion(13, at: dbPath)

        await #expect(throws: Search.Error.self) {
            _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        }

        // The DB version must remain at 13 — the throw happens before
        // `setSchemaVersion` runs, so no silent stamping occurs.
        let after = try Self.readRawUserVersion(at: dbPath)
        #expect(after == 13, "rejected DB must keep its original user_version, got \(after)")
    }

    // MARK: - D. newer mismatched version (forward incompat) throws via existing check

    @Test("DB at user_version > schemaVersion is rejected (existing forward-incompat path)")
    func newerVersionRejected() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Stamp at schemaVersion + 1 to simulate "user upgraded the
        // bundle but downgraded the binary".
        try Data().write(to: dbPath)
        try Self.writeRawUserVersion(Search.Index.schemaVersion + 1, at: dbPath)

        await #expect(throws: Search.Error.self) {
            _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        }

        let after = try Self.readRawUserVersion(at: dbPath)
        #expect(
            after == Search.Index.schemaVersion + 1,
            "forward-incompat DB must keep its original user_version"
        )
    }

    // MARK: - E. setSchemaVersion guard (defense-in-depth)

    @Test("setSchemaVersion guard refuses to stamp over a non-zero, non-matching value")
    func setSchemaVersionGuardRejectsNonZeroMismatch() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Bring up an Index normally (stamps to current schemaVersion).
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        // Now poke the DB to an off-by-one version with the actor still open.
        // Direct call into setSchemaVersion is via the actor's internal
        // surface — we exercise it through reopening after a raw poke.
        await idx.disconnect()
        try Self.writeRawUserVersion(Search.Index.schemaVersion - 1, at: dbPath)

        // Reopening should throw — but if a future schema bump forgot
        // its migrator entry (so `checkAndMigrateSchema` fell through
        // without rejecting), the `setSchemaVersion` guard would catch
        // the stamp attempt. Either way: throw, no silent stamping.
        await #expect(throws: Search.Error.self) {
            _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        }

        // The DB must NOT have been stamped at the new schemaVersion.
        let after = try Self.readRawUserVersion(at: dbPath)
        #expect(
            after == Search.Index.schemaVersion - 1,
            "guard must leave user_version untouched on mismatch (got \(after))"
        )
    }

    // MARK: - F. error message includes the cupertino-setup recovery hint

    @Test("v13→v14 migrator throw mentions `cupertino setup` so the user knows what to do")
    func errorMessageMentionsSetup() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        try Data().write(to: dbPath)
        try Self.writeRawUserVersion(13, at: dbPath)

        do {
            _ = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
            Issue.record("expected Search.Index init to throw, but it succeeded")
        } catch let error as Search.Error {
            let message = error.localizedDescription
            #expect(
                message.contains("schema version 13"),
                "error should name the on-disk version (13), got: \(message)"
            )
            #expect(
                message.contains("cupertino setup"),
                "error should suggest `cupertino setup`, got: \(message)"
            )
        } catch {
            Issue.record("expected Search.Error, got \(type(of: error)): \(error)")
        }
    }
}

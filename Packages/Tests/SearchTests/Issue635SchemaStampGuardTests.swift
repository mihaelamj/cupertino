import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
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

    /// Drop the most-recent-version column + index from a freshly-built
    /// current-schemaVersion DB so the on-disk shape looks one version
    /// older. Used by the `schemaVersionMinusOneAutoMigratesToTarget`
    /// test — it pairs with `writeRawUserVersion(schemaVersion - 1, ...)`
    /// to construct a synthetic pre-current-version DB.
    ///
    /// The strip targets the column added by the LATEST schema bump
    /// (currently v17's `generic_constraints` per #755). Update this
    /// helper on each schema bump so the test stays anchored to
    /// `current - 1` rather than to a specific version that drifts
    /// further away with every bump.
    ///
    /// Why strip latest-only and not every column since v15: stripping
    /// is per-version-bump work. The test exercises the v(N-1) → vN
    /// migration; the older v(<N-1) migrators are tested elsewhere
    /// (`Issue749MigratorPragmaBumpTests` covers v15→v16 explicitly).
    private static func stripCurrentVersionColumnAndIndex(at dbURL: URL) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbURL.path)) failed",
            ])
        }
        // v18: re-CREATE the dropped `packages` + `package_dependencies` tables
        // (#789's in-place migration DROPs them). Stamping PRAGMA back to v17
        // and reopening should re-run migrateToVersion18 and drop them again.
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS packages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                owner TEXT NOT NULL,
                repository_url TEXT NOT NULL,
                UNIQUE(owner, name)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS package_dependencies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_id INTEGER NOT NULL,
                depends_on_package_id INTEGER NOT NULL,
                UNIQUE(package_id, depends_on_package_id)
            );
            """,
        ]
        for sql in statements {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "TestSetup", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "exec(\(sql)) failed: \(String(cString: sqlite3_errmsg(db)))",
                ])
            }
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

    @Test("schemaVersion-1 DB auto-migrates in place: PRAGMA stamped to target, no throw")
    func schemaVersionMinusOneAutoMigratesToTarget() async throws {
        // Post-#749 fix: in-place migrators self-stamp PRAGMA user_version
        // at the end via `stampUserVersionUnchecked`. A DB at
        // `schemaVersion - 1` (today v15) has a working in-place migrator
        // (migrateToVersion16) that runs the ALTER TABLE ADD COLUMN +
        // stamps to 16. setSchemaVersion's #635 guard sees the matching
        // version and returns at the early-exit, never reaching the
        // throw branch.
        //
        // Pre-#749: this test asserted the open SHOULD throw because
        // migrateToVersion16 didn't stamp and the #635 guard refused to
        // stamp from non-zero. That codified the bug. Updated to assert
        // the post-fix correct behaviour: in-place migration succeeds
        // end-to-end.
        //
        // The #635 guard remains as defense in depth — fires if a future
        // schema bump forgets to add a migrator entry. Defense is hard to
        // test in isolation today because every version 2 through 16
        // has SOME branch in `checkAndMigrateSchema` (migrate, throw, or
        // no-op-via-createTables-IF-NOT-EXISTS). When the next schema
        // bump lands, this test gains a sibling that pokes the new
        // schemaVersion - 1 and verifies in-place migration there too.
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Bring up an Index normally (stamps to current schemaVersion).
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await idx.disconnect()

        // Strip the latest-version column + index, then stamp PRAGMA back
        // to current schemaVersion - 1 so the DB looks one version older
        // than this binary's target. The strip targets the column the
        // latest in-place migrator (today v17 / #755) adds.
        try Self.stripCurrentVersionColumnAndIndex(at: dbPath)
        try Self.writeRawUserVersion(Search.Index.schemaVersion - 1, at: dbPath)

        // Reopening triggers checkAndMigrateSchema → migrateToVersion16
        // (which now stamps the version) → setSchemaVersion (early-exits
        // because PRAGMA already matches target).
        let reopened = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await reopened.disconnect()

        // The DB should now be stamped at the current schemaVersion.
        let after = try Self.readRawUserVersion(at: dbPath)
        #expect(
            after == Search.Index.schemaVersion,
            "in-place migration must stamp PRAGMA to target (got \(after), expected \(Search.Index.schemaVersion))"
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

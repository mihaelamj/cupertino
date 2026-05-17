import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

// MARK: - #749 — in-place migrators must stamp PRAGMA user_version

//
// Bug surfaced during the 2026-05-17 pair-workflow test pass: main built
// a v15 binary (pre-PR #718), saved a v15 DB, develop opened it with a
// fresh v16 binary. The migration path threw at the #635 guard in
// setSchemaVersion() because migrateToVersion16() added the column but
// did not bump PRAGMA user_version. Class-of-bug audit: none of the
// 7 in-place migrators (3 / 4 / 6 / 7 / 10 / 11 / 16) bumped the
// stamp.
//
// The fix extracted a private helper `stampUserVersionUnchecked(_:)`
// on Search.Index that bypasses the #635 guard; each migrator calls it
// at the end. This suite pins the contract: for the migrator path we
// can construct from current build (v15 → v16, since the v16 schema is
// what `createTables()` writes today), Search.Index.init auto-migrates
// the DB to v16 + makes the new column reachable + leaves the DB at
// PRAGMA user_version = 16. The promised v15→v16 integration test in
// Issue225PartBImplementationSwiftVersionTests.swift line 19-21 lived
// only in the documentation comment; this suite is that test, filed
// as the regression lock for #749.
//
// Why not parametrise across v3 / v6 / v7 / v10 / v11 / v16? Each
// requires constructing the from-version schema shape from scratch,
// which is tedious + fragile (older schemas have been removed from
// the codebase as production moved on). The class-of-bug fix is in
// the helper itself; every migrator now calls it. Pinning the v15→v16
// path covers (a) the helper compiles and runs, (b) the
// `checkAndMigrateSchema → migrator → helper → setSchemaVersion` flow
// works end-to-end against a real-shaped DB. Older paths can be
// retro-tested if a user ever reports trouble.

@Suite("#749 — in-place migrators stamp PRAGMA user_version", .serialized)
struct Issue749MigratorPragmaBumpTests {
    /// Drops the v15→v16 column + index from a freshly-built v16 DB
    /// and stamps PRAGMA = 15. Produces an on-disk artefact shaped
    /// like a DB produced by a pre-#718 binary.
    private static func makeSyntheticV15DB() async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-749-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")

        // Build a fresh v16 DB through the normal path so every other
        // table exists in the v15-otherwise-correct shape.
        let bootstrap = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await bootstrap.disconnect()

        // Strip the v16-only column + index so the DB looks v15.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let stripStatements = [
            "DROP INDEX IF EXISTS idx_implementation_swift_version;",
            "ALTER TABLE docs_metadata DROP COLUMN implementation_swift_version;",
            "PRAGMA user_version = 15;",
        ]
        for sql in stripStatements {
            var err: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(err) }
            try #require(sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK, "strip statement failed: \(sql)")
        }

        return dbPath
    }

    @Test("v15 DB opened by v16 binary auto-migrates: PRAGMA 16 + column reachable")
    func v15ToV16AutoMigrationLeavesDBAtV16() async throws {
        let dbPath = try await Self.makeSyntheticV15DB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Pre-condition: confirm the synthetic DB is at v15 and the column is absent.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        var preVersionStmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &preVersionStmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(preVersionStmt) == SQLITE_ROW)
        let preVersion = sqlite3_column_int(preVersionStmt, 0)
        sqlite3_finalize(preVersionStmt)
        sqlite3_close(db)
        #expect(preVersion == 15, "synthetic-v15-DB construction failed; got user_version=\(preVersion)")

        // Act: open the DB via Search.Index.init. This is the path that
        // triggers checkAndMigrateSchema → migrateToVersion16 →
        // stampUserVersionUnchecked(16). Before #749 fix, this threw at
        // setSchemaVersion's guard.
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await index.disconnect()

        // Post-condition: PRAGMA stamped to 16, column reachable.
        var postDB: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &postDB) == SQLITE_OK)
        defer { sqlite3_close(postDB) }

        var versionStmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(postDB, "PRAGMA user_version", -1, &versionStmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(versionStmt) == SQLITE_ROW)
        let postVersion = sqlite3_column_int(versionStmt, 0)
        sqlite3_finalize(versionStmt)
        #expect(
            postVersion == Search.Index.schemaVersion,
            "PRAGMA user_version should be stamped to current schemaVersion (\(Search.Index.schemaVersion)) post-migration; got \(postVersion)"
        )

        // Column reachable via SELECT.
        var columnStmt: OpaquePointer?
        let columnQuery = "SELECT implementation_swift_version FROM docs_metadata LIMIT 1;"
        let columnPrep = sqlite3_prepare_v2(postDB, columnQuery, -1, &columnStmt, nil)
        sqlite3_finalize(columnStmt)
        #expect(columnPrep == SQLITE_OK, "implementation_swift_version column not reachable post-migration; sqlite3_prepare_v2 returned \(columnPrep)")

        // Index present.
        var indexStmt: OpaquePointer?
        let indexQuery = "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_implementation_swift_version';"
        try #require(sqlite3_prepare_v2(postDB, indexQuery, -1, &indexStmt, nil) == SQLITE_OK)
        let hasIndex = sqlite3_step(indexStmt) == SQLITE_ROW
        sqlite3_finalize(indexStmt)
        #expect(hasIndex, "idx_implementation_swift_version should exist post-migration")
    }

    @Test("Second open against the migrated DB is a no-op (idempotent)")
    func secondOpenIsNoOp() async throws {
        let dbPath = try await Self.makeSyntheticV15DB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // First open migrates from v15 to v16.
        let firstOpen = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await firstOpen.disconnect()

        // Second open should be a no-op (DB is already at target).
        let secondOpen = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await secondOpen.disconnect()

        // No throw is the test. Also verify PRAGMA is still 16.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        let version = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        #expect(
            version == Search.Index.schemaVersion,
            "PRAGMA user_version should still be current schemaVersion (\(Search.Index.schemaVersion)) after second open; got \(version)"
        )
    }

    @Test("stampUserVersionUnchecked writes the requested version unconditionally")
    func helperStampsRequestedVersionUnconditionally() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-749-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbPath = tempDir.appendingPathComponent("search.db")

        // Build a fresh v16 DB and use the helper to overstamp to an
        // arbitrary value. This pins that the helper bypasses the
        // setSchemaVersion #635 guard; the guard's "currentVersion ==
        // 0" precondition is irrelevant to the helper.
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await index.stampUserVersionUnchecked(99)
        await index.disconnect()

        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        let stamped = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        #expect(stamped == 99, "helper should stamp the requested version unconditionally; got \(stamped)")
    }
}

import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

// MARK: - #755 — generic_constraints column + extraction helpers

//
// Bug surfaced during main's MCP-tools-sanity probe 2026-05-17:
// `search_generics("Collection")` and `search_generics("Array")`
// returned EMPTY against a v1.0.x bundle DB while `("Result")`
// returned 649 rows. SQL-level investigation found the
// `doc_symbols.generic_params` column stored type-parameter NAMES
// (`T`, `Element`, `Result`), not constraints. The "Result" hit was
// coincidental — Result is a common generic param NAME (e.g.
// `func reduce<Result>`); Array and Collection aren't used as names.
//
// Fix shipped in schema v17: new `generic_constraints` column
// populated from two sources at index time:
//   (1) AST extractor's `T: Collection` form, split into name +
//       constraint (the constraint half lands in the new column).
//   (2) Where-clause + inline patterns regex-parsed from the
//       signature column for declarations the AST extractor doesn't
//       reach (where clauses live on a separate AST node).
//
// Search predicate `searchByGenericConstraint` moved from
// `s.generic_params LIKE` to `s.generic_constraints LIKE`.
//
// This suite pins two contracts:
//   - **Migration**: a v16 DB opened by a v17 binary auto-migrates
//     in place (ALTER TABLE ADD COLUMN + index + PRAGMA stamp via
//     the #749 helper).
//   - **Extraction helpers**: parametrised round-trips over the
//     concrete shapes the corpus carries (bare names, inline
//     constraints, where clauses, same-type requirements, multiple
//     constraints joined with `&`, multiple params, edge cases).

@Suite("#755 — schema v16 → v17 migration", .serialized)
struct Issue755MigrateToVersion17Tests {
    /// Drops the v17-only column + index from a freshly-built v17 DB
    /// and stamps PRAGMA = 16. Produces an on-disk artefact shaped
    /// like a DB produced by a pre-#755 binary against the v1.0.2 corpus.
    private static func makeSyntheticV16DB() async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-755-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")

        // Build a fresh v17 DB through the normal path so every other
        // table exists in the v16-otherwise-correct shape.
        let bootstrap = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await bootstrap.disconnect()

        // Strip the v17-only column + index so the DB looks v16.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let stripStatements = [
            "DROP INDEX IF EXISTS idx_doc_symbols_generic_constraints;",
            "ALTER TABLE doc_symbols DROP COLUMN generic_constraints;",
            "PRAGMA user_version = 16;",
        ]
        for sql in stripStatements {
            var err: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(err) }
            try #require(sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK, "strip statement failed: \(sql)")
        }

        return dbPath
    }

    @Test("v16 DB opened by v17 binary auto-migrates: PRAGMA 17 + column reachable + index present")
    func v16ToV17AutoMigrationLeavesDBAtV17() async throws {
        let dbPath = try await Self.makeSyntheticV16DB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Pre-condition: confirm the synthetic DB is at v16 and the column is absent.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        var preVersionStmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &preVersionStmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(preVersionStmt) == SQLITE_ROW)
        let preVersion = sqlite3_column_int(preVersionStmt, 0)
        sqlite3_finalize(preVersionStmt)
        sqlite3_close(db)
        #expect(preVersion == 16, "synthetic-v16-DB construction failed; got user_version=\(preVersion)")

        // Act: open the DB via Search.Index.init → checkAndMigrateSchema
        // → migrateToVersion17 → stampUserVersionUnchecked(17).
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await index.disconnect()

        // Post-condition: PRAGMA stamped to 17, column reachable, index present.
        var postDB: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &postDB) == SQLITE_OK)
        defer { sqlite3_close(postDB) }

        var versionStmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(postDB, "PRAGMA user_version", -1, &versionStmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(versionStmt) == SQLITE_ROW)
        let postVersion = sqlite3_column_int(versionStmt, 0)
        sqlite3_finalize(versionStmt)
        #expect(postVersion == 17, "PRAGMA user_version should be stamped to 17 post-migration; got \(postVersion)")

        var columnStmt: OpaquePointer?
        let columnQuery = "SELECT generic_constraints FROM doc_symbols LIMIT 1;"
        let columnPrep = sqlite3_prepare_v2(postDB, columnQuery, -1, &columnStmt, nil)
        sqlite3_finalize(columnStmt)
        #expect(columnPrep == SQLITE_OK, "generic_constraints column not reachable post-migration; sqlite3_prepare_v2 returned \(columnPrep)")

        var indexStmt: OpaquePointer?
        let indexQuery = "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_doc_symbols_generic_constraints';"
        try #require(sqlite3_prepare_v2(postDB, indexQuery, -1, &indexStmt, nil) == SQLITE_OK)
        let hasIndex = sqlite3_step(indexStmt) == SQLITE_ROW
        sqlite3_finalize(indexStmt)
        #expect(hasIndex, "idx_doc_symbols_generic_constraints should exist post-migration")
    }

    @Test("Second open against the migrated DB is a no-op (idempotent)")
    func secondOpenIsNoOp() async throws {
        let dbPath = try await Self.makeSyntheticV16DB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let firstOpen = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await firstOpen.disconnect()

        let secondOpen = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        await secondOpen.disconnect()

        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        let version = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        #expect(version == 17, "PRAGMA user_version should still be 17 after second open; got \(version)")
    }
}

@Suite("#755 — combined constraint extraction (AST + where-clause)")
struct Issue755ConstraintExtractionTests {
    @Test(
        "splitGenericConstraints: AST extractor output round-trips",
        arguments: [
            // (genericParameters, expectedConstraintBlob)
            (["T"], nil),
            (["T", "U", "V"], nil),
            (["T: Collection"], "Collection"),
            (["T: Collection", "U"], "Collection"),
            (["T: Collection", "U: View"], "Collection,View"),
            (["Element: Hashable & Sendable"], "Hashable & Sendable"),
            ([], nil),
        ] as [([String], String?)]
    )
    func combinesASTOutput(genericParameters: [String], expected: String?) {
        let actual = Search.Index.combinedGenericConstraints(
            fromAST: genericParameters,
            fromSignature: nil
        )
        #expect(actual == expected, "AST split mismatch for \(genericParameters): got \(String(describing: actual)), expected \(String(describing: expected))")
    }

    @Test(
        "extractWhereClauseConstraints: signature-level patterns",
        arguments: [
            // (signature, expectedConstraints)
            (nil, []),
            ("", []),
            ("func foo<T>(x: T)", []),
            ("func foo<T>(x: T) where T: Collection", ["Collection"]),
            ("func foo<T>(x: T) where T: Hashable & Sendable", ["Hashable & Sendable"]),
            ("func foo<T, U>(x: T, y: U) where T: View, U: Equatable", ["View", "Equatable"]),
            ("extension Collection where Element == Int", []),
            ("func foo<T>(x: T) where T == U", []),
            ("func foo<T>(x: T) where T: Collection, T == U", ["Collection"]),
        ] as [(String?, [String])]
    )
    func extractsWhereClauses(signature: String?, expected: [String]) {
        let actual = Search.Index.extractWhereClauseConstraints(from: signature)
        #expect(actual == expected, "where-clause extraction mismatch for \(String(describing: signature)): got \(actual), expected \(expected)")
    }

    @Test("AST + where-clause merge: both sources contribute")
    func mergedFromBothSources() {
        let actual = Search.Index.combinedGenericConstraints(
            fromAST: ["T: Collection", "U"],
            fromSignature: "func foo<T, U>(x: T, y: U) where U: View"
        )
        #expect(actual == "Collection,View", "merged extraction should carry both AST + where halves; got \(String(describing: actual))")
    }

    @Test("All bare names + no where clause yields nil (NULL semantic)")
    func noConstraintsYieldsNil() {
        let actual = Search.Index.combinedGenericConstraints(
            fromAST: ["T", "Other"],
            fromSignature: "func reduce<T, Other>(initial: T, transform: (T, Other) -> T) -> T"
        )
        #expect(actual == nil, "all-bare-names + no-where signature should produce nil; got \(String(describing: actual))")
    }
}

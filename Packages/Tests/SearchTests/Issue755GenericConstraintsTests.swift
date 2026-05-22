import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #755 / #759 — generic_constraints column + extraction helpers

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
// Fix shipped in schema v17 + extractor pass:
//   - **Schema** (#755 + this issue): new `generic_constraints` column
//     on `doc_symbols`, populated at index time from `T: Constraint`
//     entries emitted by the AST extractor's combined generic-clause
//     + where-clause walk.
//   - **AST extraction** (#759 iteration 1): `extractGenericParameters`
//     now walks BOTH `GenericParameterClauseSyntax.parameters` (inline
//     `<T: Collection>` form) AND `GenericWhereClauseSyntax.requirements`
//     (where-clause form), filtering to `.conformanceRequirement` so
//     same-type requirements `T == U` are excluded. Output: an array
//     of `T: Constraint` entries merged from both shapes.
//   - **Hierarchy inheritance** (#759 iteration 2): post-indexing pass
//     `propagateConstraintsFromParents` walks the doc_symbols rows
//     whose own page has no constraint clause but whose parent TYPE
//     declares constraints. Catches the "bare-generic methods" case:
//     `NavigationLink<Label, Destination: View>.init(..., destination: () -> Destination)`
//     — the init's signature has bare `Destination` but inherits the
//     parent struct's `Destination: View` constraint.
//
// Search predicate `searchByGenericConstraint` moved from
// `s.generic_params LIKE` to `s.generic_constraints LIKE`.
//
// This file pins three contracts:
//   - **Migration**: v16 DB opened by a v17 binary auto-migrates in
//     place (Issue755MigrateToVersion17Tests).
//   - **AST → constraint blob**: the splitter helper round-trips
//     genericParameters output into the comma-joined constraint shape
//     written to the new column (Issue755ConstraintExtractionTests).
//   - **Parent URI**: the helper that drives iteration 2 strips
//     the last path segment correctly across canonical URI shapes
//     (Issue759ParentURITests).

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
        let bootstrap = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
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
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
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
        #expect(
            Int32(postVersion) == Search.Index.schemaVersion,
            "PRAGMA user_version should match Search.Index.schemaVersion after migration; got \(postVersion) vs \(Search.Index.schemaVersion)"
        )

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

        let firstOpen = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        await firstOpen.disconnect()

        let secondOpen = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        await secondOpen.disconnect()

        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        let version = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        #expect(
            Int32(version) == Search.Index.schemaVersion,
            "PRAGMA user_version should match Search.Index.schemaVersion after second open; got \(version) vs \(Search.Index.schemaVersion)"
        )
    }
}

@Suite("#755 / #759 — combinedGenericConstraints splits AST output")
struct Issue755ConstraintExtractionTests {
    // The AST extractor (post-#759) emits both inline `<T: X>` form
    // AND where-clause `where T: X` form merged into the
    // `genericParameters: [String]` array as `T: Constraint` entries.
    // The splitter here keeps only the constraint half and joins
    // comma-separated for the new `doc_symbols.generic_constraints`
    // column. Same-type requirements (`T == U`) never reach the
    // splitter because the AST extractor filters them upstream.

    @Test(
        "combinedGenericConstraints: AST → constraint-blob round-trip",
        arguments: [
            // (genericParameters, expectedConstraintBlob)
            (["T"], nil),
            (["T", "U", "V"], nil),
            (["T: Collection"], "Collection"),
            (["T: Collection", "U"], "Collection"),
            (["T: Collection", "U: View"], "Collection,View"),
            (["Element: Hashable & Sendable"], "Hashable & Sendable"),
            ([], nil),
            // #759 — entries the AST extractor emits from the
            // genericWhereClause walk arrive in the same `T: Constraint`
            // shape and split identically:
            (["Data", "ID", "Content", "Data: RandomAccessCollection", "ID: Hashable"], "RandomAccessCollection,Hashable"),
            // Edge case: empty constraint half after the colon falls
            // through (defensive — shouldn't reach the splitter but
            // guard anyway).
            (["T: "], nil),
        ] as [([String], String?)]
    )
    func combinesASTOutput(genericParameters: [String], expected: String?) {
        let actual = Search.Index.combinedGenericConstraints(fromAST: genericParameters)
        #expect(actual == expected, "AST split mismatch for \(genericParameters): got \(String(describing: actual)), expected \(String(describing: expected))")
    }
}

@Suite("#759 iteration 2 — parent URI derivation for hierarchy inheritance")
struct Issue759ParentURITests {
    @Test(
        "parentURI strips the last path segment",
        arguments: [
            // (childUri, expectedParent)
            ("apple-docs://swiftui/navigationlink/init-bar", "apple-docs://swiftui/navigationlink"),
            ("apple-docs://swiftui/navigationlink", "apple-docs://swiftui"),
            ("apple-docs://swiftui/foreach/init-_-content", "apple-docs://swiftui/foreach"),
            // Scheme-tail guard: refuse to strip into `apple-docs:`.
            ("apple-docs://swiftui", nil),
            // No slashes at all.
            ("bare-string", nil),
            // Empty.
            ("", nil),
        ] as [(String, String?)]
    )
    func stripsLastSegment(child: String, expected: String?) {
        let actual = Search.Index.parentURI(of: child)
        #expect(actual == expected, "parentURI(\"\(child)\") mismatch: got \(String(describing: actual)), expected \(String(describing: expected))")
    }
}

import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #759 iter 3 — applyAppleStaticConstraints (pass-3 SQL UPDATE)

//
// Pinned per the #763 immaculate-coverage acceptance list (Section 3:
// "currently ZERO tests for this method"). The method takes an
// optional `any Search.StaticConstraintsLookup` and applies its
// entries over `doc_symbols.generic_constraints` via two SQL passes:
//
//   1. Exact match: `WHERE doc_uri = entry.docURI`
//      Catches type-level rows + methods without overload disambiguation.
//
//   2. Hash-prefix match: `WHERE doc_uri LIKE entry.docURI || '-%'`
//      Catches Apple's hash-disambiguated overloads
//      (`init(_:content:)-7l1jb`).
//
// Both run in one BEGIN/COMMIT transaction. Iter 3 is AUTHORITATIVE,
// so it intentionally overwrites whatever iter 1 (AST extractor) left
// in the row — this is the inverse of iter 2's behaviour, which only
// fills NULL rows.

@Suite("#759 iter-3 — applyAppleStaticConstraints (pass-3 SQL UPDATE)", .serialized)
struct Issue759AppleStaticConstraintsTests {
    // MARK: - Test fixtures

    /// Minimal in-memory `StaticConstraintsLookup` for testing.
    /// Returns the entries provided at init. The pass-3 SQL UPDATE
    /// path is what's under test, not the lookup itself.
    private struct InMemoryLookup: Search.StaticConstraintsLookup {
        let entries: [Search.StaticConstraintEntry]
        func allEntries() async throws -> [Search.StaticConstraintEntry] {
            entries
        }
    }

    /// Lookup that throws on `allEntries()`. Used to verify the
    /// method propagates lookup errors cleanly (no half-applied
    /// transaction).
    private struct ThrowingLookup: Search.StaticConstraintsLookup {
        struct E: Error {}
        func allEntries() async throws -> [Search.StaticConstraintEntry] {
            throw E()
        }
    }

    /// Build a fresh v17 DB; return (path, index). Caller cleans up
    /// the tempdir via the `defer` in the test body.
    private static func makeFreshDB() async throws -> (dbPath: URL, index: Search.Index) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-759-iter3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:])
        return (dbPath, index)
    }

    /// Seed one row in `doc_symbols`. Pre-seeds the FK target row in
    /// `docs_metadata` so the insert doesn't trip the FK constraint.
    @discardableResult
    private static func seedSymbol(
        dbPath: URL,
        docUri: String,
        kind: String = "struct",
        name: String = "Foo",
        signature: String? = nil,
        genericParams: String? = nil,
        genericConstraints: String? = nil
    ) throws -> Int64 {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let metaSQL = """
        INSERT OR IGNORE INTO docs_metadata
            (uri, source, framework, language, kind, file_path, content_hash, last_crawled, word_count)
        VALUES (?, 'apple-docs', 'swiftui', 'swift', 'unknown', '/tmp/fake', '0', 0, 0);
        """
        var metaStmt: OpaquePointer?
        defer { sqlite3_finalize(metaStmt) }
        try #require(sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK)
        sqlite3_bind_text(metaStmt, 1, (docUri as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(metaStmt) == SQLITE_DONE)

        let sql = """
        INSERT INTO doc_symbols
            (doc_uri, name, kind, line, column, signature, is_async, is_throws,
             is_public, is_static, generic_params, generic_constraints)
        VALUES (?, ?, ?, 1, 1, ?, 0, 0, 1, 0, ?, ?);
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (kind as NSString).utf8String, -1, nil)
        if let signature {
            sqlite3_bind_text(stmt, 4, (signature as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let genericParams {
            sqlite3_bind_text(stmt, 5, (genericParams as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let genericConstraints {
            sqlite3_bind_text(stmt, 6, (genericConstraints as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        return sqlite3_last_insert_rowid(db)
    }

    private static func readConstraints(dbPath: URL, rowId: Int64) throws -> String? {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, "SELECT generic_constraints FROM doc_symbols WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int64(stmt, 1, rowId)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        guard let cstr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cstr)
    }

    // MARK: - nil + empty lookup paths

    @Test("nil lookup: method is a no-op, DB untouched")
    func nilLookupIsNoOp() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            genericConstraints: "OriginalValue"
        )

        try await index.applyAppleStaticConstraints(lookup: nil)
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == "OriginalValue", "nil lookup must not touch existing rows; got \(String(describing: result))")
    }

    @Test("empty entries: method is a no-op, no transaction overhead")
    func emptyEntriesIsNoOp() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            genericConstraints: "OriginalValue"
        )

        try await index.applyAppleStaticConstraints(lookup: InMemoryLookup(entries: []))
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == "OriginalValue", "empty-entries lookup must not touch existing rows; got \(String(describing: result))")
    }

    // MARK: - exact match path

    @Test("Exact-match doc_uri: row's generic_constraints replaced with entry value")
    func exactMatchUpdatesRow() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            genericConstraints: nil
        )

        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/foreach",
                constraints: ["RandomAccessCollection", "Hashable"]
            ),
        ])
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == "RandomAccessCollection,Hashable", "exact-match should set the joined-comma blob; got \(String(describing: result))")
    }

    // MARK: - hash-disambiguator LIKE-prefix path

    @Test("Hash-disambiguated overload row caught by LIKE-prefix UPDATE")
    func hashDisambiguatedRowCaughtByLikePrefix() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Apple's URL renderer appends `-<hash>` to disambiguate
        // overloads. The symbolgraph emits only the un-disambiguated
        // form; the LIKE-prefix fallback catches the hashed row.
        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach/init(_:content:)-7l1jb",
            kind: "initializer",
            name: "init"
        )

        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/foreach/init(_:content:)",
                constraints: ["RandomAccessCollection", "Hashable"]
            ),
        ])
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == "RandomAccessCollection,Hashable", "hashed-row should be caught by LIKE-prefix; got \(String(describing: result))")
    }

    @Test("Same entry catches BOTH the un-disambiguated row AND its hash variants")
    func entryUpdatesBothExactAndHashRows() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let exactRowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/list/init(selection:content:)",
            kind: "initializer",
            name: "init"
        )
        let hashedRowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/list/init(selection:content:)-590zm",
            kind: "initializer",
            name: "init"
        )

        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/list/init(selection:content:)",
                constraints: ["Hashable", "View"]
            ),
        ])
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        let exact = try Self.readConstraints(dbPath: dbPath, rowId: exactRowId)
        let hashed = try Self.readConstraints(dbPath: dbPath, rowId: hashedRowId)
        #expect(exact == "Hashable,View", "exact-match path: got \(String(describing: exact))")
        #expect(hashed == "Hashable,View", "LIKE-prefix path: got \(String(describing: hashed))")
    }

    // MARK: - missing target row

    @Test("Entry with no matching doc_symbols row: silently skipped, no error")
    func nonMatchingEntryDoesNotError() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Seed one row; lookup carries an entry pointing at a
        // different URI.
        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach"
        )
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/never-existed",
                constraints: ["View"]
            ),
        ])

        // Method should NOT throw even though the entry doesn't match.
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        // The seeded row's constraints stayed NULL (no entry matched).
        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == nil, "non-matching entry must not touch unrelated rows; got \(String(describing: result))")
    }

    // MARK: - batched multi-entry transaction

    @Test("Multiple entries all applied inside one BEGIN/COMMIT transaction")
    func multipleEntriesBatched() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let foreachId = try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach")
        let listId = try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://swiftui/list")
        let pickerId = try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://swiftui/picker")

        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/foreach", constraints: ["RandomAccessCollection"]),
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/list", constraints: ["Hashable", "View"]),
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/picker", constraints: ["View", "Hashable", "View"]),
        ])
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        #expect(try Self.readConstraints(dbPath: dbPath, rowId: foreachId) == "RandomAccessCollection")
        #expect(try Self.readConstraints(dbPath: dbPath, rowId: listId) == "Hashable,View")
        #expect(try Self.readConstraints(dbPath: dbPath, rowId: pickerId) == "View,Hashable,View")
    }

    // MARK: - iter-3 OVERWRITES iter-1 (authoritative source)

    @Test("Row with existing constraints from iter-1 IS overwritten by iter-3 (iter-3 is authoritative)")
    func iter3OverwritesIter1Constraints() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Iter-1 left a partial / less-authoritative blob. Iter-3 has
        // the symbol-graph value and replaces it. This is the
        // INVERSE of iter-2's contract (which preserves existing
        // non-NULL rows).
        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            genericConstraints: "RandomAccessCollection" // missing the Hashable part from iter-1
        )

        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/foreach",
                constraints: ["RandomAccessCollection", "Hashable"]
            ),
        ])
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == "RandomAccessCollection,Hashable", "iter-3 must overwrite iter-1's partial constraints; got \(String(describing: result))")
    }

    // MARK: - constraint-list joining

    @Test(
        "Multiple constraints joined with comma; single constraint passes through",
        arguments: [
            (["View"], "View"),
            (["View", "Hashable"], "View,Hashable"),
            (["RandomAccessCollection", "Hashable", "Sendable"], "RandomAccessCollection,Hashable,Sendable"),
            // Repeated identical entries are preserved (the LIKE search predicate handles them fine):
            (["View", "View"], "View,View"),
        ] as [([String], String)]
    )
    func constraintsJoinedWithComma(constraints: [String], expected: String) async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let rowId = try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://test/uri")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://test/uri", constraints: constraints),
        ])
        try await index.applyAppleStaticConstraints(lookup: lookup)
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == expected, "constraints \(constraints): got \(String(describing: result)), expected \(expected)")
    }

    // MARK: - error propagation

    @Test("Throwing lookup: error propagates, DB stays consistent (transaction not started)")
    func throwingLookupPropagates() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        let rowId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            genericConstraints: "Pre-existing"
        )

        await #expect(throws: ThrowingLookup.E.self) {
            try await index.applyAppleStaticConstraints(lookup: ThrowingLookup())
        }
        await index.disconnect()

        // Row is unchanged — the throw happened before any SQL fired.
        let result = try Self.readConstraints(dbPath: dbPath, rowId: rowId)
        #expect(result == "Pre-existing", "throwing lookup must not corrupt the row; got \(String(describing: result))")
    }
}

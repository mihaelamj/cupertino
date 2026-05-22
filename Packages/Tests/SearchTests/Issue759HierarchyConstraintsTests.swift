import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// Test suite for the iter-2 hierarchy walk introduced by
// [#759](https://github.com/mihaelamj/cupertino/issues/759). Covers the
// four surfaces that shipped in PR #760 with only `parentURI(of:)`
// unit-tested:
//
// 1. `extractBareParamNames(from:)`. parses the `generic_params` column
//    shape to recover the bare type-parameter names (`T`, `Data`, `ID`)
//    after the AST extractor joined bare + where-clause entries in one
//    comma-separated string.
// 2. `signatureReferencesAnyParam(_:paramNames:)`. the word-boundary
//    regex match that decides trigger B (child has no own generics but
//    its signature uses one of the parent's type-parameter names).
// 3. `buildParentConstraintsMap`. pass-1 SELECT against doc_symbols,
//    filtered to type kinds, de-dup-on-collision on doc_uri.
// 4. `propagateConstraintsFromParents`. the full orchestrator end to
//    end: triggers A and B, idempotence, empty-input no-op.
//
// In-memory SQLite fixtures (temp files) mirror the production schema
// from `Search.Index.Schema`. The full `Search.Index` is opened so the
// async public surface (`propagateConstraintsFromParents`) is exercised
// in the same shape the indexer hits at save time.

// MARK: - pure helpers (no SQLite)

@Suite("#759 iter-2. extractBareParamNames (pure)")
struct Issue759ExtractBareParamNamesTests {
    @Test(
        "Splits comma-separated entries and drops the constraint half after `:`",
        arguments: [
            // (input, expected)
            ("", []),
            ("T", ["T"]),
            ("T,U,V", ["T", "U", "V"]),
            ("Data,ID,Content", ["Data", "ID", "Content"]),
            ("T: Collection", ["T"]),
            ("T: Collection,U: View", ["T", "U"]),
            ("Element: Hashable & Sendable", ["Element"]),
            // Post-#759 AST output: bare + where-clause entries merged.
            // The bare names appear first; the `Name: Constraint` entries
            // re-list a subset of those names with constraints attached.
            // De-dup keeps only the first occurrence.
            ("Data,ID,Content,Data: RandomAccessCollection,ID: Hashable", ["Data", "ID", "Content"]),
            // Whitespace tolerance (the AST extractor's output isn't
            // guaranteed-trimmed).
            ("  T  ,  U  ", ["T", "U"]),
            // Empty trailing entry from a stray comma.
            ("T,", ["T"]),
            // Pathological: only commas → empty list.
            (",,,", []),
            // Same name listed twice without constraint. dedup.
            ("T,T", ["T"]),
            // Same name bare then with constraint. dedup; first wins.
            ("T,T: View", ["T"]),
        ] as [(String, [String])]
    )
    func splitsAndDedups(input: String, expected: [String]) {
        let actual = Search.Index.extractBareParamNames(from: input)
        #expect(actual == expected, "extractBareParamNames(\"\(input)\") = \(actual), expected \(expected)")
    }
}

@Suite("#759 iter-2. signatureReferencesAnyParam (word-boundary regex)")
struct Issue759SignatureReferencesAnyParamTests {
    @Test(
        "Matches at identifier word boundaries; rejects substring matches",
        arguments: [
            // (signature, paramNames, expectMatch)

            // -- TRUE matches ---------------------------------------------
            // After space, end of string.
            ("() -> Destination", ["Destination"], true),
            // Inside angle brackets.
            ("Binding<Destination>", ["Destination"], true),
            // After comma, end-of-string.
            ("(items: [Data], content: Content)", ["Data", "Content"], true),
            // Multiple param names. alternation picks any.
            ("(_ data: Data) -> Content", ["Data", "Content"], true),
            // After `(`, before `,`.
            ("init(_ Label: Label, destination: Destination)", ["Label", "Destination"], true),

            // -- FALSE: substring not at a word boundary ------------------
            // The docstring's headline example: `Row` must NOT match in `RowValue`.
            ("(_ row: RowValue) -> Bool", ["Row"], false),
            // Suffix substring: `Destination` followed by alnum.
            ("(_ key: DestinationKey)", ["Destination"], false),
            // Prefix substring: `_Data`. leading `_` is identifier-char.
            ("(_ x: _Data)", ["Data"], false),

            // -- FALSE: empty inputs --------------------------------------
            ("() -> Void", [], false),
            ("", ["T"], false),

            // -- TRUE: param name matches itself (defensive) ---------------
            ("T", ["T"], true),
        ] as [(String, [String], Bool)]
    )
    func wordBoundaryMatch(signature: String, paramNames: [String], expectMatch: Bool) {
        let actual = Search.Index.signatureReferencesAnyParam(signature, paramNames: paramNames)
        #expect(
            actual == expectMatch,
            "signatureReferencesAnyParam(\"\(signature)\", \(paramNames)) = \(actual), expected \(expectMatch)"
        )
    }
}

// MARK: - SQLite-backed (uses Search.Index on a temp DB)

/// Helpers shared by the SQLite-backed suites.
private enum Issue759Fixture {
    static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue759-hier-\(UUID().uuidString).db")
    }

    /// Insert a row into `docs_metadata` (the FK target for doc_symbols).
    /// Returns the row's uri unchanged so callers can chain.
    @discardableResult
    static func insertMetadata(_ db: OpaquePointer, uri: String, framework: String = "swiftui") throws -> String {
        let sql = """
        INSERT INTO docs_metadata (uri, framework, file_path, content_hash, last_crawled, word_count)
        VALUES (?, ?, ?, ?, 0, 0);
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "prep insertMetadata"])
        }
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (framework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ("/test/\(uri).json" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, ("h0" as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "Fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "exec insertMetadata"])
        }
        return uri
    }

    /// Insert a `doc_symbols` row. Caller supplies the kind, generic_params,
    /// generic_constraints, signature. the four columns iter-2 reads.
    static func insertSymbol(
        _ db: OpaquePointer,
        docUri: String,
        name: String,
        kind: String,
        signature: String? = nil,
        genericParams: String? = nil,
        genericConstraints: String? = nil
    ) throws {
        let sql = """
        INSERT INTO doc_symbols (doc_uri, name, kind, line, column, signature, generic_params, generic_constraints)
        VALUES (?, ?, ?, 0, 0, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "Fixture", code: 3, userInfo: [NSLocalizedDescriptionKey: "prep insertSymbol"])
        }
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
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "Fixture", code: 4, userInfo: [NSLocalizedDescriptionKey: "exec insertSymbol"])
        }
    }

    /// Read back the `generic_constraints` column for the row identified
    /// by docUri (returns nil if column is NULL or row missing).
    static func readConstraints(_ db: OpaquePointer, docUri: String) throws -> String? {
        let sql = "SELECT generic_constraints FROM doc_symbols WHERE doc_uri = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let ptr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: ptr)
    }

    /// Count NULL-constraints rows (sanity check for trigger evaluation).
    static func nullConstraintsCount(_ db: OpaquePointer) throws -> Int {
        let sql = "SELECT COUNT(*) FROM doc_symbols WHERE generic_constraints IS NULL;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return -1
        }
        return Int(sqlite3_column_int(stmt, 0))
    }
}

@Suite("#759 iter-2. propagateConstraintsFromParents end-to-end", .serialized)
struct Issue759PropagateEndToEndTests {
    @Test("Trigger A: child with own generic_params + NULL constraints inherits from parent type")
    func triggerAOwnGenericParams() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Open a raw handle to insert fixtures (production indexer code
        // path does this via its own write helpers; here we go direct
        // for fixture clarity).
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        let parentURI = "apple-docs://swiftui/foreach"
        let childURI = "apple-docs://swiftui/foreach/init-_-content"
        try Issue759Fixture.insertMetadata(#require(db), uri: parentURI)
        try Issue759Fixture.insertMetadata(#require(db), uri: childURI)
        // Parent struct with constraints.
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: parentURI, name: "ForEach", kind: "struct",
            genericParams: "Data,ID,Content,Data: RandomAccessCollection,ID: Hashable",
            genericConstraints: "RandomAccessCollection,Hashable"
        )
        // Child: own generic_params present (trigger A) but constraints NULL.
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: childURI, name: "init", kind: "init",
            signature: "init(data: Data, content: () -> Content)",
            genericParams: "Data,Content",
            genericConstraints: nil
        )

        try await idx.propagateConstraintsFromParents()
        await idx.disconnect()

        let inherited = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        #expect(
            inherited == "RandomAccessCollection,Hashable",
            "child should have inherited parent's constraints under trigger A; got \(inherited ?? "nil")"
        )
    }

    @Test("Trigger B: child with NO generic_params but signature references parent's type-param name")
    func triggerBSignatureMatch() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        let parentURI = "apple-docs://swiftui/navigationlink"
        let childURI = "apple-docs://swiftui/navigationlink/init-_-isactive-destination"
        try Issue759Fixture.insertMetadata(#require(db), uri: parentURI)
        try Issue759Fixture.insertMetadata(#require(db), uri: childURI)
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: parentURI, name: "NavigationLink", kind: "struct",
            genericParams: "Label,Destination,Label: View,Destination: View",
            genericConstraints: "View,View"
        )
        // Child: no own generic_params; signature references `Destination`.
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: childURI, name: "init", kind: "init",
            signature: "init(_ titleKey: LocalizedStringKey, isActive: Binding<Bool>, destination: () -> Destination)",
            genericParams: nil,
            genericConstraints: nil
        )

        try await idx.propagateConstraintsFromParents()
        await idx.disconnect()

        let inherited = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        #expect(
            inherited == "View,View",
            "child should have inherited parent's constraints under trigger B; got \(inherited ?? "nil")"
        )
    }

    @Test("No inheritance: child with no generic_params + signature missing parent's names stays NULL")
    func noInheritanceStaysNull() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        let parentURI = "apple-docs://swiftui/navigationlink"
        let childURI = "apple-docs://swiftui/navigationlink/static-helper"
        try Issue759Fixture.insertMetadata(#require(db), uri: parentURI)
        try Issue759Fixture.insertMetadata(#require(db), uri: childURI)
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: parentURI, name: "NavigationLink", kind: "struct",
            genericParams: "Label,Destination",
            genericConstraints: "View,View"
        )
        // Child: no generic_params, signature references nothing from parent.
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: childURI, name: "isSelected", kind: "func",
            signature: "isSelected() -> Bool",
            genericParams: nil,
            genericConstraints: nil
        )

        try await idx.propagateConstraintsFromParents()
        await idx.disconnect()

        let constraints = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        #expect(constraints == nil, "non-generic child should stay NULL; got \(constraints ?? "nil")")
    }

    @Test("Idempotent: re-running against an already-propagated DB is a no-op")
    func idempotent() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        let parentURI = "apple-docs://swiftui/foreach"
        let childURI = "apple-docs://swiftui/foreach/init-_-content"
        try Issue759Fixture.insertMetadata(#require(db), uri: parentURI)
        try Issue759Fixture.insertMetadata(#require(db), uri: childURI)
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: parentURI, name: "ForEach", kind: "struct",
            genericParams: "Data,Content",
            genericConstraints: "RandomAccessCollection,Hashable"
        )
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: childURI, name: "init", kind: "init",
            genericParams: "Data,Content"
        )

        try await idx.propagateConstraintsFromParents()
        let afterFirst = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        let nullCountAfterFirst = try Issue759Fixture.nullConstraintsCount(#require(db))

        try await idx.propagateConstraintsFromParents()
        let afterSecond = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        let nullCountAfterSecond = try Issue759Fixture.nullConstraintsCount(#require(db))

        await idx.disconnect()

        #expect(afterFirst == "RandomAccessCollection,Hashable")
        #expect(afterFirst == afterSecond, "second run must not change the value")
        #expect(nullCountAfterFirst == nullCountAfterSecond, "second run must not change row counts")
    }

    @Test("Empty parent map (no type rows with constraints) is a no-op")
    func emptyParentMapNoOp() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        // Only a child row; no parent type with constraints exists.
        let childURI = "apple-docs://swiftui/foreach/init-_-content"
        try Issue759Fixture.insertMetadata(#require(db), uri: childURI)
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: childURI, name: "init", kind: "init",
            genericParams: "Data,Content"
        )

        try await idx.propagateConstraintsFromParents()
        await idx.disconnect()

        let after = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        #expect(after == nil, "no parent → child stays NULL; got \(after ?? "nil")")
    }

    @Test("Methods/properties don't act as parents (kind filter)")
    func methodNotAParent() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        // "Parent" row is a method, not a type. buildParentConstraintsMap
        // must skip it (kind IN (...) filter). Even though the method
        // has constraints, no child should inherit from it.
        let methodURI = "apple-docs://swiftui/foreach/helper-method"
        let childURI = "apple-docs://swiftui/foreach/helper-method/nested-init"
        try Issue759Fixture.insertMetadata(#require(db), uri: methodURI)
        try Issue759Fixture.insertMetadata(#require(db), uri: childURI)
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: methodURI, name: "helper", kind: "func",
            genericParams: "T",
            genericConstraints: "Equatable"
        )
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: childURI, name: "init", kind: "init",
            genericParams: "T"
        )

        try await idx.propagateConstraintsFromParents()
        await idx.disconnect()

        let after = try Issue759Fixture.readConstraints(#require(db), docUri: childURI)
        #expect(after == nil, "method-parent must NOT propagate (kind filter); got \(after ?? "nil")")
    }

    @Test("Mixed corpus: trigger-A child + trigger-B child + no-inheritance sibling. only the two qualifying rows update")
    func mixedCorpus() async throws {
        let dbPath = Issue759Fixture.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            Issue.record("could not open temp DB at \(dbPath.path)")
            return
        }
        defer { sqlite3_close(db) }

        let parentURI = "apple-docs://swiftui/navigationlink"
        let aURI = "apple-docs://swiftui/navigationlink/init-content" // trigger A
        let bURI = "apple-docs://swiftui/navigationlink/init-destination" // trigger B
        let nURI = "apple-docs://swiftui/navigationlink/static-helper" // neither

        for uri in [parentURI, aURI, bURI, nURI] {
            try Issue759Fixture.insertMetadata(#require(db), uri: uri)
        }
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: parentURI, name: "NavigationLink", kind: "struct",
            genericParams: "Label,Destination",
            genericConstraints: "View,View"
        )
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: aURI, name: "init", kind: "init",
            signature: "init(_ x: Int)",
            genericParams: "Label", // trigger A
            genericConstraints: nil
        )
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: bURI, name: "init", kind: "init",
            signature: "init(_ y: () -> Destination)", // trigger B
            genericParams: nil,
            genericConstraints: nil
        )
        try Issue759Fixture.insertSymbol(
            #require(db), docUri: nURI, name: "isSelected", kind: "func",
            signature: "isSelected() -> Bool",
            genericParams: nil,
            genericConstraints: nil
        )

        try await idx.propagateConstraintsFromParents()
        await idx.disconnect()

        #expect(try Issue759Fixture.readConstraints(#require(db), docUri: aURI) == "View,View")
        #expect(try Issue759Fixture.readConstraints(#require(db), docUri: bURI) == "View,View")
        #expect(try Issue759Fixture.readConstraints(#require(db), docUri: nURI) == nil)
    }
}

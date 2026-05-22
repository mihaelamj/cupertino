import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #759 iter 2 — additional defensive contracts

//
// Companion to `Issue759HierarchyConstraintsTests` (which covers the
// happy-path triggers A + B + 7 other scenarios shipped in PR #762).
// This file pins the defensive contracts the main test surface didn't
// directly assert:
//
//   - Existing constraints not overwritten (the WHERE-NULL filter on
//     iter-2's UPDATE is load-bearing — iter-2 fills in NULL rows but
//     does NOT clobber iter-1 or iter-3's output)
//   - Multiple parent rows at same doc_uri: longest-constraints wins
//   - Three-level hierarchy: propagation is one-level-up, doesn't
//     transitively cross multiple levels in a single pass
//   - Sibling propagation: two methods sharing one parent both inherit
//   - Parent kind = typealias: still acts as a parent (typealias is in
//     the WHERE clause's kind list)
//   - Child has both trigger A AND trigger B: applied once, no double
//     write of identical data
//   - Parent's generic_params empty string: degrades cleanly (no
//     bare param names → trigger B never fires)

@Suite("#759 iter-2 — defensive contracts", .serialized)
struct Issue759HierarchyDefensiveTests {
    private static func makeFreshDB() async throws -> (dbPath: URL, index: Search.Index) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-759-defensive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        return (dbPath, index)
    }

    @discardableResult
    private static func seedSymbol(
        dbPath: URL,
        docUri: String,
        kind: String,
        name: String,
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

    // MARK: - existing constraints preserved

    @Test("Existing generic_constraints row is NOT overwritten (iter-2 WHERE-NULL filter is load-bearing)")
    func existingConstraintsNotOverwritten() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            kind: "struct",
            name: "ForEach",
            genericParams: "Data,ID,Content",
            genericConstraints: "RandomAccessCollection,Hashable"
        )
        // Child method has its OWN constraint already (from iter-1 or iter-3).
        // Iter-2 must not clobber this even though the row would otherwise
        // trigger A (own generic_params present).
        let methodId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach/init",
            kind: "initializer",
            name: "init",
            signature: "init<T>(x: T) where T: View",
            genericParams: "T,T: View",
            genericConstraints: "View"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: methodId)
        #expect(result == "View", "iter-2 must NOT overwrite existing constraints; got \(String(describing: result))")
    }

    // MARK: - parent-map tie-break

    @Test("Multiple parent rows at same doc_uri: longest constraint blob wins per in-source tie-break comment")
    func multipleParentRowsSameUriLongestWins() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Two type rows share the same doc_uri (e.g. typealias + struct
        // co-located on one Apple doc page). Parent map keeps the one
        // with the longer constraint blob (rationale: longer = more
        // informative for search).
        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            kind: "typealias",
            name: "ForEach.Iterator",
            genericConstraints: "View"
        )
        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach",
            kind: "struct",
            name: "ForEach",
            genericParams: "Data,ID,Content",
            genericConstraints: "RandomAccessCollection,Hashable"
        )
        let childId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/foreach/init",
            kind: "initializer",
            name: "init",
            signature: "init(_ data: Data, content: (Data.Element) -> Content)"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: childId)
        #expect(result == "RandomAccessCollection,Hashable", "longer constraint blob should win the tie-break; got \(String(describing: result))")
    }

    // MARK: - three-level hierarchy

    @Test("Three-level hierarchy: propagation is one-level-up; child without immediate parent constraint doesn't reach grandparent")
    func threeLevelHierarchyOneLevelUp() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Grandparent has constraints. Parent has none. Child has bare
        // generic_params. Propagation walks parent_uri = strip-last-segment
        // (one level only); doesn't recurse.
        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/grandparent",
            kind: "struct",
            name: "Grandparent",
            genericParams: "T",
            genericConstraints: "View"
        )
        // Mid-level row exists at the URI but has no constraints.
        // (Not strictly required for parent-strip behaviour; documents
        // the intermediate scope.)
        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/grandparent/parent",
            kind: "function",
            name: "parent"
        )
        // Child's parent URI = "apple-docs://swiftui/grandparent/parent"
        // (the function above) — NOT a type, so not in the parent map.
        let childId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/grandparent/parent/child",
            kind: "initializer",
            name: "init",
            genericParams: "U"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: childId)
        #expect(result == nil, "single-level propagation: child's immediate parent isn't a type → no inheritance from grandparent; got \(String(describing: result))")
    }

    // MARK: - sibling propagation

    @Test("Two sibling methods sharing one parent type: both inherit the same blob")
    func twoSiblingsBothInherit() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/picker",
            kind: "struct",
            name: "Picker",
            genericParams: "Label,SelectionValue,Content,Label: View,SelectionValue: Hashable,Content: View",
            genericConstraints: "View,Hashable,View"
        )
        let init1Id = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/picker/init(_:selection:content:)",
            kind: "initializer",
            name: "init",
            signature: "init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, content: () -> Content)"
        )
        let init2Id = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/picker/init(selection:label:content:)",
            kind: "initializer",
            name: "init",
            signature: "init(selection: Binding<SelectionValue>, label: () -> Label, content: () -> Content)"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        let r1 = try Self.readConstraints(dbPath: dbPath, rowId: init1Id)
        let r2 = try Self.readConstraints(dbPath: dbPath, rowId: init2Id)
        #expect(r1 == "View,Hashable,View", "first sibling inherits parent blob; got \(String(describing: r1))")
        #expect(r2 == "View,Hashable,View", "second sibling inherits parent blob; got \(String(describing: r2))")
    }

    // MARK: - parent kind = typealias

    @Test("Parent kind = typealias: still acts as a parent in the propagation map")
    func typealiasActsAsParent() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/myalias",
            kind: "typealias",
            name: "MyAlias",
            genericParams: "T,T: View",
            genericConstraints: "View"
        )
        let childId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/myalias/method",
            kind: "function",
            name: "method",
            signature: "func method(_ x: T) -> T"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: childId)
        #expect(result == "View", "typealias kind should be in the parent-map WHERE filter; got \(String(describing: result))")
    }

    // MARK: - both triggers fire simultaneously

    @Test("Child fires both trigger A AND trigger B simultaneously: applied once with parent's blob")
    func bothTriggersFireOnce() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/navigationlink",
            kind: "struct",
            name: "NavigationLink",
            genericParams: "Label,Destination,Label: View,Destination: View",
            genericConstraints: "View,View"
        )
        // Child has:
        //   - own generic_params (trigger A)
        //   - signature that ALSO references Destination (trigger B)
        // Should produce ONE UPDATE with the parent's blob (not two).
        let childId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/navigationlink/init",
            kind: "initializer",
            name: "init",
            signature: "init<T>(destination: () -> Destination) where T: View",
            genericParams: "T"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        let result = try Self.readConstraints(dbPath: dbPath, rowId: childId)
        #expect(result == "View,View", "dual-trigger child should inherit once with parent's blob; got \(String(describing: result))")
    }

    // MARK: - parent's generic_params is empty string

    @Test("Parent's generic_params empty string: trigger B can't match (no bare names), trigger A still works")
    func parentEmptyGenericParamsDegradesGracefully() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Parent type with empty generic_params but with constraints
        // (an edge case — typically these would be coupled). The
        // extractBareParamNames helper short-circuits empty to [], so
        // trigger B has nothing to word-boundary-match against.
        try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/edgecase",
            kind: "struct",
            name: "EdgeCase",
            genericParams: "",
            genericConstraints: "View"
        )
        // Child with EMPTY own generic_params + signature referencing a
        // common name. Trigger A skipped (own params empty), trigger B
        // skipped (parent param names empty). Row stays NULL.
        let nullChildId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/edgecase/method",
            kind: "function",
            name: "method",
            signature: "func method() -> T"
        )
        // Child with bare own generic_params: trigger A still fires.
        let triggerAChildId = try Self.seedSymbol(
            dbPath: dbPath,
            docUri: "apple-docs://swiftui/edgecase/method2",
            kind: "function",
            name: "method2",
            genericParams: "T"
        )

        try await index.propagateConstraintsFromParents()
        await index.disconnect()

        #expect(try Self.readConstraints(dbPath: dbPath, rowId: nullChildId) == nil, "trigger B with empty parent params → no inherit")
        #expect(try Self.readConstraints(dbPath: dbPath, rowId: triggerAChildId) == "View", "trigger A still fires regardless of parent param-names extraction")
    }
}

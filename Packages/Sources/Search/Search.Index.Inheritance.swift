import Foundation
import SearchModels
import SQLite3

extension Search.Index {
    /// Write class-inheritance edges to the `inheritance` table (#274).
    ///
    /// Each directed edge is one row: `(parent_uri, child_uri)`. The
    /// table's composite primary key dedupes edges that show up from
    /// both ends — e.g. `UIControl.inheritedBy` lists `UIButton` and
    /// `UIButton.inheritsFrom` lists `UIControl`; whichever page is
    /// indexed first writes the row, the second `INSERT OR IGNORE`
    /// silently no-ops.
    ///
    /// Empty / nil inputs are a no-op (most pages are structs, enums,
    /// protocols, or property pages that legitimately have no
    /// inheritance edges to write). The page's own URI is one end of
    /// every edge it contributes:
    ///
    /// - For each `parentURI` in `inheritsFromURIs`: emit
    ///   `(parent_uri: parentURI, child_uri: pageURI)`.
    /// - For each `childURI` in `inheritedByURIs`: emit
    ///   `(parent_uri: pageURI, child_uri: childURI)`.
    ///
    /// Re-indexing the same page must not produce duplicate rows
    /// (the indexer can be re-run incrementally). The composite
    /// primary key + `INSERT OR IGNORE` handles that.
    func writeInheritanceEdges(
        pageURI: String,
        inheritsFromURIs: [String]?,
        inheritedByURIs: [String]?
    ) async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }
        let inheritsFrom = inheritsFromURIs ?? []
        let inheritedBy = inheritedByURIs ?? []
        guard !inheritsFrom.isEmpty || !inheritedBy.isEmpty else {
            return
        }

        let sql = """
        INSERT OR IGNORE INTO inheritance (parent_uri, child_uri)
        VALUES (?, ?);
        """

        for parentURI in inheritsFrom {
            try insertEdge(database: database, sql: sql, parent: parentURI, child: pageURI)
        }
        for childURI in inheritedBy {
            try insertEdge(database: database, sql: sql, parent: pageURI, child: childURI)
        }
    }

    private func insertEdge(
        database: OpaquePointer,
        sql: String,
        parent: String,
        child: String
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.prepareFailed("inheritance insert: \(errorMessage)")
        }
        sqlite3_bind_text(statement, 1, (parent as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (child as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.insertFailed("inheritance insert: \(errorMessage)")
        }
    }

    /// Read ancestors of `childURI`. Walks `WHERE child_uri = ?` —
    /// one row per immediate parent. Caller composes recursive walks
    /// (no SQL recursion required; the table is small enough that
    /// repeated single-row lookups stay fast).
    public func parentsOf(childURI: String) async throws -> [String] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }
        let sql = "SELECT parent_uri FROM inheritance WHERE child_uri = ? ORDER BY parent_uri;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(statement, 1, (childURI as NSString).utf8String, -1, nil)
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(statement, 0) {
                result.append(String(cString: ptr))
            }
        }
        return result
    }

    /// Read descendants of `parentURI`. Walks `WHERE parent_uri = ?`.
    public func childrenOf(parentURI: String) async throws -> [String] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }
        let sql = "SELECT child_uri FROM inheritance WHERE parent_uri = ? ORDER BY child_uri;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(statement, 1, (parentURI as NSString).utf8String, -1, nil)
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(statement, 0) {
                result.append(String(cString: ptr))
            }
        }
        return result
    }

    /// Count of edges in the `inheritance` table (for diagnostics +
    /// the `cupertino doctor` post-index summary).
    public func inheritanceEdgeCount() async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }
        let sql = "SELECT COUNT(*) FROM inheritance;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}

import Foundation
import SearchModels
import SQLite3

extension Search.Indexer {
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
    public func writeInheritanceEdges(
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
}

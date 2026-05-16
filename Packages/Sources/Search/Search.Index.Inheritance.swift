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

    // MARK: - High-level walks for CLI + MCP

    /// Resolve a user-supplied symbol name to its apple-docs URI(s).
    ///
    /// Returns one URI when the title is unique (the common case for
    /// most UIKit/AppKit/Foundation classes). Returns multiple URIs
    /// when the same title exists in multiple frameworks
    /// (`Color` → SwiftUI / AppKit, `View` → SwiftUI / UIKit, etc.) —
    /// the caller must surface a disambiguation block in that case.
    /// Returns empty when no apple-docs page has the title.
    ///
    /// Match is case-insensitive on `title` (Apple uses `UIButton`
    /// in the title but a user might type `uibutton`). Source is
    /// pinned to `apple-docs` since inheritance edges only exist
    /// for that source.
    public func resolveSymbolURIs(title: String) async throws -> [Search.InheritanceCandidate] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }
        let sql = """
        SELECT uri, framework, COALESCE(json_extract(json_data, '$.title'), '') as t
        FROM docs_metadata
        WHERE source = 'apple-docs'
            AND LOWER(json_extract(json_data, '$.title')) = LOWER(?)
        ORDER BY framework;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        var candidates: [Search.InheritanceCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uriPtr = sqlite3_column_text(statement, 0) else { continue }
            let framework = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            candidates.append(Search.InheritanceCandidate(
                uri: String(cString: uriPtr),
                framework: framework,
                title: title
            ))
        }
        return candidates
    }

    /// Walk the inheritance graph from `startURI` in the given direction
    /// up to `maxDepth` hops.
    ///
    /// - `direction == .up`: follows `parentsOf` recursively (ancestor chain).
    /// - `direction == .down`: follows `childrenOf` recursively (descendant tree).
    /// - `direction == .both`: walks both directions concurrently.
    ///
    /// `maxDepth = 0` returns just the start node with no neighbours.
    /// `maxDepth` defaults to 5 in the CLI / MCP entry points so a
    /// query like `inheritance UIView --direction down` doesn't try to
    /// emit all thousands of UIView descendants in one go. Cycles are
    /// impossible in real Apple inheritance data but the walker
    /// guards with a visited-set anyway (cheap insurance).
    public func walkInheritance(
        startURI: String,
        direction: Search.InheritanceDirection,
        maxDepth: Int
    ) async throws -> Search.InheritanceTree {
        var visited: Set<String> = [startURI]
        let ups = direction == .up || direction == .both
            ? try await walk(from: startURI, mode: .parents, depth: maxDepth, visited: &visited)
            : []
        let downs = direction == .down || direction == .both
            ? try await walk(from: startURI, mode: .children, depth: maxDepth, visited: &visited)
            : []
        return Search.InheritanceTree(
            startURI: startURI,
            ancestors: ups,
            descendants: downs
        )
    }

    private enum WalkMode { case parents, children }

    /// Single-direction recursive walk. Returns the tree of nodes
    /// reachable from `from` in the requested direction up to `depth`
    /// hops. Each level's nodes are visited before recursing so the
    /// returned shape mirrors the BFS frontier rather than depth-first.
    private func walk(
        from uri: String,
        mode: WalkMode,
        depth: Int,
        visited: inout Set<String>
    ) async throws -> [Search.InheritanceNode] {
        guard depth > 0 else { return [] }
        let neighbours: [String]
        switch mode {
        case .parents: neighbours = try await parentsOf(childURI: uri)
        case .children: neighbours = try await childrenOf(parentURI: uri)
        }
        var nodes: [Search.InheritanceNode] = []
        for neighbour in neighbours {
            guard visited.insert(neighbour).inserted else { continue }
            let children = try await walk(
                from: neighbour,
                mode: mode,
                depth: depth - 1,
                visited: &visited
            )
            nodes.append(Search.InheritanceNode(uri: neighbour, children: children))
        }
        return nodes
    }
}

// `Search.InheritanceCandidate` / `InheritanceDirection` /
// `InheritanceNode` / `InheritanceTree` live in the `SearchModels`
// target so the protocol surface in `Search.Database` can name them
// without pulling the concrete `Search` target into consumers.

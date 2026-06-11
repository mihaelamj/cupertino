import Foundation
import SearchModels
import SQLite3

extension Search.Index {
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
    ///
    /// #754 — Apple's DocC stores titles in two shapes across the
    /// corpus: the bare symbol name (e.g. `"UIView"`) and the HTML
    /// page-title form with a site suffix (e.g.
    /// `"NSObject | Apple Developer Documentation"`). On the
    /// 2026-05-17 reindex the split is ~63% bare / ~37% suffixed —
    /// both forms are widespread. Pre-fix the predicate only matched
    /// the bare form, so high-traffic root types like NSObject (which
    /// happen to store the suffixed form) returned empty. Fix strips
    /// the suffix via SQLite's `REPLACE` before the equality compare,
    /// so the bare user input (`"NSObject"`) matches whichever form
    /// the stored title uses. No index helps either way (function
    /// calls in the WHERE clause force a full scan; the table has
    /// ~351k rows + the scan completes in single-digit milliseconds
    /// per the test-suite timings).
    public func resolveSymbolURIs(title: String) async throws -> [Search.InheritanceCandidate] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }
        // #754 secondary: fetch the finer-grained kind (`class` / `protocol`
        // / `struct` / `enum` / `actor` / ...) from `docs_structured.kind`
        // so the response formatter can distinguish a class-at-root
        // (NSObject going `up`) from a value type or protocol. The
        // coarser `docs_metadata.kind` is always `symbolPage` for symbol
        // pages, which doesn't help. LEFT JOIN so rows without a
        // `docs_structured` companion still return a candidate (kind = nil
        // routes to the legacy fallback message).
        let sql = """
        SELECT m.uri, m.framework, COALESCE(json_extract(m.json_data, '$.title'), '') as t, s.kind
        FROM docs_metadata m
        LEFT JOIN docs_structured s ON s.uri = m.uri
        WHERE m.source = 'apple-docs'
            AND LOWER(REPLACE(
                json_extract(m.json_data, '$.title'),
                ' | Apple Developer Documentation',
                ''
            )) = LOWER(?)
        ORDER BY m.framework;
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
            let kind = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            candidates.append(Search.InheritanceCandidate(
                uri: String(cString: uriPtr),
                framework: framework,
                title: title,
                kind: kind
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

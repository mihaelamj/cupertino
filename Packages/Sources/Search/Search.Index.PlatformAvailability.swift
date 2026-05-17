import Foundation
import SearchModels
import SQLite3

// MARK: - #226 — platform-availability batch lookup

extension Search.Index {
    /// Batch-fetch `min_*` platform availability values from
    /// `docs_metadata` for a list of URIs in one round-trip. Used by
    /// `CompositeToolProvider`'s search-style tool handlers
    /// (`search_symbols`, `search_property_wrappers`,
    /// `search_concurrency`, `search_conformances`) to apply the
    /// `--platform` / `--min-version` MCP arg filters that #226
    /// added on the MCP surface.
    ///
    /// Why batched: a typical search returns up to ~20 results; the
    /// per-result `SymbolSearchResult` doesn't carry platform versions,
    /// so a naive client-side filter would issue 20 separate DB
    /// queries. One `SELECT … WHERE uri IN (?, ?, …)` does it once.
    ///
    /// Returns a `[uri → PlatformMinima]` map. URIs that don't appear
    /// in `docs_metadata` (extremely rare — symbols always JOIN to a
    /// metadata row in practice) are absent from the map; callers
    /// treat missing entries as "no platform info; reject when any
    /// filter is set" — matches the unified `search` tool's
    /// IS-NOT-NULL pre-gate behaviour at
    /// `Search.Index.Search.swift:166-180`.
    public func fetchPlatformMinima(
        uris: [String]
    ) async throws -> [String: Search.PlatformMinima] {
        guard !uris.isEmpty else { return [:] }
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Build a `?,?,?…` placeholder list. SQLite's parameterised IN
        // doesn't accept arrays directly — one ? per value is the
        // documented pattern. Bounded by the result count (≤ ~20 in
        // practice for search-tool callers), so no need for chunking.
        let placeholders = Array(repeating: "?", count: uris.count).joined(separator: ", ")
        let sql = """
        SELECT uri, min_ios, min_macos, min_tvos, min_watchos, min_visionos
        FROM docs_metadata
        WHERE uri IN (\(placeholders));
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Platform availability fetch failed: \(errorMessage)")
        }

        for (idx, uri) in uris.enumerated() {
            sqlite3_bind_text(stmt, Int32(idx + 1), (uri as NSString).utf8String, -1, nil)
        }

        var result: [String: Search.PlatformMinima] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let uri = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let minIOS = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let minMacOS = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let minTvOS = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let minWatchOS = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let minVisionOS = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            result[uri] = Search.PlatformMinima(
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS
            )
        }
        return result
    }
}

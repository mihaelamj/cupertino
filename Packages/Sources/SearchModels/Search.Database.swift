import Foundation
import SharedConstants

/// Behavioural contract for the search-index database.
///
/// Production implementation: `Search.Index` (the actor in the Search SPM
/// target). Consumers — Services read commands, MCPSupport responders,
/// CLI runners — accept this protocol instead of taking a behavioural
/// dependency on the Search target.
///
/// The protocol surfaces every method Services calls on `Search.Index`:
/// `search`, `getDocumentContent`, `listFrameworks`, `documentCount`,
/// and `disconnect`. The full-parameter `search` lives on the protocol
/// itself; a convenience overload with `nil`-defaulted platform filters
/// is provided as a protocol extension so existing call sites with
/// fewer arguments compile unchanged.
extension Search {
    public protocol Database: Sendable {
        /// Run a full search across the index.
        ///
        /// - Parameters:
        ///   - query: Free-text query (FTS5 syntax).
        ///   - source: Filter by source prefix (`apple-docs`, `samples`, …).
        ///   - framework: Filter by framework slug.
        ///   - language: Filter by primary language (`swift`, `objc`, `c`).
        ///   - limit: Maximum number of results.
        ///   - includeArchive: Include archive results when `source` is nil.
        ///   - minIOS / minMacOS / minTvOS / minWatchOS / minVisionOS:
        ///     Filter rows whose minimum-version annotation falls below the
        ///     dotted-decimal threshold. Pass `nil` to skip a platform.
        func search(
            query: String,
            source: String?,
            framework: String?,
            language: String?,
            limit: Int,
            includeArchive: Bool,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?,
        ) async throws -> [Search.Result]

        /// Fetch the pre-rendered document content for a URI.
        ///
        /// Returns `nil` when the URI is not present in the index. Throws
        /// only on real database failures.
        func getDocumentContent(uri: String, format: Search.DocumentFormat) async throws -> String?

        /// All frameworks present in the index with their document counts.
        func listFrameworks() async throws -> [String: Int]

        /// Total document count across every source in the index.
        func documentCount() async throws -> Int

        /// Close the database connection. Idempotent; safe to call from a
        /// `defer` even when the actor has already shut down.
        func disconnect() async

        // MARK: - Semantic Symbol Search (#81)

        /// Semantic search across AST-extracted symbols by name pattern + kind.
        func searchSymbols(
            query: String?,
            kind: String?,
            isAsync: Bool?,
            framework: String?,
            limit: Int,
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search for property-wrapper attributes (e.g. `@Observable`,
        /// `@State`, `@MainActor`).
        func searchPropertyWrappers(
            wrapper: String,
            framework: String?,
            limit: Int,
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search for Swift concurrency patterns
        /// (`async`, `actor`, `sendable`, `mainactor`, `task`, `asyncsequence`).
        func searchConcurrencyPatterns(
            pattern: String,
            framework: String?,
            limit: Int,
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search for types by protocol conformance.
        func searchConformances(
            protocolName: String,
            framework: String?,
            limit: Int,
        ) async throws -> [Search.SymbolSearchResult]
    }
}

// MARK: - Convenience overload with defaulted platform filters

extension Search.Database {
    /// Convenience overload that defaults every platform-availability
    /// filter to `nil`. Callers who don't restrict by minimum OS version
    /// stay one line.
    public func search(
        query: String,
        source: String? = nil,
        framework: String? = nil,
        language: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit,
        includeArchive: Bool = false,
    ) async throws -> [Search.Result] {
        try await search(
            query: query,
            source: source,
            framework: framework,
            language: language,
            limit: limit,
            includeArchive: includeArchive,
            minIOS: nil,
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil,
        )
    }
}

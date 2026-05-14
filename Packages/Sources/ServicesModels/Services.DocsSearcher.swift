import Foundation
import SearchModels

// MARK: - Services.DocsSearcher

/// Minimal read-only seam for a docs-search service.
///
/// Captures the surface that `SearchToolProvider` (and any future MCP /
/// CLI consumer) actually calls on `Services.DocsSearchService` — a
/// single `search(_:) async throws -> [Search.Result]` method. The
/// concrete actor in the `Services` target conforms via a one-line
/// witness extension; consumers hold `any Services.DocsSearcher`
/// instead of the actor, so they can drop their `import Services`
/// once their other Services uses are also seamed.
///
/// Mirrors the `Search.Database` / `Sample.Index.Reader` /
/// `Sample.Search.Searcher` pattern: protocol in a foundation-only
/// Models target, conformance witness in the producer target, wiring
/// at the composition root.
extension Services {
    public protocol DocsSearcher: Sendable {
        /// Search for documents matching the query across the configured
        /// sources (apple-docs, swift-evolution, swift-org, swift-book,
        /// apple-archive, hig).
        func search(_ query: Services.SearchQuery) async throws -> [Search.Result]
    }
}

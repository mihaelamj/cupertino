import Foundation

// MARK: - Services.UnifiedSearcher

/// Minimal read-only seam for the unified-search service.
///
/// Captures the surface that `SearchToolProvider` actually calls on
/// `Services.UnifiedSearchService` — a single `searchAll(...)` method
/// that returns a `Services.Formatter.Unified.Input` snapshot ready to
/// be rendered by the unified-search formatter family.
///
/// Mirrors the `Services.DocsSearcher` / `Services.Teaser` /
/// `Sample.Search.Searcher` pattern: protocol in a foundation-only
/// Models target, conformance witness in the producer target, wiring
/// at the composition root.
extension Services {
    public protocol UnifiedSearcher: Sendable {
        /// Search every configured source (apple-docs, apple-archive,
        /// samples, hig, swift-evolution, swift-org, swift-book,
        /// packages) and return a `Services.Formatter.Unified.Input`
        /// snapshot holding the per-source result arrays + the
        /// per-source limit.
        func searchAll(
            query: String,
            framework: String?,
            limit: Int
        ) async -> Services.Formatter.Unified.Input
    }
}

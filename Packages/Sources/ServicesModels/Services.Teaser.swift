import Foundation

// MARK: - Services.Teaser

/// Minimal read-only seam for the teaser-fetching service.
///
/// Captures the surface that `SearchToolProvider` actually calls on
/// `Services.TeaserService` — a single
/// `fetchAllTeasers(query:framework:currentSource:includeArchive:)`
/// method that returns a `Services.Formatter.TeaserResults` snapshot.
/// The concrete actor in the `Services` target conforms via a one-line
/// witness extension; consumers hold `any Services.Teaser` and can drop
/// their `import Services` for this call.
///
/// Mirrors the `Services.DocsSearcher` / `Sample.Search.Searcher`
/// pattern from #487: protocol in a foundation-only Models target,
/// conformance witness in the producer target, wiring at the
/// composition root.
extension Services {
    public protocol Teaser: Sendable {
        /// Fetch teaser results from every source except the one being
        /// searched (driven by `currentSource`). Returns a populated
        /// `Services.Formatter.TeaserResults` snapshot — empty
        /// per-source arrays for sources that don't apply.
        func fetchAllTeasers(
            query: String,
            framework: String?,
            currentSource: String?,
            includeArchive: Bool
        ) async -> Services.Formatter.TeaserResults
    }
}

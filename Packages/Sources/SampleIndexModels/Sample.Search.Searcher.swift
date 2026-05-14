import Foundation
import SharedConstants

// MARK: - Sample.Search.Searcher

/// Minimal read-only seam for a sample-code-search service.
///
/// Captures the surface that `SearchToolProvider` (and any future MCP /
/// CLI consumer) actually calls on `Sample.Search.Service` — a single
/// `search(_:) async throws -> Sample.Search.Result` method. The
/// concrete actor in the `Services` target conforms via a one-line
/// witness extension; consumers hold `any Sample.Search.Searcher`
/// instead of the actor.
///
/// Mirrors the `Search.Database` / `Sample.Index.Reader` /
/// `Services.DocsSearcher` pattern: protocol in a foundation-only
/// Models target, conformance witness in the producer target, wiring
/// at the composition root.
extension Sample.Search {
    public protocol Searcher: Sendable {
        /// Search Apple sample-code projects and files for the given
        /// query parameters.
        func search(_ query: Sample.Search.Query) async throws -> Sample.Search.Result
    }
}

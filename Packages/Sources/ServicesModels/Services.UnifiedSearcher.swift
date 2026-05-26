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
        ///
        /// #226 expansion: the 5 `min_*` platform filters + `minSwift`
        /// are threaded through to each search.db-backed fetcher (apple-
        /// docs, apple-archive, swift-evolution, swift-org, swift-book,
        /// hig, packages) so a fan-out call now applies the filter
        /// uniformly across the 6 article-or-symbol sources that go
        /// through `Search.Database.search`. Pre-#226 the unified
        /// fan-out dropped these args silently for every source. The
        /// `samples` fetcher remains unfiltered in the fan-out path
        /// today — `Sample.Index.Database.searchProjects` doesn't yet
        /// accept platform args (the `searchFiles` path does, but
        /// returns a different result shape that the unified formatter
        /// can't consume without further work). Filed as #732 follow-up.
        func searchAll(
            query: String,
            framework: String?,
            limit: Int,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?,
            minSwift: String?,
            appleImports: String?,
            availableSources: [String]?
        ) async -> Services.Formatter.Unified.Input
    }
}

// MARK: - Backward-compatible default (pre-`availableSources`)

extension Services.UnifiedSearcher {
    /// #1042 Cluster 2 wiring: registry-supplied source-id list for the
    /// formatter's "Searched ALL sources" header + footer tip. Pre-fix
    /// the conformer always built the list from the foundation-tier
    /// static. Default nil here keeps existing callers compiling; the
    /// composition root (MCP `CompositeToolProvider.handleSearchAll`)
    /// supplies a registry-derived list to make the new source visible
    /// in the formatter output.
    public func searchAll(
        query: String,
        framework: String?,
        limit: Int,
        minIOS: String?,
        minMacOS: String?,
        minTvOS: String?,
        minWatchOS: String?,
        minVisionOS: String?,
        minSwift: String?,
        appleImports: String?
    ) async -> Services.Formatter.Unified.Input {
        await searchAll(
            query: query,
            framework: framework,
            limit: limit,
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS,
            minSwift: minSwift,
            appleImports: appleImports,
            availableSources: nil
        )
    }
}

// MARK: - Backward-compatible default (pre-`appleImports`)

extension Services.UnifiedSearcher {
    /// Legacy nine-arg overload retained so call sites that haven't been
    /// migrated to thread the `apple_imports` MCP arg through compile
    /// unchanged. Forwards to the new ten-arg requirement with
    /// `appleImports: nil`.
    public func searchAll(
        query: String,
        framework: String?,
        limit: Int,
        minIOS: String?,
        minMacOS: String?,
        minTvOS: String?,
        minWatchOS: String?,
        minVisionOS: String?,
        minSwift: String?
    ) async -> Services.Formatter.Unified.Input {
        await searchAll(
            query: query,
            framework: framework,
            limit: limit,
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS,
            minSwift: minSwift,
            appleImports: nil
        )
    }
}

// MARK: - Backward-compatible default

extension Services.UnifiedSearcher {
    /// Legacy zero-platform-args overload — preserved for callers that
    /// haven't been migrated to thread platform filters through. Maps to
    /// the new shape with every `min_*` / `minSwift` argument set to nil.
    /// Existing call sites compile unchanged; new platform-filtered
    /// behaviour is opt-in.
    public func searchAll(
        query: String,
        framework: String?,
        limit: Int
    ) async -> Services.Formatter.Unified.Input {
        await searchAll(
            query: query,
            framework: framework,
            limit: limit,
            minIOS: nil,
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil,
            minSwift: nil
        )
    }
}

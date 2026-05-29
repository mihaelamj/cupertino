import Foundation

// MARK: - Search.WebCrawlStrategyFactory

extension Search {
    /// GoF Abstract Factory (1994 p. 87) seam for the shared web-crawl
    /// fetch strategy. The concrete `WebCrawlFetchStrategy` + its crawl
    /// engine (`Crawler.AppleDocs` + `Ingest`) live in the macOS-side
    /// `Crawler` producer; the three web-crawl source providers
    /// (apple-docs, swift-org, swift-book) depend only on this seam and
    /// receive the factory by init injection from the composition root
    /// (#536 lift 4).
    ///
    /// Decoupling the source providers from the crawl-engine concrete is
    /// load-bearing for the Linux runtime: the providers must build on
    /// Linux (they back the read/serve registry), while the crawl engine
    /// is macOS-only. The factory is wired only on macOS; a Linux build
    /// supplies no factory (or a no-op), and the crawl path is never
    /// exercised there.
    ///
    /// Returns `any Search.SourceFetchStrategy`, so the protocol lives in
    /// `SearchModels` rather than `CrawlerModels` (which `SearchModels`
    /// already imports; the reverse would cycle).
    public protocol WebCrawlStrategyFactory: Sendable {
        /// Build a web-crawl fetch strategy for a source.
        ///
        /// - Parameters:
        ///   - defaultCrawlBaseURL: fallback seed URL when `env.startURL`
        ///     is nil (the source's canonical seed).
        ///   - defaultAllowedPrefixes: URL prefix allowlist when
        ///     `env.allowedPrefixes` is nil (multi-host sources supply
        ///     their own list).
        ///   - candidateSessionDirectories: per-source dirs searched for
        ///     a resumable session when `--output-dir` isn't supplied.
        func makeStrategy(
            defaultCrawlBaseURL: String,
            defaultAllowedPrefixes: [String]?,
            candidateSessionDirectories: [URL]
        ) -> any Search.SourceFetchStrategy
    }
}

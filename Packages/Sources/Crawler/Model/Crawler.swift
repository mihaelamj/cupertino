import Foundation

// MARK: - Crawler Namespace (foundation-only anchor)

/// Foundation-only namespace anchor for the `Crawler` SPM target. Lives
/// in `CrawlerModels` (this target) so consumers can extend `Crawler.*`
/// with protocols and value types without importing the concrete
/// `Crawler` target. The concrete `Crawler` target re-uses this same
/// namespace via `import CrawlerModels`.
///
/// Concrete crawlers (`Crawler.AppleDocs`, `Crawler.HIG`, …) live in
/// the `Crawler` SPM target. The `Crawler.WebKit` sub-namespace
/// concretes (`Crawler.WebKit.ContentFetcher`, `Crawler.WebKit.Engine`,
/// `Crawler.WebKit.LiveHTTPFetcherFactory`) live in the `CrawlerWebKit`
/// sibling target post-#903. This file owns only the bare anchor + the
/// `WebKit` sub-anchor so protocols in CrawlerModels can extend
/// `Crawler.*` symbols cleanly without linking either producer.
public enum Crawler {
    /// Sub-namespace for WKWebView-based fetching (used by HIG + as
    /// fallback from AppleDocs). The concrete actors live in the
    /// `CrawlerWebKit` sibling target post-#903.
    public enum WebKit {}
}

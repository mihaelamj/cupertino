import Foundation

// MARK: - Crawler Namespace (foundation-only anchor)

/// Foundation-only namespace anchor for the `Crawler` SPM target. Lives
/// in `CrawlerModels` (this target) so consumers can extend `Crawler.*`
/// with protocols and value types without importing the concrete
/// `Crawler` target. The concrete `Crawler` target re-uses this same
/// namespace via `import CrawlerModels`.
///
/// Concrete crawlers (`Crawler.AppleDocs`, `Crawler.HIG`, …) and their
/// behavioural sub-namespaces (`Crawler.WebKit`) live in the
/// `Crawler` SPM target. This file owns only the bare anchor + the
/// `WebKit` sub-anchor so the protocols in CrawlerModels can extend
/// `Crawler.*` symbols cleanly.
public enum Crawler {
    /// Sub-namespace for WKWebView-based fetching (used by HIG + as
    /// fallback from AppleDocs). The concrete actors live in the
    /// `Crawler` target.
    public enum WebKit {}
}

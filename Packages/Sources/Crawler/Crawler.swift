import CoreProtocols
import Foundation

// MARK: - Crawler Namespace

/// `Crawler` is the SPM target that owns every web-crawling concern: fetching
/// pages from Apple's documentation servers, Swift Evolution, the HIG site,
/// and so on. Each concrete crawler lives under `Crawler.<Source>` with
/// nested companion types (`State`, `Progress`, `Statistics`, `Error`).
///
/// Concrete crawlers conform to `Core.Protocols.CrawlerEngine` so a higher-level
/// dispatcher can drive any of them through the same interface.
///
/// Layout:
/// - `Crawler.AppleDocs` — main developer.apple.com/documentation BFS crawler
///   (uses Apple's JSON API via `Core.JSONParser.Engine` + falls back to WKWebView
///   via `Crawler.WebKit.Engine`).
/// - `Crawler.AppleArchive` — developer.apple.com/library/archive crawler.
/// - `Crawler.HIG` — Human Interface Guidelines (JavaScript SPA, WebKit only).
/// - `Crawler.Evolution` — Swift Evolution proposals from GitHub.
/// - `Crawler.WebKit.{Engine, ContentFetcher}` — shared WKWebView-based fetcher.
/// - `Crawler.TechnologiesIndex` — Apple's framework index (technologies.json).
/// - `Crawler.AppleDocs.State` — resumable crawl state for AppleDocs.
/// - `Crawler.ArchiveGuideCatalog` — curated Apple Archive guides list.
public enum Crawler {
    /// Sub-namespace for WKWebView-based fetching (used by HIG + as fallback
    /// from AppleDocs).
    public enum WebKit {}
}

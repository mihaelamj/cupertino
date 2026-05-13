import CoreProtocols
import Foundation

// MARK: - Core.WKWebCrawler Namespace

extension Core {
    /// `Core.WKWebCrawler` provides WKWebView-based web page fetching capabilities
    /// for Apple documentation crawling. Mirrors the `Sources/Core/WKWebCrawler/`
    /// folder on disk and groups fetchers that handle JavaScript-rendered pages
    /// requiring a full browser engine.
    ///
    /// Note: WKWebView is macOS/iOS only. For Linux support, see alternative crawlers.
    ///
    /// Layout:
    /// - `Core.WKWebCrawler.ContentFetcher` — HTTP-level fetch via WKWebView.
    /// - `Core.WKWebCrawler.ContentFetcher.Error` (renamed from `WebKitFetcherError`).
    /// - `Core.WKWebCrawler.Engine` — full crawler engine wrapping ContentFetcher
    ///   + `Core.Parser.HTML` transformation.
    /// - `Core.WKWebCrawler.Engine.Error` (renamed from `WebKitCrawlerError`).
    public enum WKWebCrawler {
        /// Module version
        public static let version = "1.0.0"
    }
}

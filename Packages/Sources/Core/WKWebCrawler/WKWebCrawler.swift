import Foundation

// MARK: - WKWebCrawler Namespace

/// WKWebCrawler provides WKWebView-based web page fetching capabilities
/// for Apple documentation crawling. This namespace contains fetchers
/// that handle JavaScript-rendered pages requiring a full browser engine.
/// Note: WKWebView is macOS/iOS only. For Linux support, see alternative crawlers.
public enum WKWebCrawler {
    /// Module version
    public static let version = "1.0.0"
}

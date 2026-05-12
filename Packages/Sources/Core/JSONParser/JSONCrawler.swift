import Foundation

// MARK: - JSONCrawler Module

/// JSONCrawler provides JSON API-based content fetching for Apple documentation
/// This module fetches structured JSON data directly from Apple's API,
/// avoiding WKWebView memory issues while providing faster crawling.
public enum JSONCrawler {
    /// Module version
    public static let version = "1.0.0"
}

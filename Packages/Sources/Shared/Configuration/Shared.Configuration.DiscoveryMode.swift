import Foundation
import SharedConstants

// MARK: - Shared.Configuration.DiscoveryMode

extension Shared.Configuration {
    /// Selects how the crawler discovers child URLs.
    /// - `auto`: JSON API primary, fall back to WKWebView when JSON 404s. (default)
    /// - `jsonOnly`: JSON API only, no WKWebView fallback (fastest, narrowest).
    /// - `webViewOnly`: WKWebView for everything (matches pre-2025-11-30 behavior, broadest discovery).
    public enum DiscoveryMode: String, Codable, Sendable {
        case auto
        case jsonOnly = "json-only"
        case webViewOnly = "webview-only"
    }
}

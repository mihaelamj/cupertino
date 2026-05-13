import Foundation

// MARK: - Rejection Reason

extension Crawler.AppleDocs.State {
    public enum RejectionReason: String, Codable, Sendable {
        /// `Core.Parser.HTML.looksLikeHTTPErrorPage` tripped — Apple's CDN
        /// served a styled 403/404/502 page at HTTP 200.
        case httpErrorTemplate = "http_error_template"
        /// `Core.Parser.HTML.looksLikeJavaScriptFallback` tripped — Apple's
        /// React SPA rendered its "page can't be found" / "unknown error"
        /// sub-view at HTTP 200 (the internal doc-loader returned 404).
        case javaScriptFallback = "js_fallback"
    }
}

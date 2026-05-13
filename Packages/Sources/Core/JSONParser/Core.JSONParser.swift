import CoreProtocols
import Foundation

// MARK: - Core.JSONParser Namespace

extension Core {
    /// Sub-namespace for JSON-API-based content fetching, parsing, and reference
    /// resolution against Apple's documentation JSON endpoints. Mirrors the
    /// `Sources/Core/JSONParser/` folder on disk.
    ///
    /// Layout:
    /// - `Core.JSONParser.Engine` — top-level crawler engine driving the JSON pipeline.
    /// - `Core.JSONParser.ContentFetcher` — HTTP-level fetch with `Core.JSONParser.ContentFetcher.Error`.
    /// - `Core.JSONParser.AppleJSONToMarkdown` — converts Apple's DocC JSON to Markdown.
    /// - `Core.JSONParser.MarkdownToStructuredPage` — extracts structured page model from Markdown.
    /// - `Core.JSONParser.RefResolver` — resolves `doc://` references to canonical URLs / titles.
    /// - `Core.JSONParser.AppleJSONAPITitleFetcher`,
    ///   `Core.JSONParser.WKWebViewTitleFetcher`,
    ///   `Core.JSONParser.CompositeTitleFetcher` — title-fetch strategies for RefResolver.
    public enum JSONParser {
        /// Module version
        public static let version = "1.0.0"
    }
}

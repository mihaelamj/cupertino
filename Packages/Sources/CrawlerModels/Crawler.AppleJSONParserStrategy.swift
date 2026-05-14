import Foundation
import SharedConstants
import SharedModels

// MARK: - Crawler.AppleJSONParserStrategy

/// Pure Apple-JSON→markdown / Apple-JSON→structured-page transformer
/// used by the crawl pipeline when Apple serves a documentation page's
/// JSON API endpoint. GoF Strategy pattern.
///
/// The Crawler SPM target holds `any AppleJSONParserStrategy` rather
/// than reaching into the concrete `CoreJSONParser` target. The
/// composition root (the CLI binary) supplies a
/// `LiveAppleJSONParserStrategy` that wraps
/// `Core.JSONParser.AppleJSONToMarkdown.{convert,toStructuredPage,
/// jsonAPIURL,documentationURL,extractLinks}`.
///
/// Parallel to `Crawler.HTMLParserStrategy` — both abstract pure
/// stateless transformers behind one protocol per content shape.
public extension Crawler {
    protocol AppleJSONParserStrategy: Sendable {
        /// Convert the JSON API response body to a markdown
        /// approximation. Returns nil when the response can't be
        /// parsed as the expected Apple-documentation schema.
        func convert(json: Data, url: URL) -> String?

        /// Convert the JSON API response body to a structured
        /// documentation page. Returns nil when the schema doesn't
        /// match. `depth` is carried through for crawl-relative
        /// pagination.
        func toStructuredPage(
            json: Data,
            url: URL,
            depth: Int?
        ) -> Shared.Models.StructuredDocumentationPage?

        /// Map a `developer.apple.com/documentation/...` page URL to
        /// its corresponding JSON API endpoint. Returns nil when the
        /// URL doesn't match a supported documentation prefix.
        func jsonAPIURL(from documentationURL: URL) -> URL?

        /// Inverse of `jsonAPIURL(from:)` — recover the canonical
        /// page URL from a JSON API URL. The crawler uses this to
        /// build a stable cache key when the response came back via
        /// a redirect.
        func documentationURL(from jsonAPIURL: URL) -> URL?

        /// Extract every link referenced in the JSON response so the
        /// crawler can enqueue them. The implementation decides how
        /// to filter against the configured allow-list.
        func extractLinks(from json: Data) -> [URL]
    }
}

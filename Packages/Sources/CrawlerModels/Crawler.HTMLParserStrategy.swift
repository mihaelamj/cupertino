import Foundation
import SharedConstants
import SharedModels

// MARK: - Crawler.HTMLParserStrategy

/// Pure HTML→markdown / HTML→structured-page transformer used by the
/// crawl pipeline. GoF Strategy pattern (Gamma et al, 1994): one
/// algorithm in production (`Core.Parser.HTML` static methods), with
/// test stubs swapping in for unit coverage.
///
/// The Crawler SPM target holds `any HTMLParserStrategy` rather than
/// reaching into the concrete `Core` target. The composition root
/// (the CLI binary) supplies a `LiveHTMLParserStrategy` that wraps
/// `Core.Parser.HTML.{convert,toStructuredPage,looksLikeHTTPErrorPage,
/// looksLikeJavaScriptFallback}` field-for-field.
///
/// Parallel to `Search.MarkdownToStructuredPageStrategy` on the docs
/// side (#496) — both abstract pure stateless transformers.
public extension Crawler {
    protocol HTMLParserStrategy: Sendable {
        /// Convert raw HTML to a markdown approximation. The
        /// implementation decides how much of the page chrome is
        /// stripped; callers treat the output as opaque text.
        func convert(html: String, url: URL) -> String

        /// Convert raw HTML to a structured documentation page when
        /// the page has enough semantic markup; nil otherwise. The
        /// `source` parameter labels the resulting page so the
        /// downstream indexer can attribute it correctly. `depth`
        /// is carried through for crawl-relative pagination.
        func toStructuredPage(
            html: String,
            url: URL,
            source: Shared.Models.StructuredDocumentationPage.Source,
            depth: Int?
        ) -> Shared.Models.StructuredDocumentationPage?

        /// True when the HTML looks like an Apple HTTP error template
        /// (custom 404 / 403 / 502 layouts that share boilerplate
        /// chrome). Used by the crawler to skip non-content responses
        /// rather than indexing the error page itself (#284).
        func looksLikeHTTPErrorPage(html: String) -> Bool

        /// True when the HTML is the bare JavaScript shell Apple
        /// serves before the React app hydrates. Distinguishes
        /// fetcher-too-fast from a real empty page so the WebView
        /// fallback path can re-fetch.
        func looksLikeJavaScriptFallback(html: String) -> Bool
    }
}

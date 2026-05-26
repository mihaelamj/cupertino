import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
import CrawlerModels
import Foundation
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SearchAPI
import SearchModels
import SearchSQLite
import Services
import ServicesModels
import SharedConstants

// MARK: - Production Crawler.HTMLParserStrategy (#505)

// Concrete `Crawler.HTMLParserStrategy` (GoF Strategy) — wraps
// `Core.Parser.HTML` pure static methods. Crawler doesn't import
// `Core`; only this composition root does. Same shape as
// `LiveMarkdownToStructuredPageStrategy` (#496).

struct LiveHTMLParserStrategy: Crawler.HTMLParserStrategy {
    func convert(html: String, url: URL) -> String {
        Core.Parser.HTML.convert(html, url: url)
    }

    func toStructuredPage(
        html: String,
        url: URL,
        source: Shared.Models.StructuredDocumentationPage.Source,
        depth: Int?
    ) -> Shared.Models.StructuredDocumentationPage? {
        Core.Parser.HTML.toStructuredPage(html, url: url, source: source, depth: depth)
    }

    func looksLikeHTTPErrorPage(html: String) -> Bool {
        Core.Parser.HTML.looksLikeHTTPErrorPage(html: html)
    }

    func looksLikeJavaScriptFallback(html: String) -> Bool {
        Core.Parser.HTML.looksLikeJavaScriptFallback(html: html)
    }
}

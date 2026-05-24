import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
import Crawler
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

// MARK: - Production Crawler.AppleJSONParserStrategy (#505)

// Concrete `Crawler.AppleJSONParserStrategy` — wraps
// `Core.JSONParser.AppleJSONToMarkdown` pure static methods.

struct LiveAppleJSONParserStrategy: Crawler.AppleJSONParserStrategy {
    func convert(json: Data, url: URL) -> String? {
        Core.JSONParser.AppleJSONToMarkdown.convert(json, url: url)
    }

    func toStructuredPage(
        json: Data,
        url: URL,
        depth: Int?
    ) -> Shared.Models.StructuredDocumentationPage? {
        Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(json, url: url, depth: depth)
    }

    func jsonAPIURL(from documentationURL: URL) -> URL? {
        Core.JSONParser.AppleJSONToMarkdown.jsonAPIURL(from: documentationURL)
    }

    func documentationURL(from jsonAPIURL: URL) -> URL? {
        Core.JSONParser.AppleJSONToMarkdown.documentationURL(from: jsonAPIURL)
    }

    func extractLinks(from json: Data) -> [URL] {
        Core.JSONParser.AppleJSONToMarkdown.extractLinks(from: json)
    }
}

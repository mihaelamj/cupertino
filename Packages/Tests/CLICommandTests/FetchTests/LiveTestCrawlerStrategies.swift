@testable import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
import CrawlerModels
import Foundation
import SharedConstants
import SharedModels

// MARK: - Live test crawler strategies

// Real wrappers around `Core.Parser.HTML`, `Core.JSONParser.AppleJSONToMarkdown`,
// and `Core.PackageIndexing.PriorityPackageGenerator`. Integration tests
// that actually walk pages need real HTML / JSON parsing (the
// `Crawler.NoopHTMLParserStrategy` fixtures in CrawlerModels return
// empty content, which makes content-shape assertions fail).
//
// Each test target imports `Core` / `CoreJSONParser` /
// `CorePackageIndexing` because the test target IS a composition
// root for its own bundle. Production consumers (the `Crawler`
// target itself) still know none of these.

struct LiveTestHTMLParserStrategy: Crawler.HTMLParserStrategy {
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

struct LiveTestAppleJSONParserStrategy: Crawler.AppleJSONParserStrategy {
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

struct LiveTestPriorityPackageStrategy: Crawler.PriorityPackageStrategy {
    func generate(
        swiftOrgDocsPath: URL,
        outputPath: URL
    ) async throws -> Crawler.PriorityPackageOutcome {
        let generator = Core.PackageIndexing.PriorityPackageGenerator(
            swiftOrgDocsPath: swiftOrgDocsPath,
            outputPath: outputPath
        )
        let list = try await generator.generate()
        return Crawler.PriorityPackageOutcome(
            totalUniqueReposFound: list.stats.totalUniqueReposFound
        )
    }
}

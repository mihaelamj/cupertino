import Foundation
import SharedConstants
import SharedModels

// MARK: - No-op test fixtures

/// Inert implementations of the three Crawler strategies — return
/// the empty / nil case for every method. Tests that construct
/// `Crawler.AppleDocs` purely to exercise State / Statistics / queue
/// management (i.e. don't actually run a network crawl) use these so
/// the test target doesn't have to import the concrete `Core` /
/// `CoreJSONParser` / `CorePackageIndexing` producers.
///
/// Integration tests that DO walk pages and need real markdown
/// conversion live in test composition roots (the test target IS the
/// composition root for its own bundle), where they wire concrete
/// strategies wrapping `Core.Parser.HTML` / `Core.JSONParser.AppleJSONToMarkdown`
/// / `Core.PackageIndexing.PriorityPackageGenerator` field-for-field.
public extension Crawler {
    struct NoopHTMLParserStrategy: HTMLParserStrategy {
        public init() {}

        public func convert(html: String, url: URL) -> String {
            ""
        }

        public func toStructuredPage(
            html: String,
            url: URL,
            source: Shared.Models.StructuredDocumentationPage.Source,
            depth: Int?
        ) -> Shared.Models.StructuredDocumentationPage? {
            nil
        }

        public func looksLikeHTTPErrorPage(html: String) -> Bool {
            false
        }

        public func looksLikeJavaScriptFallback(html: String) -> Bool {
            false
        }
    }

    struct NoopAppleJSONParserStrategy: AppleJSONParserStrategy {
        public init() {}

        public func convert(json: Data, url: URL) -> String? {
            nil
        }

        public func toStructuredPage(
            json: Data,
            url: URL,
            depth: Int?
        ) -> Shared.Models.StructuredDocumentationPage? {
            nil
        }

        public func jsonAPIURL(from documentationURL: URL) -> URL? {
            nil
        }

        public func documentationURL(from jsonAPIURL: URL) -> URL? {
            nil
        }

        public func extractLinks(from json: Data) -> [URL] {
            []
        }
    }

    struct NoopPriorityPackageStrategy: PriorityPackageStrategy {
        public init() {}

        public func generate(
            swiftOrgDocsPath: URL,
            outputPath: URL
        ) async throws -> PriorityPackageOutcome {
            PriorityPackageOutcome(totalUniqueReposFound: 0)
        }
    }
}

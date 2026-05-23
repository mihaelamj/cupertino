import CoreProtocols
import Foundation
import SharedConstants

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

    /// Inert `HTTPFetcherFactory` (#903) — every call to `makeFetcher`
    /// returns the same no-op `StringContentFetcher` that throws
    /// `NotImplementedError` on `.fetch(url:)`. Used by tests that
    /// construct `Crawler.AppleDocs` / `Crawler.HIG` for state /
    /// statistics coverage without actually walking the network.
    /// Integration tests that need real fetches inject
    /// `Crawler.WebKit.LiveHTTPFetcherFactory()` directly.
    @MainActor
    struct NoopHTTPFetcherFactory: HTTPFetcherFactory {
        public init() {}

        public func makeFetcher(
            pageLoadTimeout _: Duration,
            javascriptWaitTime _: Duration
        ) -> any Core.Protocols.StringContentFetcher {
            NoopStringContentFetcher()
        }
    }

    struct NoopStringContentFetcher: Core.Protocols.StringContentFetcher {
        public init() {}

        public func fetch(url: URL) async throws -> Core.Protocols.FetchResult<String> {
            throw NoopFetcherError.notImplemented(url)
        }
    }

    enum NoopFetcherError: Swift.Error {
        case notImplemented(URL)
    }
}

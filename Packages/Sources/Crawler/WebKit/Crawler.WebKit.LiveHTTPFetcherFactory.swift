import CoreProtocols
import CrawlerModels
import Foundation
import SharedConstants

// MARK: - Crawler.WebKit.LiveHTTPFetcherFactory

/// Production conformer for `Crawler.HTTPFetcherFactory`. Constructs
/// `Crawler.WebKit.ContentFetcher` instances backed by `WKWebView`.
///
/// Lives in `CrawlerWebKit` (#903) because the produced concretes
/// import WebKit and the Crawler producer is foundation-only.
/// The composition root (`CLI`) instantiates this factory and passes
/// it to `Crawler.HIG` / `Crawler.AppleDocs` via init injection.
public extension Crawler.WebKit {
    @MainActor
    struct LiveHTTPFetcherFactory: Crawler.HTTPFetcherFactory {
        public init() {}

        public func makeFetcher(
            pageLoadTimeout: Duration,
            javascriptWaitTime: Duration
        ) -> any Core.Protocols.StringContentFetcher {
            Crawler.WebKit.ContentFetcher(
                pageLoadTimeout: pageLoadTimeout,
                javascriptWaitTime: javascriptWaitTime
            )
        }
    }
}

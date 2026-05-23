import CoreProtocols
import Foundation

// MARK: - Crawler.HTTPFetcherFactory

/// Strategy seam (GoF 1994 p. 315) for producing `Core.Protocols.ContentFetcher`
/// instances of the WebKit-or-equivalent variety the `Crawler` producer needs.
///
/// The Crawler target conforms to the strict foundation-only allow-list
/// (#536 / #893): it links Foundation + `*Models` seams + CoreProtocols +
/// SharedConstants + LoggingModels and nothing else. WebKit lives in the
/// `CrawlerWebKit` sibling target (#903). The factory is the seam by which
/// the WebKit-backed concrete reaches the Crawler producer without the
/// Crawler producer linking WebKit.
///
/// Implementations:
/// - `Crawler.WebKit.LiveHTTPFetcherFactory` (in `CrawlerWebKit`) wraps
///   `WKWebView` for production crawls.
/// - Tests inject a stub conformer that returns an in-memory fetcher
///   (`Crawler.NoopHTTPFetcherFactory` throws on `.fetch`;
///   `Crawler.CannedHTMLFetcherFactory` returns canned HTML).
///
/// Each call to `makeFetcher` produces a fresh instance. `Crawler.HIG`
/// and `Crawler.AppleDocs` recycle their fetchers on a memory-pressure
/// interval, so the factory must produce distinct objects, not return
/// a cached shared instance.
public extension Crawler {
    @MainActor
    protocol HTTPFetcherFactory: Sendable {
        /// Produce a fresh `ContentFetcher<String>` configured with the
        /// supplied page-load + javascript-wait timeouts. The crawler
        /// producer holds the factory at construction time and calls this
        /// method during `crawl()` to obtain a per-crawl fetcher
        /// instance.
        ///
        /// - Parameters:
        ///   - pageLoadTimeout: Maximum wall-clock seconds to wait for a
        ///     page's load event before treating the fetch as failed.
        ///   - javascriptWaitTime: Additional seconds to wait after the
        ///     load event for any JavaScript-driven content to settle.
        ///     Apple's HIG SPA needs this; the docs site doesn't.
        /// - Returns: A fresh `StringContentFetcher` instance.
        func makeFetcher(
            pageLoadTimeout: Duration,
            javascriptWaitTime: Duration
        ) -> any Core.Protocols.StringContentFetcher
    }
}

import Foundation
import SearchModels

// MARK: - LiveWebCrawlStrategyFactory

/// Production `Search.WebCrawlStrategyFactory`. Lives in the `Crawler`
/// producer next to the `WebCrawlFetchStrategy` it builds. The
/// composition root instantiates it and injects it into the three
/// web-crawl source providers (apple-docs, swift-org, swift-book), which
/// depend only on the `Search.WebCrawlStrategyFactory` seam (#536 lift 4).
public struct LiveWebCrawlStrategyFactory: Search.WebCrawlStrategyFactory {
    public init() {}

    public func makeStrategy(
        defaultCrawlBaseURL: String,
        defaultAllowedPrefixes: [String]?,
        candidateSessionDirectories: [URL]
    ) -> any Search.SourceFetchStrategy {
        WebCrawlFetchStrategy(
            defaultCrawlBaseURL: defaultCrawlBaseURL,
            defaultAllowedPrefixes: defaultAllowedPrefixes,
            candidateSessionDirectories: candidateSessionDirectories
        )
    }
}

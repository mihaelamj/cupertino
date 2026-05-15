import Foundation
import SharedConstants

// MARK: - Crawler.AppleDocsProgress + ProgressObserving
//
// Naming note: the producer-target class `Crawler.AppleDocs` is a
// `public final class` declared in the `Crawler` SPM target's
// `Crawler.AppleDocs.swift`. To keep its progress payload + Observer
// protocol in this foundation-only seam target (so any conformer can
// implement without `import Crawler`), the seam types use flat names
// under `Crawler` (`Crawler.AppleDocsProgress`,
// `Crawler.AppleDocsProgressObserving`) rather than nested under the
// class. Same pattern used for the other three crawlers.

extension Crawler {
    /// Progress information emitted during an Apple-docs crawl run.
    /// Lives in `CrawlerModels` so any conformer of
    /// `Crawler.AppleDocsProgressObserving` can receive it without
    /// depending on the concrete `Crawler` producer target. Strict GoF
    /// Observer (1994 p. 293): the abstraction is reachable without the
    /// subject.
    public struct AppleDocsProgress: Sendable {
        public let currentURL: URL
        public let visitedCount: Int
        public let totalPages: Int
        public let stats: Shared.Models.CrawlStatistics

        public var percentage: Double {
            Double(visitedCount) / Double(totalPages) * 100
        }

        public init(
            currentURL: URL,
            visitedCount: Int,
            totalPages: Int,
            stats: Shared.Models.CrawlStatistics
        ) {
            self.currentURL = currentURL
            self.visitedCount = visitedCount
            self.totalPages = totalPages
            self.stats = stats
        }
    }

    /// GoF Observer (1994 p. 293) for Apple-docs crawl progress.
    /// Replaces the previous inline
    /// `onProgress: (@Sendable (Progress) -> Void)?` closure parameter
    /// on `Crawler.AppleDocs.crawl`. Per the standing cupertino rule
    /// "no closures, they ate magic."
    public protocol AppleDocsProgressObserving: Sendable {
        /// Called periodically as the crawl visits each URL.
        /// Implementations should be non-blocking; the crawler waits
        /// for return before continuing.
        func observe(progress: Crawler.AppleDocsProgress)
    }
}

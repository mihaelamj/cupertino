import Foundation
import SharedConstants

// MARK: - Crawler.HIG{Statistics,Progress,ProgressObserving}

extension Crawler {
    /// Statistics produced by a HIG crawl run.
    public struct HIGStatistics: Sendable {
        public var totalPages: Int = 0
        public var newPages: Int = 0
        public var updatedPages: Int = 0
        public var skippedPages: Int = 0
        public var errors: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public init(
            totalPages: Int = 0,
            newPages: Int = 0,
            updatedPages: Int = 0,
            skippedPages: Int = 0,
            errors: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalPages = totalPages
            self.newPages = newPages
            self.updatedPages = updatedPages
            self.skippedPages = skippedPages
            self.errors = errors
            self.startTime = startTime
            self.endTime = endTime
        }

        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else {
                return nil
            }
            return end.timeIntervalSince(start)
        }
    }

    /// Progress information emitted during a HIG crawl.
    public struct HIGProgress: Sendable {
        public let currentPage: Int
        public let totalPages: Int
        public let currentItem: String
        public let stats: HIGStatistics

        public var percentage: Double {
            guard totalPages > 0 else { return 0 }
            return Double(currentPage) / Double(totalPages) * 100
        }

        public init(
            currentPage: Int,
            totalPages: Int,
            currentItem: String,
            stats: HIGStatistics
        ) {
            self.currentPage = currentPage
            self.totalPages = totalPages
            self.currentItem = currentItem
            self.stats = stats
        }
    }

    /// GoF Observer (1994 p. 293) for HIG crawl progress. Replaces the
    /// inline closure parameter previously taken by `Crawler.HIG.crawl`.
    public protocol HIGProgressObserving: Sendable {
        func observe(progress: Crawler.HIGProgress)
    }
}

import Foundation
import SharedConstants

// MARK: - Crawler.AppleArchive{Statistics,Progress,ProgressObserving}

extension Crawler {
    /// Statistics produced by an Apple Archive crawl run. Moved from
    /// the `Crawler` producer target (was `Crawler.AppleArchive.Statistics`)
    /// so the foundation-only seam owns the shape that callers consume.
    public struct AppleArchiveStatistics: Sendable {
        public var totalGuides: Int = 0
        public var totalPages: Int = 0
        public var newPages: Int = 0
        public var updatedPages: Int = 0
        public var skippedPages: Int = 0
        public var errors: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public init(
            totalGuides: Int = 0,
            totalPages: Int = 0,
            newPages: Int = 0,
            updatedPages: Int = 0,
            skippedPages: Int = 0,
            errors: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalGuides = totalGuides
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

    /// Progress information emitted during an Apple Archive crawl run.
    public struct AppleArchiveProgress: Sendable {
        public let currentGuide: Int
        public let totalGuides: Int
        public let currentPage: Int
        public let totalPages: Int
        public let guideName: String
        public let pageName: String
        public let stats: AppleArchiveStatistics

        public var percentage: Double {
            let guideProgress = Double(currentGuide - 1) / Double(totalGuides)
            let pageProgress = Double(currentPage) / Double(max(totalPages, 1)) / Double(totalGuides)
            return (guideProgress + pageProgress) * 100
        }

        public var currentItem: String {
            "\(guideName) - \(pageName)"
        }

        public init(
            currentGuide: Int,
            totalGuides: Int,
            currentPage: Int,
            totalPages: Int,
            guideName: String,
            pageName: String,
            stats: AppleArchiveStatistics
        ) {
            self.currentGuide = currentGuide
            self.totalGuides = totalGuides
            self.currentPage = currentPage
            self.totalPages = totalPages
            self.guideName = guideName
            self.pageName = pageName
            self.stats = stats
        }
    }

    /// GoF Observer (1994 p. 293) for Apple Archive crawl progress.
    /// Replaces the inline closure parameter previously taken by
    /// `Crawler.AppleArchive.crawl`.
    public protocol AppleArchiveProgressObserving: Sendable {
        func observe(progress: Crawler.AppleArchiveProgress)
    }
}

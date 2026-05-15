import CoreProtocols
import Foundation
import SharedConstants

// MARK: - Core.PackageIndexing.PackageFetcher{Statistics,Progress,ProgressObserving}
//
// Naming note: the producer-target `Core.PackageIndexing.PackageFetcher`
// is a `public actor` declared in the `CorePackageIndexing` SPM target.
// To keep its progress payload + Observer protocol in this foundation-
// only seam target (so any conformer can implement without
// `import CorePackageIndexing`), the seam types use flat names under
// `Core.PackageIndexing` (`PackageFetcherProgress`,
// `PackageFetcherStatistics`, `PackageFetcherProgressObserving`) rather
// than nested under the actor. Same pattern used by the 4 crawler seams
// in `CrawlerModels` and the 3 Indexer services in `IndexerModels`.

extension Core.PackageIndexing {
    /// Statistics produced by a `PackageFetcher.fetch(progress:)` run.
    /// Lives in the foundation-only seam target so any conformer of
    /// `PackageFetcherProgressObserving` can receive them without
    /// depending on the concrete producer target.
    public struct PackageFetcherStatistics: Sendable {
        public var totalPackages: Int = 0
        public var successfulFetches: Int = 0
        public var errors: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else { return nil }
            return end.timeIntervalSince(start)
        }

        public init(
            totalPackages: Int = 0,
            successfulFetches: Int = 0,
            errors: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalPackages = totalPackages
            self.successfulFetches = successfulFetches
            self.errors = errors
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    /// Progress information emitted periodically during a
    /// `PackageFetcher.fetch(progress:)` run.
    public struct PackageFetcherProgress: Sendable {
        public let current: Int
        public let total: Int
        public let packageName: String
        public let stats: PackageFetcherStatistics

        public var percentage: Double {
            Double(current) / Double(total) * 100
        }

        public init(
            current: Int,
            total: Int,
            packageName: String,
            stats: PackageFetcherStatistics
        ) {
            self.current = current
            self.total = total
            self.packageName = packageName
            self.stats = stats
        }
    }

    /// GoF Observer (1994 p. 293) for `PackageFetcher` progress. Replaces
    /// the inline `onProgress: (@Sendable (Progress) -> Void)?` closure
    /// parameter previously taken by `PackageFetcher.fetch`. Per the
    /// standing cupertino rule "no closures, they ate magic."
    public protocol PackageFetcherProgressObserving: Sendable {
        /// Called periodically as each package is processed.
        /// Implementations should be non-blocking; the fetcher waits
        /// for return before continuing.
        func observe(progress: Core.PackageIndexing.PackageFetcherProgress)
    }
}

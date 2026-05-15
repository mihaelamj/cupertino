import Foundation
import SharedConstants

// MARK: - Crawler.Evolution{Statistics,Progress,ProgressObserving}

extension Crawler {
    /// Statistics produced by a Swift Evolution crawl run.
    public struct EvolutionStatistics: Sendable {
        public var totalProposals: Int = 0
        public var newProposals: Int = 0
        public var updatedProposals: Int = 0
        public var errors: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public init(
            totalProposals: Int = 0,
            newProposals: Int = 0,
            updatedProposals: Int = 0,
            errors: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalProposals = totalProposals
            self.newProposals = newProposals
            self.updatedProposals = updatedProposals
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

    /// Progress information emitted during a Swift Evolution crawl.
    public struct EvolutionProgress: Sendable {
        public let current: Int
        public let total: Int
        public let proposalID: String
        public let stats: EvolutionStatistics

        public var percentage: Double {
            Double(current) / Double(total) * 100
        }

        public init(
            current: Int,
            total: Int,
            proposalID: String,
            stats: EvolutionStatistics
        ) {
            self.current = current
            self.total = total
            self.proposalID = proposalID
            self.stats = stats
        }
    }

    /// GoF Observer (1994 p. 293) for Swift Evolution crawl progress.
    /// Replaces the inline closure parameter previously taken by
    /// `Crawler.Evolution.crawl`.
    public protocol EvolutionProgressObserving: Sendable {
        func observe(progress: Crawler.EvolutionProgress)
    }
}

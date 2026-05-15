import Foundation
import SharedConstants

// MARK: - Sample Core Progress

extension Sample.Core {
    public struct Progress: Sendable {
        public let current: Int
        public let total: Int
        public let sampleName: String
        public let stats: Sample.Core.Statistics

        /// Explicit public init: when this type lived inside the
        /// `CoreSampleCode` producer, Swift's synthesised memberwise
        /// init defaulted to internal and was fine for in-module use.
        /// Post-move to `CoreSampleCodeModels`, the producer is a
        /// separate module and needs the explicit public init to
        /// construct progress payloads.
        public init(current: Int, total: Int, sampleName: String, stats: Sample.Core.Statistics) {
            self.current = current
            self.total = total
            self.sampleName = sampleName
            self.stats = stats
        }

        public var percentage: Double {
            Double(current) / Double(total) * 100
        }
    }
}

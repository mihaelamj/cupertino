import Foundation
import SharedConstants

// MARK: - Sample Core Progress

extension Sample.Core {
    public struct Progress: Sendable {
        public let current: Int
        public let total: Int
        public let sampleName: String
        public let stats: Sample.Core.Statistics

        public var percentage: Double {
            Double(current) / Double(total) * 100
        }
    }
}

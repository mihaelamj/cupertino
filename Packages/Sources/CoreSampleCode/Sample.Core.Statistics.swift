import Foundation
import SharedConstants

// MARK: - Sample Core Statistics

extension Sample.Core {
    public struct Statistics: Sendable {
        public var totalSamples: Int = 0
        public var downloadedSamples: Int = 0
        public var skippedSamples: Int = 0
        public var errors: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public init(
            totalSamples: Int = 0,
            downloadedSamples: Int = 0,
            skippedSamples: Int = 0,
            errors: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalSamples = totalSamples
            self.downloadedSamples = downloadedSamples
            self.skippedSamples = skippedSamples
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
}

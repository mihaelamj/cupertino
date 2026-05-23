import Foundation

// MARK: - Availability Fetch Statistics

extension Availability {
    /// Statistics for availability fetch operation
    public struct Statistics: Sendable {
        /// Total documents scanned
        public var totalDocuments: Int = 0

        /// Documents that had availability updated
        public var updatedDocuments: Int = 0

        /// Documents where availability fetch was successful
        public var successfulFetches: Int = 0

        /// Documents where availability fetch failed (timeouts, 404s, etc.)
        public var failedFetches: Int = 0

        /// Documents skipped (already have availability or not applicable)
        public var skippedDocuments: Int = 0

        /// Documents that inherited availability from parent/framework
        public var inheritedFromParent: Int = 0

        /// Articles that derived availability from referenced APIs
        public var derivedFromReferences: Int = 0

        /// Documents marked with empty availability (checked but none found)
        public var markedEmpty: Int = 0

        /// Number of frameworks processed
        public var frameworksProcessed: Int = 0

        /// Files that had no availability after all fallbacks (for logging)
        public var filesWithNoAvailability: [String] = []

        /// Start time of the operation
        public var startTime: Date?

        /// End time of the operation
        public var endTime: Date?

        public init(
            totalDocuments: Int = 0,
            updatedDocuments: Int = 0,
            successfulFetches: Int = 0,
            failedFetches: Int = 0,
            skippedDocuments: Int = 0,
            inheritedFromParent: Int = 0,
            derivedFromReferences: Int = 0,
            markedEmpty: Int = 0,
            frameworksProcessed: Int = 0,
            filesWithNoAvailability: [String] = [],
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalDocuments = totalDocuments
            self.updatedDocuments = updatedDocuments
            self.successfulFetches = successfulFetches
            self.failedFetches = failedFetches
            self.skippedDocuments = skippedDocuments
            self.inheritedFromParent = inheritedFromParent
            self.derivedFromReferences = derivedFromReferences
            self.markedEmpty = markedEmpty
            self.frameworksProcessed = frameworksProcessed
            self.filesWithNoAvailability = filesWithNoAvailability
            self.startTime = startTime
            self.endTime = endTime
        }

        /// Duration of the operation in seconds
        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else {
                return nil
            }
            return end.timeIntervalSince(start)
        }

        /// Success rate as percentage
        public var successRate: Double {
            let attempted = successfulFetches + failedFetches
            guard attempted > 0 else { return 0 }
            return (Double(successfulFetches) / Double(attempted)) * 100.0
        }
    }
}

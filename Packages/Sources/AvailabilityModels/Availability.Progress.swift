import Foundation

// MARK: - Availability Fetch Progress

extension Availability {
    /// Progress information for availability fetching
    public struct Progress: Sendable {
        /// Current document being processed
        public let currentDocument: String

        /// Number of documents processed
        public let completed: Int

        /// Total documents to process
        public let total: Int

        /// Number of successful fetches
        public let successful: Int

        /// Number of failed fetches
        public let failed: Int

        /// Current framework being processed
        public let currentFramework: String

        public init(
            currentDocument: String,
            completed: Int,
            total: Int,
            successful: Int,
            failed: Int,
            currentFramework: String
        ) {
            self.currentDocument = currentDocument
            self.completed = completed
            self.total = total
            self.successful = successful
            self.failed = failed
            self.currentFramework = currentFramework
        }

        /// Progress percentage (0-100)
        public var percentage: Double {
            guard total > 0 else { return 0 }
            return (Double(completed) / Double(total)) * 100.0
        }
    }
}

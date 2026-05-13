import Foundation

// MARK: - Indexer Index Result

extension RemoteSync.Indexer {
    /// Index result for a single document
    public struct IndexResult: Sendable {
        public let uri: String
        public let title: String
        public let success: Bool
        public let error: String?

        public init(uri: String, title: String, success: Bool, error: String? = nil) {
            self.uri = uri
            self.title = title
            self.success = success
            self.error = error
        }
    }
}

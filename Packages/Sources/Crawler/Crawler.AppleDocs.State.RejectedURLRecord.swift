import Foundation

// MARK: - Rejected URL Record

extension Crawler.AppleDocs.State {
    /// One row of the rejected-URLs log. Append-only JSONL so an interrupted
    /// crawl preserves every prior write.
    public struct RejectedURLRecord: Codable, Sendable {
        public let url: String
        public let framework: String
        public let reason: RejectionReason
        public let timestamp: Date
    }
}

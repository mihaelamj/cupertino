import Foundation
import SearchModels
import SharedConstants

// MARK: - HIG Indexer

/// Indexer for Human Interface Guidelines. HIG content is pure design
/// guidance with no code blocks, so `extractCode(from:)` always
/// returns `Search.ExtractedContent.empty`.
extension Search {
    public struct HIGIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.hig
        public let displayName = "Human Interface Guidelines"

        public init() {}

        public func extractCode(from _: Search.SourceItem) -> Search.ExtractedContent {
            // HIG has no code; pure design guidance.
            .empty
        }
    }
}

import Foundation
import SearchModels
import SharedConstants

// MARK: - Swift.org Indexer

/// Indexer for Swift.org content. No `extractCode` override; relies
/// on the default `Search.SourceIndexer.extractCode` (returns
/// `Search.ExtractedContent.empty`) because Swift.org pages are
/// mostly prose; the structured-page pipeline at the strategy layer
/// handles the markdown-to-structured-page conversion.
extension Search {
    public struct SwiftOrgIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.swiftOrg
        public let displayName = "Swift.org"

        public init() {}
    }
}

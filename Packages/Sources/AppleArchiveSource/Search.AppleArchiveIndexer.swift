import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Apple Archive Indexer

/// Indexer for Apple Archive (legacy documentation). Mixed Swift +
/// Objective-C content; `extractCode(from:)` guards a SwiftSyntax
/// parse on a heuristic check for Swift-shaped tokens to avoid
/// running the extractor over pure Obj-C content (which would fail
/// to parse without surfacing useful symbols).
extension Search {
    public struct AppleArchiveIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.appleArchive
        public let displayName = "Apple Archive"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Archive may have Objective-C code which SwiftSyntax can't parse.
            // Only extract if content looks like Swift.
            guard item.content.contains("func ") ||
                item.content.contains("struct ") ||
                item.content.contains("class ") ||
                item.content.contains("import ")
            else {
                return .empty
            }

            let extractor = ASTIndexer.Extractor()
            let result = extractor.extract(from: item.content)

            return Search.ExtractedContent(
                symbols: result.symbols,
                imports: result.imports,
                hasErrors: result.hasErrors
            )
        }
    }
}

import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Sample Code Indexer

/// Indexer for Apple Sample Code projects. Renamed from `Sample.Indexer`
/// to `Search.SampleCodeIndexer` by #898F so the type lives under the
/// same `Search` namespace as its sibling indexer concretes. Sample
/// code is full Swift files; `extractCode(from:)` runs
/// `ASTIndexer.Extractor` over the source to capture symbols and
/// imports.
extension Search {
    public struct SampleCodeIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.samples
        public let displayName = "Sample Code"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Sample code is full Swift files; extract everything.
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

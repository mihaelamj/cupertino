import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Swift Evolution Indexer

/// Indexer for Swift Evolution proposals. Pulls fenced Swift code
/// blocks out of the proposal markdown via the private
/// `extractAllCodeBlocks` helper, then runs `ASTIndexer.Extractor`
/// over the concatenation to capture symbols + imports.
extension Search {
    public struct SwiftEvolutionIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.swiftEvolution
        public let displayName = "Swift Evolution"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Swift Evolution proposals have lots of code examples.
            let extractor = ASTIndexer.Extractor()

            // Extract all code blocks from the proposal markdown.
            let codeBlocks = extractAllCodeBlocks(from: item.content)
            if codeBlocks.isEmpty {
                return .empty
            }

            let combinedCode = codeBlocks.joined(separator: "\n\n")
            let result = extractor.extract(from: combinedCode)

            return Search.ExtractedContent(
                symbols: result.symbols,
                imports: result.imports,
                hasErrors: result.hasErrors
            )
        }

        private func extractAllCodeBlocks(from content: String) -> [String] {
            var blocks: [String] = []
            let lines = content.components(separatedBy: .newlines)
            var inCodeBlock = false
            var currentBlock: [String] = []

            for line in lines {
                if line.hasPrefix("```"), !inCodeBlock {
                    inCodeBlock = true
                    currentBlock = []
                } else if line.hasPrefix("```"), inCodeBlock {
                    if !currentBlock.isEmpty {
                        blocks.append(currentBlock.joined(separator: "\n"))
                    }
                    inCodeBlock = false
                    currentBlock = []
                } else if inCodeBlock {
                    currentBlock.append(line)
                }
            }

            return blocks
        }
    }
}

import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Swift Book Indexer

/// Indexer for The Swift Programming Language book. Pulls fenced
/// code blocks out of the chapter markdown via the private
/// `extractCodeBlocks` helper and runs `ASTIndexer.Extractor` over
/// them to capture symbols + imports.
extension Search {
    public struct SwiftBookIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.swiftBook
        public let displayName = "The Swift Programming Language"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Swift book has extensive code examples.
            let extractor = ASTIndexer.Extractor()

            // Extract code blocks from markdown.
            let codeBlocks = extractCodeBlocks(from: item.content)
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

        private func extractCodeBlocks(from content: String) -> [String] {
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

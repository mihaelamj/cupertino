import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Apple Docs Indexer

/// Indexer for Apple Developer Documentation
extension Search {
    public struct AppleDocsIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.appleDocs
        public let displayName = "Apple Documentation"

        public init() {}

        public func validate(_ item: Search.SourceItem) -> Bool {
            // Apple docs must have a non-empty framework
            !item.uri.isEmpty &&
                !item.title.isEmpty &&
                item.framework?.isEmpty == false
        }

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Apple docs have declaration code in specific patterns
            // Extract from code blocks and declaration sections
            let extractor = ASTIndexer.Extractor()

            // Try to extract from the content directly
            let result = extractor.extract(from: item.content)

            // If no symbols found, content might be markdown with code blocks
            if result.symbols.isEmpty {
                // Extract code blocks from markdown
                let codeBlocks = extractCodeBlocks(from: item.content)
                if !codeBlocks.isEmpty {
                    let combinedCode = codeBlocks.joined(separator: "\n\n")
                    let blockResult = extractor.extract(from: combinedCode)
                    return Search.ExtractedContent(
                        symbols: blockResult.symbols,
                        imports: blockResult.imports,
                        hasErrors: blockResult.hasErrors
                    )
                }
            }

            return Search.ExtractedContent(
                symbols: result.symbols,
                imports: result.imports,
                hasErrors: result.hasErrors
            )
        }

        /// Extract Swift code blocks from markdown content
        private func extractCodeBlocks(from content: String) -> [String] {
            var blocks: [String] = []
            let lines = content.components(separatedBy: .newlines)
            var inCodeBlock = false
            var currentBlock: [String] = []
            var isSwiftBlock = false

            for line in lines {
                if line.hasPrefix("```swift") || line.hasPrefix("```Swift") {
                    inCodeBlock = true
                    isSwiftBlock = true
                    currentBlock = []
                } else if line.hasPrefix("```"), inCodeBlock {
                    if isSwiftBlock, !currentBlock.isEmpty {
                        blocks.append(currentBlock.joined(separator: "\n"))
                    }
                    inCodeBlock = false
                    isSwiftBlock = false
                    currentBlock = []
                } else if inCodeBlock {
                    currentBlock.append(line)
                }
            }

            return blocks
        }
    }
}

// MARK: - HIG Indexer

/// Indexer for Human Interface Guidelines

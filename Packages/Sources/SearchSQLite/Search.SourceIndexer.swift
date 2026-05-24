import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Swift Book Indexer

/// Indexer for The Swift Programming Language book
extension Search {
    public struct SwiftBookIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.swiftBook
        public let displayName = "The Swift Programming Language"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Swift book has extensive code examples
            let extractor = ASTIndexer.Extractor()

            // Extract code blocks from markdown
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

// MARK: - Swift.org Indexer

/// Indexer for Swift.org content
extension Search {
    public struct SwiftOrgIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.swiftOrg
        public let displayName = "Swift.org"

        public init() {}
    }
}

// MARK: - Packages Indexer

// #789: PackagesIndexer removed along with the search.db `packages`
// table. Package indexing lives in packages.db via the dedicated
// `Indexer.PackagesService` (`cupertino save --packages`); the
// in-search.db indexer was a shallow shadow that fed the now-dropped
// `packages` table.

// #932: the static `Search.IndexerRegistry` enum that lived here was
// dissolved. The 7 production indexer concretes are assembled inline
// at the composition root in `CLIImpl.Command.Save.Indexers.swift`,
// not via a named helper on the `Search` namespace. Naming a helper
// here would reintroduce a Service Locator surface (gof-di-rules.md
// Rule 1): the composition root is the only place that should hold
// the production list. Tests that need a fake-indexer dict construct
// their own literal.

import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

extension Search {
    public struct HIGIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.hig
        public let displayName = "Human Interface Guidelines"

        public init() {}

        public func extractCode(from _: Search.SourceItem) -> Search.ExtractedContent {
            // HIG has no code - pure design guidance
            .empty
        }
    }
}

// MARK: - Swift Evolution Indexer

/// Indexer for Swift Evolution proposals
extension Search {
    public struct SwiftEvolutionIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.swiftEvolution
        public let displayName = "Swift Evolution"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Swift Evolution proposals have lots of code examples
            let extractor = ASTIndexer.Extractor()

            // Extract all code blocks from the proposal markdown
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

// MARK: - Sample Code Indexer

/// Indexer for Apple Sample Code projects. Renamed from `Sample.Indexer`
/// to `Search.SampleCodeIndexer` by #898F so the type lives under the
/// same `Search` namespace as its 7 sibling indexer concretes
/// (AppleDocsIndexer, HIGIndexer, etc.); the previous `extension Sample`
/// nesting made `Search.SourceIndexer` references resolve to
/// `Sample.Search.SourceIndexer` once the file moved out of the Search
/// target.
extension Search {
    public struct SampleCodeIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.samples
        public let displayName = "Sample Code"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Sample code is full Swift files - extract everything
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

// MARK: - Archive Indexer

/// Indexer for Apple Archive (legacy documentation)
extension Search {
    public struct AppleArchiveIndexer: Search.SourceIndexer {
        public let sourceID = Shared.Constants.SourcePrefix.appleArchive
        public let displayName = "Apple Archive"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Archive may have Objective-C code which we can't parse with SwiftSyntax
            // Only extract if content looks like Swift
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

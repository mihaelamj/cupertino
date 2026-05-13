import ASTIndexer
import Foundation
import SharedConstants
import SharedCore

// MARK: - Source Item

/// Unified container for content to be indexed from any source.
/// This decouples source-specific crawling from generic indexing logic.
extension Search {
    public struct SourceItem: Sendable {
        // MARK: Required Fields

        /// Unique identifier URI (e.g., "apple-docs://swiftui/documentation_swiftui_view")
        public let uri: String

        /// Source identifier (e.g., "apple-docs", "wwdc-transcripts", "swift-forums")
        public let source: String

        /// Document title
        public let title: String

        /// Full content (markdown or plain text)
        public let content: String

        /// Path to local file (for caching/debugging)
        public let filePath: String

        /// Hash of content for change detection
        public let contentHash: String

        /// When this item was crawled/fetched
        public let lastCrawled: Date

        // MARK: Optional Fields

        /// Framework this belongs to (e.g., "swiftui", "foundation")
        public let framework: String?

        /// Programming language ("swift", "objc")
        public let language: String?

        /// Source type for categorization
        public let sourceType: String

        /// Associated package ID (for package docs)
        public let packageId: Int?

        /// Raw JSON data (for rich content preservation)
        public let jsonData: String?

        // MARK: Availability

        /// Minimum iOS version (e.g., "13.0")
        public let minIOS: String?

        /// Minimum macOS version (e.g., "10.15")
        public let minMacOS: String?

        /// Minimum tvOS version
        public let minTvOS: String?

        /// Minimum watchOS version
        public let minWatchOS: String?

        /// Minimum visionOS version
        public let minVisionOS: String?

        /// How availability was determined ("api", "parsed", "inherited")
        public let availabilitySource: String?

        // MARK: Source-Specific Metadata

        /// Extensible metadata for source-specific fields
        /// Examples:
        /// - WWDC: ["sessionYear": "2024", "sessionNumber": "101", "videoId": "abc123"]
        /// - Forums: ["threadId": "12345", "category": "Development", "replyCount": "42"]
        public let metadata: [String: String]

        // MARK: Initializer

        public init(
            uri: String,
            source: String,
            title: String,
            content: String,
            filePath: String,
            contentHash: String,
            lastCrawled: Date = Date(),
            framework: String? = nil,
            language: String? = nil,
            sourceType: String = Shared.Constants.Database.defaultSourceTypeApple,
            packageId: Int? = nil,
            jsonData: String? = nil,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil,
            availabilitySource: String? = nil,
            metadata: [String: String] = [:]
        ) {
            self.uri = uri
            self.source = source
            self.title = title
            self.content = content
            self.filePath = filePath
            self.contentHash = contentHash
            self.lastCrawled = lastCrawled
            self.framework = framework
            self.language = language
            self.sourceType = sourceType
            self.packageId = packageId
            self.jsonData = jsonData
            self.minIOS = minIOS
            self.minMacOS = minMacOS
            self.minTvOS = minTvOS
            self.minWatchOS = minWatchOS
            self.minVisionOS = minVisionOS
            self.availabilitySource = availabilitySource
            self.metadata = metadata
        }
    }
}

// MARK: - Extracted Content

/// Results from AST extraction on source content
extension Search {
    public struct ExtractedContent: Sendable {
        /// Extracted symbols (functions, types, properties, etc.)
        public let symbols: [ASTIndexer.Symbol]

        /// Extracted imports
        public let imports: [ASTIndexer.Import]

        /// Whether parsing encountered errors
        public let hasErrors: Bool

        public init(
            symbols: [ASTIndexer.Symbol] = [],
            imports: [ASTIndexer.Import] = [],
            hasErrors: Bool = false
        ) {
            self.symbols = symbols
            self.imports = imports
            self.hasErrors = hasErrors
        }

        /// Empty result for non-code content
        public static let empty = Search.ExtractedContent()
    }
}

// MARK: - Source Indexer Protocol

/// Protocol for source-specific indexing logic.
/// Each source (apple-docs, wwdc-transcripts, swift-forums) implements this protocol
/// to handle its unique content structure and metadata extraction.
extension Search {
    public protocol SourceIndexer: Sendable {
        /// Source identifier (must match SourceRegistry entry)
        var sourceID: String { get }

        /// Human-readable name for logging
        var displayName: String { get }

        /// Validate an item before indexing
        /// - Returns: true if item is valid and should be indexed
        func validate(_ item: Search.SourceItem) -> Bool

        /// Extract code and symbols from content
        /// - Parameter item: The source item to extract from
        /// - Returns: Extracted symbols and imports for AST indexing
        func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent

        /// Pre-process item before indexing (optional transformation)
        /// - Parameter item: Original item
        /// - Returns: Transformed item ready for indexing
        func preprocess(_ item: Search.SourceItem) -> Search.SourceItem

        /// Post-process after indexing (optional cleanup/logging)
        /// - Parameter item: The indexed item
        func postprocess(_ item: Search.SourceItem)
    }
}

// MARK: - Default Implementations

public extension Search.SourceIndexer {
    /// Default validation: require non-empty URI and title
    func validate(_ item: Search.SourceItem) -> Bool {
        !item.uri.trimmingCharacters(in: .whitespaces).isEmpty &&
            !item.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Default extraction: use ASTIndexer.Extractor on content
    func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
        // Skip extraction for non-Swift content
        guard item.language == "swift" || item.language == nil else {
            return .empty
        }

        // Skip very short content (likely not code)
        guard item.content.count > 50 else {
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

    /// Default preprocessing: return item unchanged
    func preprocess(_ item: Search.SourceItem) -> Search.SourceItem {
        item
    }

    /// Default postprocessing: do nothing
    func postprocess(_: Search.SourceItem) {
        // No-op by default
    }
}

// MARK: - Apple Docs Indexer

/// Indexer for Apple Developer Documentation
extension Search {
    public struct AppleDocsIndexer: Search.SourceIndexer {
        public let sourceID = "apple-docs"
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
extension Search {
    public struct HIGIndexer: Search.SourceIndexer {
        public let sourceID = "hig"
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
        public let sourceID = "swift-evolution"
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

/// Indexer for Apple Sample Code projects
extension Sample {
    public struct Indexer: SearchModule.SourceIndexer {
        public let sourceID = "samples"
        public let displayName = "Sample Code"

        public init() {}

        public func extractCode(from item: SearchModule.SourceItem) -> SearchModule.ExtractedContent {
            // Sample code is full Swift files - extract everything
            let extractor = ASTIndexer.Extractor()
            let result = extractor.extract(from: item.content)

            return SearchModule.ExtractedContent(
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
        public let sourceID = "apple-archive"
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
        public let sourceID = "swift-book"
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
        public let sourceID = "swift-org"
        public let displayName = "Swift.org"

        public init() {}
    }
}

// MARK: - Packages Indexer

/// Indexer for Swift Package documentation
extension Search {
    public struct PackagesIndexer: Search.SourceIndexer {
        public let sourceID = "packages"
        public let displayName = "Swift Packages"

        public init() {}

        public func extractCode(from item: Search.SourceItem) -> Search.ExtractedContent {
            // Package docs have API documentation with declarations
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

// MARK: - Indexer Registry

/// Registry of all available source indexers
extension Search {
    public enum IndexerRegistry {
        /// All registered indexers
        private static let indexers: [String: any Search.SourceIndexer] = [
            "apple-docs": AppleDocsIndexer(),
            "hig": HIGIndexer(),
            "swift-evolution": SwiftEvolutionIndexer(),
            "samples": Sample.Indexer(),
            "apple-archive": AppleArchiveIndexer(),
            "swift-book": SwiftBookIndexer(),
            "swift-org": SwiftOrgIndexer(),
            "packages": PackagesIndexer(),
        ]

        /// Get indexer for a source ID
        /// - Parameter sourceID: The source identifier
        /// - Returns: The indexer, or nil if not found
        public static func indexer(for sourceID: String) -> (any Search.SourceIndexer)? {
            indexers[sourceID]
        }

        /// Get all registered source IDs
        public static var allSourceIDs: [String] {
            Array(indexers.keys).sorted()
        }

        /// Register a custom indexer (for extensions)
        /// Note: This is not thread-safe, should only be called at startup
        public static func register(_ indexer: some Search.SourceIndexer) {
            // Would need to make indexers mutable for this
            // For now, custom indexers should be added to the static dictionary
        }
    }
}

import ASTIndexer
import Foundation
import SharedConstants

// MARK: - Source Item

/// Unified container for content to be indexed from any source.
/// This decouples source-specific crawling from generic indexing logic.
///
/// Lifted from `SearchSQLite/Search.SourceIndexer.swift` to
/// `SearchModels` by epic #1007 Phase 1A (#1008) so per-source SPM
/// targets can construct `SourceItem` values via the foundation-only
/// seam without dragging the `SearchSQLite` concrete target in.
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

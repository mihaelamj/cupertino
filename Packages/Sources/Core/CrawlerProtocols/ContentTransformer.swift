import Foundation
import Shared

// MARK: - Content Transformer Protocol

/// Protocol for transforming raw content into Markdown
/// Implementations include HTML→Markdown, JSON→Markdown, XML→Markdown, etc.
public protocol ContentTransformer: Sendable {
    /// The type of raw content this transformer accepts
    associatedtype RawContent: Sendable

    /// Transform raw content into Markdown
    /// - Parameters:
    ///   - content: The raw content to transform
    ///   - url: The source URL (for resolving relative links)
    /// - Returns: Markdown string, or nil if transformation failed
    func transform(_ content: RawContent, url: URL) -> String?

    /// Extract links from the raw content
    /// - Parameter content: The raw content to extract links from
    /// - Returns: Array of discovered URLs
    func extractLinks(from content: RawContent) -> [URL]
}

// MARK: - Transform Result

/// Result of a content transformation
public struct TransformResult: Sendable {
    public let markdown: String
    public let links: [URL]
    public let metadata: TransformMetadata?
    public let structuredPage: StructuredDocumentationPage?

    public init(
        markdown: String,
        links: [URL],
        metadata: TransformMetadata? = nil,
        structuredPage: StructuredDocumentationPage? = nil
    ) {
        self.markdown = markdown
        self.links = links
        self.metadata = metadata
        self.structuredPage = structuredPage
    }
}

/// Metadata extracted during transformation
public struct TransformMetadata: Sendable {
    public let title: String?
    public let description: String?
    public let framework: String?
    public let platforms: [String]?
    public let isDeprecated: Bool

    public init(
        title: String? = nil,
        description: String? = nil,
        framework: String? = nil,
        platforms: [String]? = nil,
        isDeprecated: Bool = false
    ) {
        self.title = title
        self.description = description
        self.framework = framework
        self.platforms = platforms
        self.isDeprecated = isDeprecated
    }
}

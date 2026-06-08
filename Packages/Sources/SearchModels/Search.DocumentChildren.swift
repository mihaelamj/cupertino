import Foundation
import SharedConstants

// MARK: - Search.DocumentChildren

extension Search {
    /// Direct child node for document-outline browsing surfaces.
    public struct DocumentChild: Codable, Equatable, Sendable {
        public let uri: String
        public let title: String
        public let kind: String
        public let hasChildren: Bool

        public init(
            uri: String,
            title: String,
            kind: String,
            hasChildren: Bool
        ) {
            self.uri = uri
            self.title = title
            self.kind = kind
            self.hasChildren = hasChildren
        }
    }

    /// Result returned by `cupertino list-children` and MCP `list_children`.
    public struct DocumentChildrenPage: Codable, Equatable, Sendable {
        public let source: String
        public let parentURI: String
        public let children: [DocumentChild]

        public init(
            source: String,
            parentURI: String,
            children: [DocumentChild]
        ) {
            self.source = source
            self.parentURI = parentURI
            self.children = children
        }
    }

    /// Optional read-side refinement for APIs that browse document outlines.
    public protocol DocumentChildrenListing: Sendable {
        func listChildren(
            source: String,
            uri: String
        ) async throws -> Search.DocumentChildrenPage
    }
}

extension Search.DocumentChildrenListing {
    public func listChildren(
        source: String = Shared.Constants.SourcePrefix.appleDocs,
        uri: String
    ) async throws -> Search.DocumentChildrenPage {
        try await listChildren(source: source, uri: uri)
    }
}

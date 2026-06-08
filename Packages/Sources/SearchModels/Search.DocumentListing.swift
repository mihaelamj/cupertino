import Foundation
import SharedConstants

// MARK: - Search.DocumentListing

extension Search {
    /// Lightweight document row for framework-scoped browsing surfaces.
    public struct DocumentListItem: Codable, Equatable, Sendable {
        public let uri: String
        public let title: String
        public let kind: String

        public init(uri: String, title: String, kind: String) {
            self.uri = uri
            self.title = title
            self.kind = kind
        }
    }

    /// Paged result returned by `cupertino list-documents` and MCP `list_documents`.
    public struct DocumentListPage: Codable, Equatable, Sendable {
        public let source: String
        public let framework: String
        public let offset: Int
        public let limit: Int
        public let total: Int
        public let documents: [DocumentListItem]

        public init(
            source: String,
            framework: String,
            offset: Int,
            limit: Int,
            total: Int,
            documents: [DocumentListItem]
        ) {
            self.source = source
            self.framework = framework
            self.offset = offset
            self.limit = limit
            self.total = total
            self.documents = documents
        }
    }

    /// Optional read-side refinement for APIs that page document metadata.
    ///
    /// Kept separate from `Search.Database` so embedded readers and tests that only
    /// implement the core CupertinoDataKit contract are not forced to add this
    /// desktop-browser surface until they need it.
    public protocol DocumentListing: Sendable {
        func listDocuments(
            source: String,
            framework: String,
            offset: Int,
            limit: Int
        ) async throws -> Search.DocumentListPage
    }
}

extension Search.DocumentListing {
    public func listDocuments(
        source: String = Shared.Constants.SourcePrefix.appleDocs,
        framework: String,
        offset: Int = 0,
        limit: Int = Shared.Constants.Limit.defaultDocumentListLimit
    ) async throws -> Search.DocumentListPage {
        try await listDocuments(
            source: source,
            framework: framework,
            offset: offset,
            limit: limit
        )
    }
}

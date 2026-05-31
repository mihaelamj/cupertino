import Foundation
import SearchModels
import ServicesModels
import SharedConstants

// MARK: - Services.LiveDocsLookupStrategy

extension Services {
    /// 2026-05-26 audit #1055: production `Search.DocsLookupStrategy`
    /// conformer that wraps `Services.ServiceContainer.withDocsService`
    /// — the live SearchSQLite-backed reader. CLI / MCP composition
    /// root wires this into `Search.ReadEnvironment.docsLookup` so
    /// per-source `Search.DocsReadStrategy` instances can ask the
    /// live backend without per-source targets having to depend on
    /// SearchSQLite.
    public struct LiveDocsLookupStrategy: Search.DocsLookupStrategy {
        public let searchDatabaseFactory: any Search.DatabaseFactory

        public init(searchDatabaseFactory: any Search.DatabaseFactory) {
            self.searchDatabaseFactory = searchDatabaseFactory
        }

        public func read(uri: String, format: Search.DocumentFormat, dbURL: URL) async throws -> String? {
            try await Services.ServiceContainer.withDocsService(
                dbURL: dbURL,
                searchDatabaseFactory: searchDatabaseFactory
            ) { service in
                try await service.read(uri: uri, format: format)
            }
        }
    }
}

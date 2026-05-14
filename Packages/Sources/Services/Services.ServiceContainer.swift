import Foundation
import SampleIndex
import SearchModels
import ServicesModels
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Service Container

/// Composition utility for the Services target's read-side services
/// (`DocsSearchService`, `TeaserService`, `UnifiedSearchService`,
/// `Sample.Search.Service`). Provides `with*Service` static methods that
/// handle path resolution + existence checks + service disconnect, so
/// CLI / MCP / TUI callers don't have to repeat that boilerplate per
/// command.
///
/// The container does not import the Search target. Every search-side
/// database (`Search.Index`) is constructed by an injected
/// `Search.DatabaseFactory` (GoF Factory Method) that callers wire
/// from the composition root: CLI supplies a concrete
/// `LiveSearchDatabaseFactory` whose `openDatabase(at:)` opens a real
/// `Search.Index` actor; tests supply a mock conforming type.
extension Services {
    public enum ServiceContainer {
        // MARK: - Convenience Factory Methods

        /// Execute an operation with a docs service, handling lifecycle.
        public static func withDocsService<T>(
            dbPath: String? = nil,
            searchDatabaseFactory: any Search.DatabaseFactory,
            operation: (Services.DocsSearchService) async throws -> T
        ) async throws -> T {
            let resolvedPath = Shared.Utils.PathResolver.searchDatabase(dbPath)

            guard Shared.Utils.PathResolver.exists(resolvedPath) else {
                throw Shared.Core.ToolError.noData("Search database not found at \(resolvedPath.path). Run 'cupertino save' to build the index.")
            }

            let database = try await searchDatabaseFactory.openDatabase(at: resolvedPath)
            let service = Services.DocsSearchService(database: database)
            defer {
                Task {
                    await service.disconnect()
                }
            }

            return try await operation(service)
        }

        /// Execute an operation with a sample service, handling lifecycle.
        /// No `makeSearchDatabase` here: the sample service is backed by
        /// `Sample.Search.Service`, which constructs its own
        /// `Sample.Index.Database` — that's a SampleIndex-target concern,
        /// not Search.
        public static func withSampleService<T: Sendable>(
            dbPath: URL,
            operation: (Sample.Search.Service) async throws -> T
        ) async throws -> T {
            guard Shared.Utils.PathResolver.exists(dbPath) else {
                throw Shared.Core.ToolError.noData("Sample database not found at \(dbPath.path). Run 'cupertino save --samples' to build the index.")
            }

            let service = try await Sample.Search.Service(dbPath: dbPath)
            let result = try await operation(service)
            await service.disconnect()
            return result
        }

        /// Execute an operation with a teaser service.
        ///
        /// The teaser service reads from the search database (optional)
        /// and the sample database (optional). Missing paths degrade
        /// each source to empty rather than failing.
        public static func withTeaserService<T: Sendable>(
            searchDbPath: String? = nil,
            sampleDbPath: URL? = nil,
            searchDatabaseFactory: any Search.DatabaseFactory,
            operation: (Services.TeaserService) async throws -> T
        ) async throws -> T {
            let resolvedSearchPath = Shared.Utils.PathResolver.searchDatabase(searchDbPath)
            let resolvedSamplePath = sampleDbPath ?? Sample.Index.defaultDatabasePath

            let searchIndex: (any Search.Database)?
            if Shared.Utils.PathResolver.exists(resolvedSearchPath) {
                searchIndex = try await searchDatabaseFactory.openDatabase(at: resolvedSearchPath)
            } else {
                searchIndex = nil
            }

            let service = try await Services.TeaserService(
                searchIndex: searchIndex,
                sampleDbPath: Shared.Utils.PathResolver.exists(resolvedSamplePath) ? resolvedSamplePath : nil
            )

            return try await operation(service)
        }

        /// Execute an operation with a unified search service. Same
        /// composition pattern as `withTeaserService`.
        public static func withUnifiedSearchService<T: Sendable>(
            searchDbPath: String? = nil,
            sampleDbPath: URL? = nil,
            searchDatabaseFactory: any Search.DatabaseFactory,
            operation: (Services.UnifiedSearchService) async throws -> T
        ) async throws -> T {
            let resolvedSearchPath = Shared.Utils.PathResolver.searchDatabase(searchDbPath)
            let resolvedSamplePath = sampleDbPath ?? Sample.Index.defaultDatabasePath

            let searchIndex: (any Search.Database)?
            if Shared.Utils.PathResolver.exists(resolvedSearchPath) {
                searchIndex = try await searchDatabaseFactory.openDatabase(at: resolvedSearchPath)
            } else {
                searchIndex = nil
            }

            let service = try await Services.UnifiedSearchService(
                searchIndex: searchIndex,
                sampleDbPath: Shared.Utils.PathResolver.exists(resolvedSamplePath) ? resolvedSamplePath : nil
            )

            return try await operation(service)
        }
    }
}

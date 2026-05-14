import Foundation
import SampleIndexModels
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
        /// The sample database is opened through an injected
        /// `Sample.Index.DatabaseFactory` (GoF Factory Method) —
        /// symmetric with `Search.DatabaseFactory` on the docs side
        /// (#494). This target builds the `Sample.Search.Service`
        /// wrapper internally; the composition root never has to know
        /// about it.
        public static func withSampleService<T: Sendable>(
            dbPath: URL,
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
            operation: (any Sample.Search.Searcher) async throws -> T
        ) async throws -> T {
            guard Shared.Utils.PathResolver.exists(dbPath) else {
                throw Shared.Core.ToolError.noData("Sample database not found at \(dbPath.path). Run 'cupertino save --samples' to build the index.")
            }

            let database = try await sampleDatabaseFactory.openDatabase(at: dbPath)
            let service = Sample.Search.Service(database: database)
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
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
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

            let sampleDatabase: (any Sample.Index.Reader)?
            if Shared.Utils.PathResolver.exists(resolvedSamplePath) {
                sampleDatabase = try await sampleDatabaseFactory.openDatabase(at: resolvedSamplePath)
            } else {
                sampleDatabase = nil
            }

            let service = Services.TeaserService(
                searchIndex: searchIndex,
                sampleDatabase: sampleDatabase
            )

            return try await operation(service)
        }

        /// Execute an operation with a unified search service. Same
        /// composition pattern as `withTeaserService`.
        public static func withUnifiedSearchService<T: Sendable>(
            searchDbPath: String? = nil,
            sampleDbPath: URL? = nil,
            searchDatabaseFactory: any Search.DatabaseFactory,
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
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

            let sampleDatabase: (any Sample.Index.Reader)?
            if Shared.Utils.PathResolver.exists(resolvedSamplePath) {
                sampleDatabase = try await sampleDatabaseFactory.openDatabase(at: resolvedSamplePath)
            } else {
                sampleDatabase = nil
            }

            let service = Services.UnifiedSearchService(
                searchIndex: searchIndex,
                sampleDatabase: sampleDatabase
            )

            return try await operation(service)
        }
    }
}

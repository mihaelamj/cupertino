import Foundation
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants
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
        ///
        /// `searchDB` is the resolved search.db URL supplied by the caller
        /// at its composition root. Pre-#535 this method accepted an
        /// optional `String?` path and fell back to
        /// `Shared.Constants.defaultSearchDatabase` via
        /// `Shared.Utils.PathResolver.searchDatabase` (a Service Locator
        /// shape — Seemann 2011 ch. 5). Strict DI requires the caller to
        /// supply the URL it wants; no producer-side default reaches.
        public static func withDocsService<T>(
            searchDB: URL,
            searchDatabaseFactory: any Search.DatabaseFactory,
            operation: (Services.DocsSearchService) async throws -> T
        ) async throws -> T {
            guard FileManager.default.fileExists(atPath: searchDB.path) else {
                throw Shared.Core.ToolError.noData("Search database not found at \(searchDB.path). Run 'cupertino save' to build the index.")
            }

            let database = try await searchDatabaseFactory.openDatabase(at: searchDB)
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
            samplesDB: URL,
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
            operation: (any Sample.Search.Searcher) async throws -> T
        ) async throws -> T {
            guard FileManager.default.fileExists(atPath: samplesDB.path) else {
                throw Shared.Core.ToolError.noData("Sample database not found at \(samplesDB.path). Run 'cupertino save --samples' to build the index.")
            }

            let database = try await sampleDatabaseFactory.openDatabase(at: samplesDB)
            let service = Sample.Search.Service(database: database)
            let result = try await operation(service)
            await service.disconnect()
            return result
        }

        /// Execute an operation with a teaser service.
        ///
        /// The teaser service reads from the search database (optional)
        /// and the sample database (optional). Missing paths on disk
        /// degrade each source to empty rather than failing — pass any
        /// URL the caller has resolved; existence is checked here.
        public static func withTeaserService<T: Sendable>(
            searchDB: URL,
            samplesDB: URL,
            searchDatabaseFactory: any Search.DatabaseFactory,
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
            operation: (Services.TeaserService) async throws -> T
        ) async throws -> T {
            let searchIndex: (any Search.Database)?
            if FileManager.default.fileExists(atPath: searchDB.path) {
                searchIndex = try await searchDatabaseFactory.openDatabase(at: searchDB)
            } else {
                searchIndex = nil
            }

            let sampleDatabase: (any Sample.Index.Reader)?
            if FileManager.default.fileExists(atPath: samplesDB.path) {
                sampleDatabase = try await sampleDatabaseFactory.openDatabase(at: samplesDB)
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
            searchDB: URL,
            samplesDB: URL,
            searchDatabaseFactory: any Search.DatabaseFactory,
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
            operation: (Services.UnifiedSearchService) async throws -> T
        ) async throws -> T {
            let searchIndex: (any Search.Database)?
            if FileManager.default.fileExists(atPath: searchDB.path) {
                searchIndex = try await searchDatabaseFactory.openDatabase(at: searchDB)
            } else {
                searchIndex = nil
            }

            let sampleDatabase: (any Sample.Index.Reader)?
            if FileManager.default.fileExists(atPath: samplesDB.path) {
                sampleDatabase = try await sampleDatabaseFactory.openDatabase(at: samplesDB)
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

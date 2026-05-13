import Foundation
import SampleIndex
import Search
import SharedConstants
import SharedCore
import SharedUtils
import SearchModels

// MARK: - Service Container

/// Container for managing service lifecycle and providing access to search services.
/// Handles database connections and cleanup.
extension Services {
    public actor ServiceContainer {
        private var docsService: Services.DocsSearchService?
        private var higService: Services.HIGSearchService?
        private var sampleService: Sample.Search.Service?

        private let searchDbPath: URL
        private let sampleDbPath: URL?

        /// Initialize with database paths
        public init(
            searchDbPath: URL = Shared.Constants.defaultSearchDatabase,
            sampleDbPath: URL? = nil
        ) {
            self.searchDbPath = searchDbPath
            self.sampleDbPath = sampleDbPath
        }

        // MARK: - Service Access

        /// Get or create the documentation search service
        public func getDocsService() async throws -> Services.DocsSearchService {
            if let service = docsService {
                return service
            }

            let index = try await Search.Index(dbPath: searchDbPath)
            let service = Services.DocsSearchService(database: index)
            docsService = service
            return service
        }

        /// Get or create the HIG search service
        public func getHIGService() async throws -> Services.HIGSearchService {
            if let service = higService {
                return service
            }

            let docsService = try await getDocsService()
            let service = Services.HIGSearchService(docsService: docsService)
            higService = service
            return service
        }

        /// Get or create the sample search service
        public func getSampleService() async throws -> Sample.Search.Service {
            if let service = sampleService {
                return service
            }

            guard let dbPath = sampleDbPath else {
                throw Shared.Core.ToolError.noData("Sample database path not configured")
            }

            let service = try await Sample.Search.Service(dbPath: dbPath)
            sampleService = service
            return service
        }

        // MARK: - Lifecycle

        /// Disconnect all services
        public func disconnectAll() async {
            if let docs = docsService {
                await docs.disconnect()
                docsService = nil
            }

            if let hig = higService {
                await hig.disconnect()
                higService = nil
            }

            if let sample = sampleService {
                await sample.disconnect()
                sampleService = nil
            }
        }

        // MARK: - Convenience Factory Methods

        /// Execute an operation with a docs service, handling lifecycle
        public static func withDocsService<T>(
            dbPath: String? = nil,
            operation: (Services.DocsSearchService) async throws -> T
        ) async throws -> T {
            let resolvedPath = Shared.Utils.PathResolver.searchDatabase(dbPath)

            guard Shared.Utils.PathResolver.exists(resolvedPath) else {
                throw Shared.Core.ToolError.noData("Search database not found at \(resolvedPath.path). Run 'cupertino save' to build the index.")
            }

            let index = try await Search.Index(dbPath: resolvedPath)
            let service = Services.DocsSearchService(database: index)
            defer {
                Task {
                    await service.disconnect()
                }
            }

            return try await operation(service)
        }

        /// Execute an operation with a HIG service, handling lifecycle
        public static func withHIGService<T>(
            dbPath: String? = nil,
            operation: (Services.HIGSearchService) async throws -> T
        ) async throws -> T {
            let resolvedPath = Shared.Utils.PathResolver.searchDatabase(dbPath)

            guard Shared.Utils.PathResolver.exists(resolvedPath) else {
                throw Shared.Core.ToolError.noData("Search database not found at \(resolvedPath.path). Run 'cupertino save' to build the index.")
            }

            let index = try await Search.Index(dbPath: resolvedPath)
            let service = Services.HIGSearchService(database: index)
            defer {
                Task {
                    await service.disconnect()
                }
            }

            return try await operation(service)
        }

        /// Execute an operation with a sample service, handling lifecycle
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

        /// Execute an operation with a teaser service. The teaser service
        /// reads from the search database (optional) and the sample
        /// database (optional). If either path is missing or doesn't
        /// resolve to a file, the service handles that source as empty
        /// rather than failing.
        public static func withTeaserService<T: Sendable>(
            searchDbPath: String? = nil,
            sampleDbPath: URL? = nil,
            operation: (Services.TeaserService) async throws -> T,
        ) async throws -> T {
            let resolvedSearchPath = Shared.Utils.PathResolver.searchDatabase(searchDbPath)
            let resolvedSamplePath = sampleDbPath ?? Sample.Index.defaultDatabasePath

            let searchIndex: (any Search.Database)?
            if Shared.Utils.PathResolver.exists(resolvedSearchPath) {
                searchIndex = try await Search.Index(dbPath: resolvedSearchPath)
            } else {
                searchIndex = nil
            }

            let service = try await Services.TeaserService(
                searchIndex: searchIndex,
                sampleDbPath: Shared.Utils.PathResolver.exists(resolvedSamplePath) ? resolvedSamplePath : nil,
            )

            return try await operation(service)
        }

        /// Execute an operation with a unified search service. Same
        /// composition pattern as `withTeaserService`.
        public static func withUnifiedSearchService<T: Sendable>(
            searchDbPath: String? = nil,
            sampleDbPath: URL? = nil,
            operation: (Services.UnifiedSearchService) async throws -> T,
        ) async throws -> T {
            let resolvedSearchPath = Shared.Utils.PathResolver.searchDatabase(searchDbPath)
            let resolvedSamplePath = sampleDbPath ?? Sample.Index.defaultDatabasePath

            let searchIndex: (any Search.Database)?
            if Shared.Utils.PathResolver.exists(resolvedSearchPath) {
                searchIndex = try await Search.Index(dbPath: resolvedSearchPath)
            } else {
                searchIndex = nil
            }

            let service = try await Services.UnifiedSearchService(
                searchIndex: searchIndex,
                sampleDbPath: Shared.Utils.PathResolver.exists(resolvedSamplePath) ? resolvedSamplePath : nil,
            )

            return try await operation(service)
        }
    }
}

import Foundation
import SampleIndex
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Unified Search Service

/// Service for searching across all documentation sources.
/// Consolidates search logic previously duplicated between CLI and MCP.
extension Services {
    public actor UnifiedSearchService {
        private let searchIndex: (any Search.Database)?
        private let sampleDatabase: (any Sample.Index.Reader)?

        /// Initialize with existing database connections. The concrete
        /// `Search.Index?` form continues to compile because `Search.Index`
        /// conforms to `Search.Database`; same for `Sample.Index.Database`
        /// conforming to `Sample.Index.Reader`.
        public init(searchIndex: (any Search.Database)?, sampleDatabase: (any Sample.Index.Reader)?) {
            self.searchIndex = searchIndex
            self.sampleDatabase = sampleDatabase
        }

        /// Initialize with a sample-database path. The search-side
        /// database is injected via `searchIndex:` because constructing
        /// a `Search.Index` requires the Search target — which Services
        /// no longer imports. The composition root
        /// (`withUnifiedSearchService` in `Services.ServiceContainer`)
        /// wires both sides.
        public init(searchIndex: (any Search.Database)?, sampleDbPath: URL?) async throws {
            self.searchIndex = searchIndex

            if let sampleDbPath, Shared.Utils.PathResolver.exists(sampleDbPath) {
                sampleDatabase = try await Sample.Index.Database(dbPath: sampleDbPath)
            } else {
                sampleDatabase = nil
            }
        }

        // MARK: - Unified Search

        /// Search all 8 sources and return combined results
        public func searchAll(
            query: String,
            framework: String?,
            limit: Int
        ) async -> Services.Formatter.Unified.Input {
            async let docResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: framework,
                limit: limit
            )

            async let archiveResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.appleArchive,
                framework: framework,
                limit: limit,
                includeArchive: true
            )

            async let sampleResults = searchSamples(
                query: query,
                framework: framework,
                limit: limit
            )

            async let higResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.hig,
                framework: nil,
                limit: limit
            )

            async let swiftEvolutionResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftEvolution,
                framework: nil,
                limit: limit
            )

            async let swiftOrgResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftOrg,
                framework: nil,
                limit: limit
            )

            async let swiftBookResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftBook,
                framework: nil,
                limit: limit
            )

            async let packagesResults = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.packages,
                framework: nil,
                limit: limit
            )

            return await Services.Formatter.Unified.Input(
                docResults: docResults,
                archiveResults: archiveResults,
                sampleResults: sampleResults,
                higResults: higResults,
                swiftEvolutionResults: swiftEvolutionResults,
                swiftOrgResults: swiftOrgResults,
                swiftBookResults: swiftBookResults,
                packagesResults: packagesResults,
                limit: limit
            )
        }

        // MARK: - Individual Source Search

        /// Search a specific documentation source
        private func searchSource(
            query: String,
            source: String,
            framework: String?,
            limit: Int,
            includeArchive: Bool = false
        ) async -> [Search.Result] {
            guard let searchIndex else { return [] }

            do {
                return try await searchIndex.search(
                    query: query,
                    source: source,
                    framework: framework,
                    language: nil,
                    limit: limit,
                    includeArchive: includeArchive
                )
            } catch {
                return []
            }
        }

        /// Search sample code projects
        private func searchSamples(
            query: String,
            framework: String?,
            limit: Int
        ) async -> [Sample.Index.Project] {
            guard let sampleDatabase else { return [] }

            do {
                return try await sampleDatabase.searchProjects(
                    query: query,
                    framework: framework,
                    limit: limit
                )
            } catch {
                return []
            }
        }

        // MARK: - Lifecycle

        /// Disconnect database connections
        public func disconnect() async {
            // Note: In actor-based design, we don't explicitly close
            // connections - they are cleaned up when the actor is deallocated
        }
    }
}

// The `withUnifiedSearchService` factory lives in
// `Services.ServiceContainer.swift` alongside the other `with*Service`
// factories — that file keeps `import Search` for the Search.Index
// instantiation; this file no longer needs it.

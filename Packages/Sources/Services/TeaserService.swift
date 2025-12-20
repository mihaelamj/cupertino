import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Teaser Service

/// Service for fetching teaser results from sources the user didn't search.
/// Consolidates teaser logic previously duplicated between CLI and MCP.
public actor TeaserService {
    private let searchIndex: Search.Index?
    private let sampleDatabase: SampleIndex.Database?

    /// Initialize with existing database connections
    public init(searchIndex: Search.Index?, sampleDatabase: SampleIndex.Database?) {
        self.searchIndex = searchIndex
        self.sampleDatabase = sampleDatabase
    }

    /// Initialize with database paths (creates connections)
    public init(searchDbPath: URL?, sampleDbPath: URL?) async throws {
        if let searchDbPath, PathResolver.exists(searchDbPath) {
            searchIndex = try await Search.Index(dbPath: searchDbPath)
        } else {
            searchIndex = nil
        }

        if let sampleDbPath, PathResolver.exists(sampleDbPath) {
            sampleDatabase = try await SampleIndex.Database(dbPath: sampleDbPath)
        } else {
            sampleDatabase = nil
        }
    }

    // MARK: - Fetch All Teasers

    /// Fetch teaser results from all sources except the one being searched
    public func fetchAllTeasers(
        query: String,
        framework: String?,
        currentSource: String?,
        includeArchive: Bool
    ) async -> TeaserResults {
        var teasers = TeaserResults()
        let source = currentSource ?? Shared.Constants.SourcePrefix.appleDocs

        // Apple Documentation teaser (unless searching apple-docs)
        if source != Shared.Constants.SourcePrefix.appleDocs {
            teasers.appleDocs = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.appleDocs
            )
        }

        // Samples teaser (unless searching samples)
        if source != Shared.Constants.SourcePrefix.samples,
           source != Shared.Constants.SourcePrefix.appleSampleCode {
            teasers.samples = await fetchTeaserSamples(query: query, framework: framework)
        }

        // Archive teaser (unless searching archive or include_archive is set)
        if !includeArchive, source != Shared.Constants.SourcePrefix.appleArchive {
            teasers.archive = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.appleArchive
            )
        }

        // HIG teaser (unless searching HIG)
        if source != Shared.Constants.SourcePrefix.hig {
            teasers.hig = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.hig
            )
        }

        // Swift Evolution teaser (unless searching swift-evolution)
        if source != Shared.Constants.SourcePrefix.swiftEvolution {
            teasers.swiftEvolution = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.swiftEvolution
            )
        }

        // Swift.org teaser (unless searching swift-org)
        if source != Shared.Constants.SourcePrefix.swiftOrg {
            teasers.swiftOrg = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.swiftOrg
            )
        }

        // Swift Book teaser (unless searching swift-book)
        if source != Shared.Constants.SourcePrefix.swiftBook {
            teasers.swiftBook = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.swiftBook
            )
        }

        // Packages teaser (unless searching packages)
        if source != Shared.Constants.SourcePrefix.packages {
            teasers.packages = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.packages
            )
        }

        return teasers
    }

    // MARK: - Individual Teaser Fetchers

    /// Fetch a few sample projects as teaser
    public func fetchTeaserSamples(query: String, framework: String?) async -> [SampleIndex.Project] {
        guard let sampleDatabase else { return [] }

        do {
            return try await sampleDatabase.searchProjects(
                query: query,
                framework: framework,
                limit: Shared.Constants.Limit.teaserLimit
            )
        } catch {
            return []
        }
    }

    /// Fetch teaser results from a specific source
    public func fetchTeaserFromSource(query: String, sourceType: String) async -> [Search.Result] {
        guard let searchIndex else { return [] }

        do {
            return try await searchIndex.search(
                query: query,
                source: sourceType,
                framework: nil,
                language: nil,
                limit: Shared.Constants.Limit.teaserLimit,
                includeArchive: sourceType == Shared.Constants.SourcePrefix.appleArchive
            )
        } catch {
            return []
        }
    }

    // MARK: - Lifecycle

    /// Disconnect database connections
    public func disconnect() async {
        // Note: In actor-based design, connections are cleaned up on deallocation
    }
}

// MARK: - ServiceContainer Extension

extension ServiceContainer {
    /// Execute an operation with a teaser service
    public static func withTeaserService<T: Sendable>(
        searchDbPath: String? = nil,
        sampleDbPath: URL? = nil,
        operation: (TeaserService) async throws -> T
    ) async throws -> T {
        let resolvedSearchPath = PathResolver.searchDatabase(searchDbPath)
        let resolvedSamplePath = sampleDbPath ?? SampleIndex.defaultDatabasePath

        let service = try await TeaserService(
            searchDbPath: PathResolver.exists(resolvedSearchPath) ? resolvedSearchPath : nil,
            sampleDbPath: PathResolver.exists(resolvedSamplePath) ? resolvedSamplePath : nil
        )

        return try await operation(service)
    }
}

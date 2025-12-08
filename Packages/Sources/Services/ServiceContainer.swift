import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Service Container

/// Container for managing service lifecycle and providing access to search services.
/// Handles database connections and cleanup.
public actor ServiceContainer {
    private var docsService: DocsSearchService?
    private var higService: HIGSearchService?
    private var sampleService: SampleSearchService?

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
    public func getDocsService() async throws -> DocsSearchService {
        if let service = docsService {
            return service
        }

        let service = try await DocsSearchService(dbPath: searchDbPath)
        docsService = service
        return service
    }

    /// Get or create the HIG search service
    public func getHIGService() async throws -> HIGSearchService {
        if let service = higService {
            return service
        }

        let docsService = try await getDocsService()
        let service = HIGSearchService(docsService: docsService)
        higService = service
        return service
    }

    /// Get or create the sample search service
    public func getSampleService() async throws -> SampleSearchService {
        if let service = sampleService {
            return service
        }

        guard let dbPath = sampleDbPath else {
            throw ToolError.noData("Sample database path not configured")
        }

        let service = try await SampleSearchService(dbPath: dbPath)
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
        operation: (DocsSearchService) async throws -> T
    ) async throws -> T {
        let resolvedPath = PathResolver.searchDatabase(dbPath)

        guard PathResolver.exists(resolvedPath) else {
            throw ToolError.noData("Search database not found at \(resolvedPath.path). Run 'cupertino save' to build the index.")
        }

        let service = try await DocsSearchService(dbPath: resolvedPath)
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
        operation: (HIGSearchService) async throws -> T
    ) async throws -> T {
        let resolvedPath = PathResolver.searchDatabase(dbPath)

        guard PathResolver.exists(resolvedPath) else {
            throw ToolError.noData("Search database not found at \(resolvedPath.path). Run 'cupertino save' to build the index.")
        }

        let index = try await Search.Index(dbPath: resolvedPath)
        let service = HIGSearchService(index: index)
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
        operation: (SampleSearchService) async throws -> T
    ) async throws -> T {
        guard PathResolver.exists(dbPath) else {
            throw ToolError.noData("Sample database not found at \(dbPath.path). Run 'cupertino index' to build the index.")
        }

        let service = try await SampleSearchService(dbPath: dbPath)
        let result = try await operation(service)
        await service.disconnect()
        return result
    }
}

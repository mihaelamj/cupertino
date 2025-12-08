import Foundation
import SampleIndex
import Shared

// MARK: - Sample Search Query

/// Query parameters for sample code searches
public struct SampleQuery: Sendable {
    public let text: String
    public let framework: String?
    public let searchFiles: Bool
    public let limit: Int

    public init(
        text: String,
        framework: String? = nil,
        searchFiles: Bool = true,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) {
        self.text = text
        self.framework = framework
        self.searchFiles = searchFiles
        self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
    }
}

// MARK: - Sample Search Result

/// Combined result from project and file searches
public struct SampleSearchResult: Sendable {
    public let projects: [SampleIndex.Project]
    public let files: [SampleIndex.Database.FileSearchResult]

    public init(projects: [SampleIndex.Project], files: [SampleIndex.Database.FileSearchResult]) {
        self.projects = projects
        self.files = files
    }

    /// Check if the result is empty
    public var isEmpty: Bool {
        projects.isEmpty && files.isEmpty
    }

    /// Total count of results
    public var totalCount: Int {
        projects.count + files.count
    }
}

// MARK: - Sample Search Service

/// Service for searching Apple sample code projects and files.
/// Wraps SampleIndex.Database with a clean interface.
public actor SampleSearchService {
    private let database: SampleIndex.Database

    /// Initialize with an existing database
    public init(database: SampleIndex.Database) {
        self.database = database
    }

    /// Initialize with a database path
    public init(dbPath: URL) async throws {
        database = try await SampleIndex.Database(dbPath: dbPath)
    }

    // MARK: - Search Methods

    /// Search with a specialized query
    public func search(_ query: SampleQuery) async throws -> SampleSearchResult {
        let projects = try await database.searchProjects(
            query: query.text,
            framework: query.framework,
            limit: query.limit
        )

        var files: [SampleIndex.Database.FileSearchResult] = []
        if query.searchFiles {
            files = try await database.searchFiles(
                query: query.text,
                projectId: nil,
                limit: query.limit
            )
        }

        return SampleSearchResult(projects: projects, files: files)
    }

    /// Simple text search
    public func search(text: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> SampleSearchResult {
        try await search(SampleQuery(text: text, limit: limit))
    }

    /// Search within a specific framework
    public func search(text: String, framework: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> SampleSearchResult {
        try await search(SampleQuery(text: text, framework: framework, limit: limit))
    }

    // MARK: - Project Access

    /// Get a project by ID
    public func getProject(id: String) async throws -> SampleIndex.Project? {
        try await database.getProject(id: id)
    }

    /// List all projects
    public func listProjects(framework: String? = nil, limit: Int = 50) async throws -> [SampleIndex.Project] {
        try await database.listProjects(framework: framework, limit: limit)
    }

    /// Get total project count
    public func projectCount() async throws -> Int {
        try await database.projectCount()
    }

    // MARK: - File Access

    /// Get a file by project ID and path
    public func getFile(projectId: String, path: String) async throws -> SampleIndex.File? {
        try await database.getFile(projectId: projectId, path: path)
    }

    /// List files in a project
    public func listFiles(projectId: String, folder: String? = nil) async throws -> [SampleIndex.File] {
        try await database.listFiles(projectId: projectId, folder: folder)
    }

    /// Get total file count
    public func fileCount() async throws -> Int {
        try await database.fileCount()
    }

    // MARK: - Lifecycle

    /// Disconnect from the database
    public func disconnect() async {
        await database.disconnect()
    }
}

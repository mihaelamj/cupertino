import Foundation
import SampleIndex
import SampleIndexModels
import SharedConstants
import SharedCore

// MARK: - Sample Search

// `Sample.Search.Query` and `Sample.Search.Result` lifted to the
// `SampleIndexModels` target so callers (`SearchToolProvider` and
// future MCP / CLI surfaces) can construct queries without importing
// the full `Services` target. The actor below stays here because it
// holds behaviour over `any Sample.Index.Reader`.

// MARK: - Sample Search Service

/// Service for searching Apple sample code projects and files.
/// Wraps Sample.Index.Database with a clean interface.
extension Sample.Search {
    public actor Service {
        private let database: any Sample.Index.Reader

        /// Initialize with an existing database. Accepts any
        /// `Sample.Index.Reader` so this layer doesn't depend on the
        /// concrete `Sample.Index.Database` actor — the composition
        /// root supplies it.
        public init(database: any Sample.Index.Reader) {
            self.database = database
        }

        /// Initialize with a database path. Keeps the convenience init
        /// that wraps `Sample.Index.Database` in callers that want a
        /// one-line construct-and-use; the typed-against-protocol field
        /// above means upper layers don't see this concrete dep.
        public init(dbPath: URL) async throws {
            database = try await Sample.Index.Database(dbPath: dbPath)
        }

        // MARK: - Search Methods

        /// Search with a specialized query
        public func search(_ query: Sample.Search.Query) async throws -> Sample.Search.Result {
            let projects = try await database.searchProjects(
                query: query.text,
                framework: query.framework,
                limit: query.limit
            )

            var files: [Sample.Index.FileSearchResult] = []
            if query.searchFiles {
                files = try await database.searchFiles(
                    query: query.text,
                    projectId: nil,
                    fileExtension: nil,
                    limit: query.limit,
                    platform: query.platform,
                    minVersion: query.minVersion
                )
            }

            return Sample.Search.Result(projects: projects, files: files)
        }

        /// Simple text search
        public func search(text: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> Sample.Search.Result {
            try await search(Sample.Search.Query(text: text, limit: limit))
        }

        /// Search within a specific framework
        public func search(text: String, framework: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> Sample.Search.Result {
            try await search(Sample.Search.Query(text: text, framework: framework, limit: limit))
        }

        // MARK: - Project Access

        /// Get a project by ID
        public func getProject(id: String) async throws -> Sample.Index.Project? {
            try await database.getProject(id: id)
        }

        /// List all projects
        public func listProjects(framework: String? = nil, limit: Int = 50) async throws -> [Sample.Index.Project] {
            try await database.listProjects(framework: framework, limit: limit)
        }

        /// Get total project count
        public func projectCount() async throws -> Int {
            try await database.projectCount()
        }

        // MARK: - File Access

        /// Get a file by project ID and path
        public func getFile(projectId: String, path: String) async throws -> Sample.Index.File? {
            try await database.getFile(projectId: projectId, path: path)
        }

        /// List files in a project
        public func listFiles(projectId: String, folder: String? = nil) async throws -> [Sample.Index.File] {
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
}

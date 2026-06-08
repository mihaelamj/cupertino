import SampleIndexModels
import SharedConstants

// MARK: - CupertinoDataEngine.SampleReaderBox

extension CupertinoDataEngine {
    struct SampleReaderBox: Sample.Index.Reader {
        let base: any Sample.Index.Reader

        // swiftlint:disable:next function_parameter_count
        func searchProjects(
            query: String,
            framework: String?,
            limit: Int,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?
        ) async throws -> [Sample.Index.Project] {
            try await base.searchProjects(
                query: query,
                framework: framework,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS
            )
        }

        // swiftlint:disable:next function_parameter_count
        func searchFiles(
            query: String,
            projectId: String?,
            fileExtension: String?,
            limit: Int,
            platform: String?,
            minVersion: String?
        ) async throws -> [Sample.Index.FileSearchResult] {
            try await base.searchFiles(
                query: query,
                projectId: projectId,
                fileExtension: fileExtension,
                limit: limit,
                platform: platform,
                minVersion: minVersion
            )
        }

        func searchSymbolsForFiles(query: String, limit: Int) async throws -> Set<String> {
            try await base.searchSymbolsForFiles(query: query, limit: limit)
        }

        func searchFilesByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Sample.Index.FileSearchResult] {
            try await base.searchFilesByGenericConstraint(
                constraint: constraint,
                framework: framework,
                limit: limit
            )
        }

        func getProject(id: String) async throws -> Sample.Index.Project? {
            try await base.getProject(id: id)
        }

        func listProjects(
            framework: String?,
            limit: Int
        ) async throws -> [Sample.Index.Project] {
            try await base.listProjects(framework: framework, limit: limit)
        }

        func projectCount() async throws -> Int {
            try await base.projectCount()
        }

        func getFile(
            projectId: String,
            path: String
        ) async throws -> Sample.Index.File? {
            try await base.getFile(projectId: projectId, path: path)
        }

        func listFiles(
            projectId: String,
            folder: String?
        ) async throws -> [Sample.Index.File] {
            try await base.listFiles(projectId: projectId, folder: folder)
        }

        func fileCount() async throws -> Int {
            try await base.fileCount()
        }

        func disconnect() async {
            // Borrowed sample readers do not own the engine's cached connection.
            // CupertinoDataEngine.disconnect() closes the underlying handle.
        }
    }
}

import Foundation
import SharedConstants

// MARK: - Sample.Index.Reader

/// Read-only seam for the SampleIndex database actor.
///
/// `Sample.Index.Database` (the concrete actor in the `SampleIndex` SPM
/// target) ships a full read+write surface, but downstream consumers
/// (`Sample.Search.Service` in `Services`, `CompositeToolProvider` in
/// `SearchToolProvider`) only need the read methods. Lifting those
/// methods into a protocol here lets every consumer be typed against
/// the abstraction and import `SampleIndexModels` instead of pulling in
/// the full `SampleIndex` target with its indexer, schema, and writer
/// surface.
///
/// Mirrors the `Search.Database` seam in `SearchModels`: protocol lives
/// in a tiny value-types + protocols target with foundation-only
/// dependencies; the concrete actor conforms via a one-line witness
/// extension in its owning target; the composition root (the CLI)
/// instantiates the concrete actor and upcasts it to
/// `any Sample.Index.Reader` when handing it to consumers.
extension Sample.Index {
    public protocol Reader: Sendable {
        // MARK: - Search

        /// Free-text search across project titles, descriptions, and
        /// metadata. Optionally narrows to a single framework.
        func searchProjects(
            query: String,
            framework: String?,
            limit: Int
        ) async throws -> [Sample.Index.Project]

        /// Free-text search across indexed source files. Optionally
        /// narrows to a single project or a single file extension, and
        /// applies the #233 platform / min-version filter pair when
        /// both are non-nil.
        func searchFiles(
            query: String,
            projectId: String?,
            fileExtension: String?,
            limit: Int,
            platform: String?,
            minVersion: String?
        ) async throws -> [Sample.Index.FileSearchResult]

        // MARK: - Project access

        /// Fetch a single project by its sample-code identifier
        /// (`apple-sample-code://<slug>`).
        func getProject(id: String) async throws -> Sample.Index.Project?

        /// List projects, optionally narrowed to a framework.
        func listProjects(
            framework: String?,
            limit: Int
        ) async throws -> [Sample.Index.Project]

        /// Total count of indexed projects across every framework.
        func projectCount() async throws -> Int

        // MARK: - File access

        /// Fetch a single source file by its project ID and
        /// repo-relative path.
        func getFile(
            projectId: String,
            path: String
        ) async throws -> Sample.Index.File?

        /// List files in a project, optionally narrowed to a sub-folder.
        func listFiles(
            projectId: String,
            folder: String?
        ) async throws -> [Sample.Index.File]

        /// Total count of indexed source files across every project.
        func fileCount() async throws -> Int

        // MARK: - Lifecycle

        /// Close the underlying SQLite connection. The protocol exposes
        /// this so `Sample.Search.Service.disconnect()` can fan out
        /// through the seam without seeing the concrete actor.
        func disconnect() async
    }
}

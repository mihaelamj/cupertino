import Foundation
import SharedConstants

// MARK: - Sample.Search.Searcher

/// Minimal read-only seam for a sample-code-search service.
///
/// Captures the surface that `SearchToolProvider` (and any future MCP /
/// CLI consumer) actually calls on `Sample.Search.Service` — a single
/// `search(_:) async throws -> Sample.Search.Result` method. The
/// concrete actor in the `Services` target conforms via a one-line
/// witness extension; consumers hold `any Sample.Search.Searcher`
/// instead of the actor.
///
/// Mirrors the `Search.Database` / `Sample.Index.Reader` /
/// `Services.DocsSearcher` pattern: protocol in a foundation-only
/// Models target, conformance witness in the producer target, wiring
/// at the composition root.
extension Sample.Search {
    public protocol Searcher: Sendable {
        /// Search Apple sample-code projects and files for the given
        /// query parameters.
        func search(_ query: Sample.Search.Query) async throws -> Sample.Search.Result

        /// Resolve a project by its catalog identifier. Returns nil
        /// when the project isn't in this index.
        func getProject(id: String) async throws -> Sample.Index.Project?

        /// List projects in the index, optionally filtered by
        /// framework. `limit` caps the returned count.
        func listProjects(framework: String?, limit: Int) async throws -> [Sample.Index.Project]

        /// Total project count in the index.
        func projectCount() async throws -> Int

        /// Resolve a single file inside a project. Returns nil when
        /// the file doesn't exist or its project isn't indexed.
        func getFile(projectId: String, path: String) async throws -> Sample.Index.File?

        /// List files inside a project, optionally narrowed to a
        /// folder path prefix.
        func listFiles(projectId: String, folder: String?) async throws -> [Sample.Index.File]

        /// Total file count in the index.
        func fileCount() async throws -> Int

        /// Release any resources held by the search service (DB
        /// connections, in-memory caches). Mirrors
        /// `Search.Database.disconnect()`.
        func disconnect() async
    }
}

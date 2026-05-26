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
        /// metadata. Optionally narrows to a single framework and applies
        /// the #732 5-field platform-minimum filter when any `min<Platform>`
        /// is non-nil. Multiple platform minima are AND-combined — a
        /// sample must satisfy every requested minimum to pass.
        func searchProjects(
            query: String,
            framework: String?,
            limit: Int,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?
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

        /// #837 read-side wiring — return the set of `"projectId|path"`
        /// composite keys identifying files whose `file_symbols` row
        /// LIKE-matches `query` in any of name / attributes / conformances
        /// / signature / generic_constraints. Caller boosts the rank of
        /// matching `Sample.Index.FileSearchResult` rows. Fails silently
        /// with an empty set; symbol search is an optional enhancement.
        func searchSymbolsForFiles(query: String, limit: Int) async throws -> Set<String>

        /// #857 — return file-symbol rows whose `generic_constraints`,
        /// `signature`, or `name` match the given constraint token,
        /// joined to `files` so the caller has project + file path. Used
        /// by the MCP `search_generics` tool's cross-DB fan-out. The
        /// optional `framework` argument matches against the parent
        /// project's framework column when set; pass nil to span every
        /// indexed project. Fails silently with an empty array.
        func searchFilesByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
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

// MARK: - #732 — backward-compatible overload

extension Sample.Index.Reader {
    /// Legacy three-argument overload retained so call sites that
    /// haven't been migrated to the 8-arg shape compile unchanged. Maps
    /// to the new shape with every `min<Platform>` argument set to nil
    /// (= no platform filter). New platform-filtered behaviour is opt-in
    /// through the explicit-args overload.
    public func searchProjects(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> [Sample.Index.Project] {
        try await searchProjects(
            query: query,
            framework: framework,
            limit: limit,
            minIOS: nil,
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
    }

    /// #857 default implementation. Conformers that haven't been
    /// updated to ship the new symbol-level cross-DB query return an
    /// empty array; the cross-DB merge in
    /// `CompositeToolProvider.handleSearchGenerics` then simply omits
    /// samples from the merged result. The production conformer
    /// `Sample.Index.Database` overrides this with a real implementation.
    public func searchFilesByGenericConstraint(
        constraint _: String,
        framework _: String?,
        limit _: Int
    ) async throws -> [Sample.Index.FileSearchResult] {
        []
    }
}

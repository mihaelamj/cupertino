import Foundation
import SharedConstants

// MARK: - Sample.Search.Result

/// Combined result from a sample-code search: matched projects + matched
/// file rows.
///
/// Previously declared inside
/// `Sources/Services/ReadCommands/Sample.Search.Service.swift`. Lifted
/// to a foundation-layer value type so consumers (`SearchToolProvider`,
/// CLI commands, MCP tool surfaces) can hold one without importing the
/// full `Services` target.
///
/// Carries `Sample.Index.Project` and `Sample.Index.FileSearchResult`
/// which already live in this same `SampleIndexModels` target, so the
/// lift introduces no new transitive dependencies.
extension Sample.Search {
    public struct Result: Sendable {
        public let projects: [Sample.Index.Project]
        public let files: [Sample.Index.FileSearchResult]

        public init(
            projects: [Sample.Index.Project],
            files: [Sample.Index.FileSearchResult]
        ) {
            self.projects = projects
            self.files = files
        }

        /// Check if the result is empty.
        public var isEmpty: Bool {
            projects.isEmpty && files.isEmpty
        }

        /// Total count of results across both projects and files.
        public var totalCount: Int {
            projects.count + files.count
        }
    }
}

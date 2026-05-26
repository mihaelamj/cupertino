import Foundation
import SharedConstants

// MARK: - Sample.Index.FileSearchResult

/// One row from a file-content search against the SampleIndex
/// FTS index. Returned by `Sample.Index.Reader.searchFiles(...)`
/// and the concrete `Sample.Index.Database.searchFiles(...)` it
/// witnesses.
///
/// Previously nested as `Sample.Index.Database.FileSearchResult`
/// inside the concrete actor. Lifted to a top-level value type
/// under `Sample.Index.*` so the `Sample.Index.Reader` protocol
/// (in this same target) can name the return type without
/// pulling in the full `SampleIndex` target's actor + schema +
/// writer surface. Callers that previously wrote
/// `Sample.Index.Database.FileSearchResult` now write
/// `Sample.Index.FileSearchResult`.
extension Sample.Index {
    public struct FileSearchResult: Sendable {
        public let projectId: String
        public let path: String
        public let filename: String
        public let snippet: String
        public let rank: Double

        public init(
            projectId: String,
            path: String,
            filename: String,
            snippet: String,
            rank: Double
        ) {
            self.projectId = projectId
            self.path = path
            self.filename = filename
            self.snippet = snippet
            self.rank = rank
        }
    }
}

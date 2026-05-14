import Foundation
import SharedConstants

// MARK: - Sample.Search.Query

/// Query parameters for sample-code searches against the SampleIndex database.
///
/// Previously declared inside `Sources/Services/ReadCommands/Sample.Search.Service.swift`.
/// Lifted to a foundation-layer value type so consumers (`SearchToolProvider`,
/// CLI commands, MCP tool surfaces) can hold a `Sample.Search.Query` value
/// without importing the full `Services` target.
///
/// `Sample.Search.Service` (the actor in Services that consumes this query
/// and runs it against a `Sample.Index.Reader`) keeps its existing
/// signature — only the type definition moved.
extension Sample.Search {
    public struct Query: Sendable {
        public let text: String
        public let framework: String?
        public let searchFiles: Bool
        public let limit: Int

        /// Optional platform filter (#233). When set together with
        /// `minVersion`, restricts results to projects whose
        /// `min_<platform>` column is non-NULL and lex-≤ the requested
        /// version. nil on either disables the filter.
        public let platform: String?
        public let minVersion: String?

        public init(
            text: String,
            framework: String? = nil,
            searchFiles: Bool = true,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit,
            platform: String? = nil,
            minVersion: String? = nil
        ) {
            self.text = text
            self.framework = framework
            self.searchFiles = searchFiles
            self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
            self.platform = platform
            self.minVersion = minVersion
        }
    }
}

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

        /// Optional single-platform filter (#233). When set together
        /// with `minVersion`, restricts results to projects whose
        /// `min_<platform>` column is non-NULL and lex-≤ the requested
        /// version. nil on either disables this filter. Kept for
        /// back-compat with the original (single-platform) call shape;
        /// new callers use the 5-field shape below.
        public let platform: String?
        public let minVersion: String?

        /// 5-field platform-minima filter (#732). When any is non-nil,
        /// AND-combines against `projects.min_<platform>` columns: a
        /// project must satisfy every set minimum to pass. Used by the
        /// MCP unified search + the fan-out path which both pass the
        /// caller-supplied `min_*` args as-is — no precedence-pick
        /// translation needed.
        public let minIOS: String?
        public let minMacOS: String?
        public let minTvOS: String?
        public let minWatchOS: String?
        public let minVisionOS: String?

        public init(
            text: String,
            framework: String? = nil,
            searchFiles: Bool = true,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit,
            platform: String? = nil,
            minVersion: String? = nil,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) {
            self.text = text
            self.framework = framework
            self.searchFiles = searchFiles
            self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
            self.platform = platform
            self.minVersion = minVersion
            self.minIOS = minIOS
            self.minMacOS = minMacOS
            self.minTvOS = minTvOS
            self.minWatchOS = minWatchOS
            self.minVisionOS = minVisionOS
        }
    }
}

import Foundation

extension Search {
    /// A source that returned empty due to a configuration error (#640).
    ///
    /// Used by `SmartQuery.answer` and `Services.UnifiedSearchService.searchAll`
    /// to flag sources that failed to open (schema mismatch / DB
    /// unopenable) so consumers (CLI text/markdown/JSON, MCP markdown
    /// response body) can prepend a `⚠ Schema mismatch` warning at the
    /// top of their output. Distinguishes "no apple-docs match for the
    /// query" from "apple-docs.db is unopenable" — both look like
    /// empty result sets to AI agents otherwise.
    ///
    /// `reason` is human-readable, suitable for direct emission. The
    /// canonical strings come from
    /// `Search.SmartQuery.classifyDegradation(_:)` and
    /// `Services.UnifiedSearchService.classifyDegradation(_:)` which
    /// share the same dispatch table.
    public struct DegradedSource: Sendable, Hashable, Codable {
        public let name: String
        public let reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }
}

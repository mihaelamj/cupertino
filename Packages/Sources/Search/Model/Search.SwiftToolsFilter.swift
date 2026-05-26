import Foundation

/// Swift-tools-version filter applied to package search (#225 Part A).
///
/// Orthogonal axis from `Search.AvailabilityFilter`: filters on the
/// authored Swift-compiler floor declared in `Package.swift` line 1
/// (`// swift-tools-version: X.Y`) rather than on platform deployment
/// targets. Issue body explicitly rejects deriving Swift from
/// `min_ios` (wrong-direction inference); this filter exists so a
/// query like "Vapor packages compatible with Swift 6" can resolve
/// against the authored declaration.
///
/// `minVersion` is the lower bound: a row passes when its
/// `swift_tools_version` is greater than or equal to the filter value
/// (lexicographic compare on the dotted-decimal string — fine for
/// current Swift majors 4.x through 6.x where minor widths are
/// uniform). Rows whose `swift_tools_version` is NULL are dropped
/// when the filter is active (no declaration = unknown = excluded
/// from a Swift-version-specific query, same semantics as
/// `Search.AvailabilityFilter`'s NULL handling for `min_<platform>`).
extension Search {
    public struct SwiftToolsFilter: Sendable {
        /// Minimum acceptable swift-tools-version. Format: `X.Y` (e.g.
        /// `"5.7"`, `"6.0"`). The parser truncates patch versions on
        /// the indexer side so the stored column is always
        /// major.minor; callers should pass the same shape.
        public let minVersion: String

        public init(minVersion: String) {
            self.minVersion = minVersion
        }
    }
}

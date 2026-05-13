import Foundation

/// Platform-version availability filter applied to package search.
///
/// Lifted out of `Search.PackageQuery.AvailabilityFilter` (nested
/// inside the PackageQuery actor in the Search target) to top-level
/// `Search.AvailabilityFilter` in SearchModels so consumers can
/// construct and pass it without taking a behavioural dependency on
/// the Search target.
///
/// `platform` is one of `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS`
/// (case-insensitive). `minVersion` is a dotted decimal like `"16.0"`
/// or `"10.15"`. Both must be set to filter; otherwise the flag is
/// ignored. NULL `min_<platform>` rows in `package_metadata` are
/// dropped when a filter is active (no annotation = unknown =
/// excluded from a platform-specific query).
extension Search {
    public struct AvailabilityFilter: Sendable {
        public let platform: String
        public let minVersion: String

        public init(platform: String, minVersion: String) {
            self.platform = platform
            self.minVersion = minVersion
        }
    }
}

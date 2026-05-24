import Foundation

// MARK: - Search.FrameworkAvailability

extension Search {
    /// Minimum platform versions for a framework. Returned by
    /// `Search.Database.getFrameworkAvailability(framework:)` so strategies
    /// can stamp per-framework minimum versions onto pages that don't
    /// carry their own (Apple sample-code zips, Apple Archive guides, etc.).
    ///
    /// Lifted from a previous nested location in the SearchAPI target's
    /// `Search.SearchResult.swift` up to `SearchModels` by epic #893's
    /// child #897, so the `Search.Database` read protocol can carry the
    /// `getFrameworkAvailability` requirement without taking a
    /// behavioural dependency on the concrete SearchAPI target.
    public struct FrameworkAvailability: Sendable {
        public let minIOS: String?
        public let minMacOS: String?
        public let minTvOS: String?
        public let minWatchOS: String?
        public let minVisionOS: String?

        public init(
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) {
            self.minIOS = minIOS
            self.minMacOS = minMacOS
            self.minTvOS = minTvOS
            self.minWatchOS = minWatchOS
            self.minVisionOS = minVisionOS
        }

        /// Empty availability (no platform data).
        public static let empty = FrameworkAvailability()
    }
}

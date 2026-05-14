import Foundation

/// Lightweight platform availability for search results.
///
/// Lifted out of the Search target into SearchModels so Services formatters
/// (and any future consumer) can deserialize `Search.Result.availability`
/// without taking a behavioural dependency on the Search target.
extension Search {
    public struct PlatformAvailability: Codable, Sendable, Hashable {
        public let name: String
        public let introducedAt: String?
        public let deprecated: Bool
        public let unavailable: Bool
        public let beta: Bool

        public init(
            name: String,
            introducedAt: String? = nil,
            deprecated: Bool = false,
            unavailable: Bool = false,
            beta: Bool = false
        ) {
            self.name = name
            self.introducedAt = introducedAt
            self.deprecated = deprecated
            self.unavailable = unavailable
            self.beta = beta
        }
    }
}

import AvailabilityModels
import Foundation

// MARK: - API Response Models (#905)

/// Internal JSON-DTO for Apple's /tutorials/data/documentation API.
/// Stays in the Availability producer target rather than
/// AvailabilityModels because it's a transport-shape concern, not a
/// public domain value-type that downstream consumers need. Pre-#905
/// this lived in `Availability.Platform.swift`; the value types
/// (Platform / Info) moved to AvailabilityModels while this internal
/// DTO stayed behind.
extension Availability {
    struct APIResponse: Codable {
        let metadata: Metadata?

        struct Metadata: Codable {
            let platforms: [PlatformInfo]?
        }

        struct PlatformInfo: Codable {
            let name: String
            let introducedAt: String?
            let deprecated: Bool?
            let deprecatedAt: String?
            let unavailable: Bool?
            let beta: Bool?

            func toPlatform() -> Availability.Platform {
                Availability.Platform(
                    name: name,
                    introducedAt: introducedAt,
                    deprecated: deprecated ?? false,
                    deprecatedAt: deprecatedAt,
                    unavailable: unavailable ?? false,
                    beta: beta ?? false
                )
            }
        }
    }
}

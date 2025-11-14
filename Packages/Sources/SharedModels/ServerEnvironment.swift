import Foundation

/// Server environment identifier
/// Used by both ApiClient (for server selection) and BetaSettings (for user configuration)
/// The actual URL resolution is handled by ApiClient using OpenAPI-generated servers
public enum ServerEnvironment: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    case staging
    case production

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local:
            return "Local Development"
        case .staging:
            return "Staging Server"
        case .production:
            return "Production"
        }
    }
}

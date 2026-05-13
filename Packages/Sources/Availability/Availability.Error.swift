import Foundation

// MARK: - Availability Errors

extension Availability {
    /// Errors that can occur during availability fetching
    public enum Error: Swift.Error, LocalizedError, Sendable {
        /// Network request failed
        case networkError(Swift.Error)

        /// Request timed out
        case timeout

        /// API returned 404 (symbol not found)
        case notFound(String)

        /// Invalid response from API
        case invalidResponse

        /// Rate limited by API
        case rateLimited

        /// No documentation directory found
        case noDocumentationFound

        /// Failed to parse JSON
        case jsonParseError(Swift.Error)

        /// Failed to write updated file
        case writeError(Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .timeout:
                return "Request timed out"
            case .notFound(let symbol):
                return "Symbol not found: \(symbol)"
            case .invalidResponse:
                return "Invalid response from Apple API"
            case .rateLimited:
                return "Rate limited by Apple API"
            case .noDocumentationFound:
                return "No documentation directory found"
            case .jsonParseError(let error):
                return "JSON parse error: \(error.localizedDescription)"
            case .writeError(let error):
                return "Failed to write file: \(error.localizedDescription)"
            }
        }
    }
}

import Foundation

// MARK: - GitHub Fetcher Error

extension RemoteSync.GitHubFetcher {
    /// Errors from GitHub fetcher
    public enum Error: Swift.Error, Sendable, CustomStringConvertible {
        case invalidResponse(url: URL)
        case notFound(url: URL)
        case rateLimited
        case httpError(statusCode: Int, url: URL)
        case invalidEncoding(path: String)

        public var description: String {
            switch self {
            case let .invalidResponse(url):
                return "Invalid response from \(url)"
            case let .notFound(url):
                return "Not found: \(url)"
            case .rateLimited:
                return "GitHub API rate limit exceeded. Try again later or use authentication."
            case let .httpError(statusCode, url):
                return "HTTP \(statusCode) from \(url)"
            case let .invalidEncoding(path):
                return "Invalid UTF-8 encoding in file: \(path)"
            }
        }
    }
}

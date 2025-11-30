import Foundation

// MARK: - JSON Content Fetcher

/// Fetches JSON content from Apple's documentation API
/// Uses URLSession for direct HTTP requests, avoiding WKWebView memory issues
extension JSONCrawler {
    public struct JSONContentFetcher: ContentFetcher, @unchecked Sendable {
        public typealias RawContent = Data

        private let session: URLSession
        private let timeout: TimeInterval

        public init(timeout: TimeInterval = 30) {
            self.timeout = timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            session = URLSession(configuration: config)
        }

        public func fetch(url: URL) async throws -> Data {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JSONFetcherError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw JSONFetcherError.httpError(statusCode: httpResponse.statusCode)
            }

            return data
        }
    }
}

// MARK: - JSON Fetcher Errors

public enum JSONFetcherError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case let .httpError(statusCode):
            return "HTTP error: \(statusCode)"
        case .invalidJSON:
            return "Invalid JSON data"
        }
    }
}

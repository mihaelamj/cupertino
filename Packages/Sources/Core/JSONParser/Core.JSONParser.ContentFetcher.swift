import CoreProtocols
import Foundation

// MARK: - JSON Content Fetcher

/// Fetches JSON content from Apple's documentation API
/// Uses URLSession for direct HTTP requests, avoiding WKWebView memory issues
extension Core.JSONParser {
    public struct ContentFetcher: Core.Protocols.ContentFetcher, @unchecked Sendable {
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

        public func fetch(url: URL) async throws -> Core.Protocols.FetchResult<Data> {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw Error.httpError(statusCode: httpResponse.statusCode)
            }

            let finalURL = response.url ?? url
            return Core.Protocols.FetchResult(content: data, url: finalURL)
        }
    }
}

// MARK: - JSON Content Fetcher Errors

extension Core.JSONParser.ContentFetcher {
    public enum Error: Swift.Error, LocalizedError, Sendable {
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
}

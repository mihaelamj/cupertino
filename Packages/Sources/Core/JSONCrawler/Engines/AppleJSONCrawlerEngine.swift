import Foundation
import Shared

// MARK: - Apple JSON Crawler Engine

/// Complete crawler engine for Apple documentation using JSON API
/// Uses JSONContentFetcher for fetching and AppleJSONToMarkdown for transformation
extension JSONCrawler {
    public final class AppleJSONCrawlerEngine: CrawlerEngine, @unchecked Sendable {
        private let fetcher: JSONContentFetcher

        public init(timeout: TimeInterval = 30) {
            fetcher = JSONContentFetcher(timeout: timeout)
        }

        public func crawl(url: URL) async throws -> TransformResult {
            // Convert documentation URL to JSON API URL
            guard let jsonURL = apiURL(from: url) else {
                throw JSONCrawlerError.invalidURL
            }

            // Fetch JSON content
            let data = try await fetcher.fetch(url: jsonURL)

            // Create structured page (includes full content)
            let structuredPage = AppleJSONToMarkdown.toStructuredPage(data, url: url)

            // Also generate markdown (optional output format)
            guard let markdown = AppleJSONToMarkdown.convert(data, url: url) else {
                throw JSONCrawlerError.transformFailed
            }

            // Extract links using AppleJSONToMarkdown
            let links = AppleJSONToMarkdown.extractLinks(from: data)

            // Extract metadata
            let metadata = extractMetadata(from: data)

            return TransformResult(
                markdown: markdown,
                links: links,
                metadata: metadata,
                structuredPage: structuredPage
            )
        }

        public func apiURL(from documentationURL: URL) -> URL? {
            // Use AppleJSONToMarkdown's URL conversion
            AppleJSONToMarkdown.jsonAPIURL(from: documentationURL)
        }

        // MARK: - Private Helpers

        private func extractMetadata(from data: Data) -> TransformMetadata? {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = json["metadata"] as? [String: Any]
            else {
                return nil
            }

            let title = metadata["title"] as? String
            let role = metadata["role"] as? String

            // Extract platforms
            var platforms: [String]?
            var isDeprecated = false
            if let platformsArray = metadata["platforms"] as? [[String: Any]] {
                platforms = platformsArray.compactMap { $0["name"] as? String }
                isDeprecated = platformsArray.contains { $0["deprecated"] as? Bool == true }
            }

            // Extract framework from module
            var framework: String?
            if let modules = metadata["modules"] as? [[String: Any]],
               let firstModule = modules.first {
                framework = firstModule["name"] as? String
            }

            return TransformMetadata(
                title: title,
                description: role,
                framework: framework,
                platforms: platforms,
                isDeprecated: isDeprecated
            )
        }
    }
}

// MARK: - JSON Crawler Errors

public enum JSONCrawlerError: Error, LocalizedError {
    case invalidURL
    case transformFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid documentation URL - cannot convert to JSON API URL"
        case .transformFailed:
            return "Failed to transform JSON content to Markdown"
        }
    }
}

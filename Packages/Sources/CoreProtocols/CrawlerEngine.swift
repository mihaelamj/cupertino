import Foundation

// MARK: - Crawler Engine Protocol

/// Protocol combining content fetching and transformation
/// This is the main interface for crawling implementations
public protocol CrawlerEngine: Sendable {
    /// Crawl a URL and return Markdown content with discovered links
    /// - Parameter url: The URL to crawl
    /// - Returns: Transform result containing markdown and links
    func crawl(url: URL) async throws -> TransformResult

    /// Get the API URL for a given documentation URL
    /// Some engines (like JSON API) need to transform the URL before fetching
    /// - Parameter documentationURL: The public documentation URL
    /// - Returns: The URL to actually fetch from, or nil if not applicable
    func apiURL(from documentationURL: URL) -> URL?

    /// Recycle resources to free memory
    func recycle()

    /// Get current memory usage in MB
    func getMemoryUsageMB() -> Double
}

// MARK: - Default Implementations

public extension CrawlerEngine {
    func apiURL(from documentationURL: URL) -> URL? {
        // Default: use the URL as-is
        documentationURL
    }

    func recycle() {
        // Default: no-op
    }

    func getMemoryUsageMB() -> Double {
        0
    }
}

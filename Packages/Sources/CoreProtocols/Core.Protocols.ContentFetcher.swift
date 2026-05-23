import Foundation

// MARK: - Content Fetcher Protocol

/// Protocol for fetching raw content from a URL
/// Implementations include WKWebView (HTML), JSON API, URLSession (HTML), etc.
extension Core.Protocols {
    public protocol ContentFetcher: Sendable {
        /// The type of raw content this fetcher produces
        associatedtype RawContent: Sendable

        /// Fetch raw content from the given URL
        /// - Parameter url: The URL to fetch content from
        /// - Returns: A FetchResult containing the raw content and the post-redirect final URL
        func fetch(url: URL) async throws -> FetchResult<RawContent>

        /// Optional: Recycle resources to free memory
        /// Default implementation does nothing
        func recycle()

        /// Optional: Get current memory usage in MB
        /// Default implementation returns 0
        func getMemoryUsageMB() -> Double
    }
}

// MARK: - Default Implementations

public extension Core.Protocols.ContentFetcher {
    func recycle() {
        // Default: no-op
    }

    func getMemoryUsageMB() -> Double {
        // Default: return 0
        0
    }
}

// MARK: - String-typed Content Fetcher (#903 seam)

/// Non-generic counterpart to `ContentFetcher` specialised for `String`
/// content. Used by `Crawler.HTTPFetcherFactory` so the Crawler producer
/// can name the existential `any StringContentFetcher` without needing
/// generic-existential primary-associated-type machinery (which Swift
/// does not synthesise on protocols declared inside an `extension`
/// block). Concretes that already conform `ContentFetcher` with
/// `RawContent == String` (`Crawler.WebKit.ContentFetcher`) get this
/// conformance for free via the extension below.
extension Core.Protocols {
    public protocol StringContentFetcher: Sendable {
        func fetch(url: URL) async throws -> FetchResult<String>
        func recycle()
        func getMemoryUsageMB() -> Double
    }
}

public extension Core.Protocols.StringContentFetcher {
    func recycle() {
        // Default: no-op
    }

    func getMemoryUsageMB() -> Double {
        0
    }
}

// MARK: - Fetch Result

/// Result of a content fetch operation
extension Core.Protocols {
    public struct FetchResult<Content: Sendable>: Sendable {
        public let content: Content
        public let url: URL
        public let responseHeaders: [String: String]?

        public init(content: Content, url: URL, responseHeaders: [String: String]? = nil) {
            self.content = content
            self.url = url
            self.responseHeaders = responseHeaders
        }
    }
}

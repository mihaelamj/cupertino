import Foundation
#if canImport(WebKit)
import WebKit
#endif

// MARK: - WKWeb Crawler Engine

/// Complete crawler engine using WKWebView for JavaScript-rendered pages
/// Uses WKWebContentFetcher for fetching and HTMLToMarkdown for transformation
extension WKWebCrawler {
    #if canImport(WebKit)
    @MainActor
    public final class WKWebCrawlerEngine: @preconcurrency CrawlerEngine {
        private let fetcher: WKWebContentFetcher

        public init(
            pageLoadTimeout: Duration = .seconds(30),
            javascriptWaitTime: Duration = .seconds(5)
        ) {
            fetcher = WKWebContentFetcher(
                pageLoadTimeout: pageLoadTimeout,
                javascriptWaitTime: javascriptWaitTime
            )
        }

        public func crawl(url: URL) async throws -> TransformResult {
            // Fetch HTML content via WKWebView
            let html = try await fetcher.fetch(url: url)

            // Transform to markdown using HTMLToMarkdown
            let markdown = HTMLToMarkdown.convert(html, url: url)

            // Extract links from HTML
            let links = extractLinks(from: html, baseURL: url)

            // Extract metadata from HTML
            let metadata = extractMetadata(from: html)

            return TransformResult(
                markdown: markdown,
                links: links,
                metadata: metadata
            )
        }

        public func apiURL(from documentationURL: URL) -> URL? {
            // WebKit fetcher uses the URL as-is
            documentationURL
        }

        public func recycle() {
            fetcher.recycle()
        }

        public func getMemoryUsageMB() -> Double {
            fetcher.getMemoryUsageMB()
        }

        // MARK: - Private Helpers

        private func extractLinks(from html: String, baseURL: URL) -> [URL] {
            var links: [URL] = []
            let pattern = #"<a[^>]+href=["']([^"']+)["'][^>]*>"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = html as NSString
                let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
                for match in matches where match.numberOfRanges >= 2 {
                    let hrefRange = match.range(at: 1)
                    let href = nsString.substring(with: hrefRange)
                    if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                        links.append(url)
                    }
                }
            }
            return links
        }

        private func extractMetadata(from html: String) -> TransformMetadata? {
            var title: String?
            var description: String?

            // Extract title
            let titlePattern = "<title[^>]*>([^<]*)</title>"
            if let regex = try? NSRegularExpression(pattern: titlePattern, options: .caseInsensitive) {
                let nsString = html as NSString
                if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsString.length)),
                   match.numberOfRanges >= 2 {
                    title = nsString.substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Extract meta description
            let descPattern = #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["']"#
            if let regex = try? NSRegularExpression(pattern: descPattern, options: .caseInsensitive) {
                let nsString = html as NSString
                if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsString.length)),
                   match.numberOfRanges >= 2 {
                    description = nsString.substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard title != nil || description != nil else {
                return nil
            }

            return TransformMetadata(
                title: title,
                description: description
            )
        }
    }
    #endif
}

// MARK: - WebKit Crawler Errors

public enum WebKitCrawlerError: Error, LocalizedError {
    case transformFailed
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .transformFailed:
            return "Failed to transform HTML content to Markdown"
        case .unsupportedPlatform:
            return "WKWebView-based crawling is not available on this platform"
        }
    }
}

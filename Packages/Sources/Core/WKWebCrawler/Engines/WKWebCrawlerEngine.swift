import Foundation
import SharedCore
#if canImport(WebKit)
import CoreProtocols
import SharedConstants
import WebKit
#endif

// MARK: - WKWeb Crawler Engine

/// Complete crawler engine using WKWebView for JavaScript-rendered pages
/// Uses WKWebCrawler.ContentFetcher for fetching and Core.Parser.HTML for transformation
extension WKWebCrawler {
    #if canImport(WebKit)
    @MainActor
    public final class Engine: @preconcurrency Core.Protocols.CrawlerEngine {
        private let fetcher: WKWebCrawler.ContentFetcher

        public init(
            pageLoadTimeout: Duration = Shared.Constants.Timeout.pageLoad,
            javascriptWaitTime: Duration = Shared.Constants.Timeout.javascriptWait
        ) {
            fetcher = WKWebCrawler.ContentFetcher(
                pageLoadTimeout: pageLoadTimeout,
                javascriptWaitTime: javascriptWaitTime
            )
        }

        public func crawl(url: URL) async throws -> Core.Protocols.TransformResult {
            // Fetch HTML content via WKWebView; result.url is the post-redirect final URL
            let result = try await fetcher.fetch(url: url)
            let html = result.content
            let finalURL = result.url

            // Transform to markdown using Core.Parser.HTML
            let markdown = Core.Parser.HTML.convert(html, url: finalURL)

            // Extract links from HTML
            let links = extractLinks(from: html, baseURL: finalURL)

            // Extract metadata from HTML
            let metadata = extractMetadata(from: html)

            return Core.Protocols.TransformResult(
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

        private func extractMetadata(from html: String) -> Core.Protocols.TransformMetadata? {
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

            return Core.Protocols.TransformMetadata(
                title: title,
                description: description
            )
        }
    }
    #endif
}

// MARK: - WebKit Crawler Errors

extension WKWebCrawler {
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
}

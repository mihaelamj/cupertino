import Foundation
import Logging
import Shared

#if canImport(WebKit)
import WebKit
#endif

// MARK: - HIG Crawler

// swiftlint:disable type_body_length
// Justification: HIGCrawler is a self-contained crawler module.
// Contains page discovery, HTML parsing, markdown conversion, and file saving.
// Splitting would scatter related functionality and reduce cohesion.

/// Crawls Apple's Human Interface Guidelines
/// The HIG website is a JavaScript SPA, requiring WKWebView-based crawling
extension Core {
    @MainActor
    public final class HIGCrawler {
        private let outputDirectory: URL
        private let forceRecrawl: Bool
        private let maxPages: Int

        #if canImport(WebKit)
        private var fetcher: WKWebCrawler.WKWebContentFetcher?
        #endif

        public init(
            outputDirectory: URL,
            forceRecrawl: Bool = false,
            maxPages: Int = 500
        ) {
            self.outputDirectory = outputDirectory
            self.forceRecrawl = forceRecrawl
            self.maxPages = maxPages
        }

        // MARK: - Public API

        /// Crawl Human Interface Guidelines
        public func crawl(
            onProgress: (@Sendable (HIGProgress) -> Void)? = nil
        ) async throws -> HIGStatistics {
            var stats = HIGStatistics(startTime: Date())

            logInfo("Starting Human Interface Guidelines crawler")
            logInfo("   Output: \(outputDirectory.path)")
            logInfo("   Max pages: \(maxPages)")

            // Create output directory
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            #if canImport(WebKit)
            // Initialize content fetcher with HIG-specific wait time
            fetcher = WKWebCrawler.WKWebContentFetcher(
                pageLoadTimeout: Shared.Constants.Timeout.pageLoad,
                javascriptWaitTime: Shared.Constants.Timeout.higJavascriptWait
            )

            // Start from HIG root
            let rootURL = URL(string: Shared.Constants.BaseURL.appleHIG)!

            // Discover all HIG pages
            logInfo("Discovering HIG pages...")
            let pages = try await discoverPages(from: rootURL, stats: &stats)
            logInfo("Found \(pages.count) pages to crawl")

            // Crawl each page
            for (index, page) in pages.prefix(maxPages).enumerated() {
                do {
                    try await crawlPage(page, stats: &stats)

                    // Progress callback
                    if let onProgress {
                        let progress = HIGProgress(
                            currentPage: index + 1,
                            totalPages: min(pages.count, maxPages),
                            currentItem: page.title,
                            stats: stats
                        )
                        onProgress(progress)
                    }

                    // Rate limiting
                    try await Task.sleep(for: Shared.Constants.Delay.archivePage)

                    // Recycle WKWebView every N pages to prevent memory buildup
                    if (index + 1) % Shared.Constants.Interval.webViewRecycleEvery == 0 {
                        fetcher?.recycle()
                        logInfo("♻️ Recycled WKWebView at page \(index + 1)")
                    }
                } catch {
                    stats.errors += 1
                    logError("Failed to crawl page \(page.title): \(error)")

                    // Recycle on error to recover from potential WebView issues
                    fetcher?.recycle()
                }
            }

            // Cleanup
            fetcher = nil
            #else
            logError("WebKit not available - HIG crawler requires macOS")
            throw HIGCrawlerError.webKitNotAvailable
            #endif

            stats.endTime = Date()

            logInfo("\nCrawl completed!")
            logStatistics(stats)

            return stats
        }

        // MARK: - Private Methods

        #if canImport(WebKit)
        private func discoverPages(
            from rootURL: URL,
            stats: inout HIGStatistics
        ) async throws -> [HIGPage] {
            var pages: [HIGPage] = []
            var visited: Set<String> = []
            var queue: [URL] = [rootURL]

            // BFS to discover HIG pages
            while !queue.isEmpty, pages.count < maxPages {
                let url = queue.removeFirst()
                let urlString = url.absoluteString

                guard !visited.contains(urlString) else { continue }
                visited.insert(urlString)

                // Only process HIG URLs
                guard urlString.contains("/design/human-interface-guidelines") else { continue }

                // Load page and extract links
                logInfo("Loading: \(url.lastPathComponent.isEmpty ? "root" : url.lastPathComponent)")
                let html: String
                do {
                    html = try await loadPage(url: url)
                } catch {
                    logError("Failed to load \(url): \(error)")
                    continue
                }

                // Extract title from page
                let title = extractTitle(from: html) ?? url.lastPathComponent

                // Determine category from URL path
                let category = extractCategory(from: url)

                // Determine platforms from content
                let platforms = extractPlatforms(from: html)

                let page = HIGPage(
                    url: url,
                    title: title,
                    category: category,
                    platforms: platforms
                )
                pages.append(page)

                // Extract links to other HIG pages
                let links = extractHIGLinks(from: html, baseURL: url)
                for link in links where !visited.contains(link.absoluteString) {
                    queue.append(link)
                }
            }

            return pages
        }

        private func loadPage(url: URL) async throws -> String {
            guard let fetcher else {
                throw HIGCrawlerError.webViewNotInitialized
            }

            return try await fetcher.fetch(url: url)
        }

        private func crawlPage(_ page: HIGPage, stats: inout HIGStatistics) async throws {
            // Determine output path
            let filename = sanitizeFilename(page.title) + ".md"
            let categoryDir = outputDirectory.appendingPathComponent(page.category.rawValue)

            do {
                try FileManager.default.createDirectory(at: categoryDir, withIntermediateDirectories: true)
            } catch {
                logError("Failed to create directory \(categoryDir.path): \(error)")
                throw error
            }

            let outputPath = categoryDir.appendingPathComponent(filename)

            // Check if already crawled
            let isNew = !FileManager.default.fileExists(atPath: outputPath.path)
            if !isNew, !forceRecrawl {
                stats.skippedPages += 1
                logInfo("⏭️ Skipped (exists): \(filename)")
                return
            }

            // Load page content
            logInfo("📥 Loading: \(page.title)")
            let html = try await loadPage(url: page.url)

            // Convert to markdown
            let markdown = convertToMarkdown(html, page: page)

            // Save
            do {
                try markdown.write(to: outputPath, atomically: true, encoding: .utf8)
                logInfo("💾 Saved: \(outputPath.path)")
            } catch {
                logError("Failed to save \(outputPath.path): \(error)")
                throw error
            }

            if isNew {
                stats.newPages += 1
            } else {
                stats.updatedPages += 1
            }

            stats.totalPages += 1
        }
        #endif

        private func extractTitle(from html: String) -> String? {
            // Try to extract from <title> tag
            let titlePattern = #"<title[^>]*>([^<]+)</title>"#
            guard let regex = try? NSRegularExpression(pattern: titlePattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html)
            else {
                return nil
            }

            var title = String(html[range])
            // Clean up title
            title = title.replacingOccurrences(of: " - Human Interface Guidelines", with: "")
            title = title.replacingOccurrences(of: " | Apple Developer Documentation", with: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func extractCategory(from url: URL) -> HIGCategory {
            let path = url.path.lowercased()

            if path.contains("/foundations") {
                return .foundations
            } else if path.contains("/patterns") {
                return .patterns
            } else if path.contains("/components") {
                return .components
            } else if path.contains("/technologies") {
                return .technologies
            } else if path.contains("/inputs") {
                return .inputs
            } else {
                return .general
            }
        }

        private func extractPlatforms(from html: String) -> [HIGPlatform] {
            var platforms: [HIGPlatform] = []
            let content = html.lowercased()

            if content.contains("ios") || content.contains("iphone") || content.contains("ipad") {
                platforms.append(.iOS)
            }
            if content.contains("macos") || content.contains("mac ") {
                platforms.append(.macOS)
            }
            if content.contains("watchos") || content.contains("apple watch") {
                platforms.append(.watchOS)
            }
            if content.contains("visionos") || content.contains("apple vision") {
                platforms.append(.visionOS)
            }
            if content.contains("tvos") || content.contains("apple tv") {
                platforms.append(.tvOS)
            }

            return platforms.isEmpty ? [.all] : platforms
        }

        private func extractHIGLinks(from html: String, baseURL: URL) -> [URL] {
            var links: [URL] = []

            // Extract href values
            let hrefPattern = #"href=[\"']([^\"']*human-interface-guidelines[^\"']*)[\"']"#
            guard let regex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive) else {
                return links
            }

            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let href = String(html[range])

                // Resolve relative URLs
                if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                    // Only include HIG URLs
                    if url.host == "developer.apple.com",
                       url.path.contains("/design/human-interface-guidelines") {
                        // Remove fragment
                        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                        components?.fragment = nil
                        if let cleanURL = components?.url {
                            links.append(cleanURL)
                        }
                    }
                }
            }

            return Array(Set(links))
        }

        private func convertToMarkdown(_ html: String, page: HIGPage) -> String {
            var lines: [String] = []

            // YAML front matter
            lines.append("---")
            lines.append("title: \"\(escapeYAML(page.title))\"")
            lines.append("category: \"\(page.category.rawValue)\"")
            lines.append("platforms: [\(page.platforms.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))]")
            lines.append("url: \"\(page.url.absoluteString)\"")
            lines.append("source: hig")
            lines.append("---")
            lines.append("")

            // Title
            lines.append("# \(page.title)")
            lines.append("")

            // Category badge
            lines.append("> **Category:** \(page.category.displayName)")
            lines.append("> **Platforms:** \(page.platforms.map(\.displayName).joined(separator: ", "))")
            lines.append("")

            // Convert HTML content to markdown
            let content = extractMainContent(from: html)
            let markdownContent = htmlToMarkdown(content)
            lines.append(markdownContent)

            return lines.joined(separator: "\n")
        }

        private func extractMainContent(from html: String) -> String {
            // Try to extract main content area
            let patterns = [
                #"<main[^>]*>([\s\S]*?)</main>"#,
                #"<article[^>]*>([\s\S]*?)</article>"#,
                #"<div[^>]*class=[\"'][^\"']*content[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#,
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                      let range = Range(match.range(at: 1), in: html)
                else {
                    continue
                }
                return String(html[range])
            }

            return html
        }

        // swiftlint:disable:next function_body_length
        // Justification: HTML to Markdown conversion requires many regex replacements.
        // Splitting would obscure the sequential transformation pipeline.
        private func htmlToMarkdown(_ html: String) -> String {
            var result = html

            // Remove script and style tags
            result = result.replacingOccurrences(
                of: #"<script[^>]*>[\s\S]*?</script>"#,
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<style[^>]*>[\s\S]*?</style>"#,
                with: "",
                options: .regularExpression
            )

            // Headers
            for level in 1...6 {
                let hashes = String(repeating: "#", count: level)
                result = result.replacingOccurrences(
                    of: #"<h\#(level)[^>]*>(.*?)</h\#(level)>"#,
                    with: "\(hashes) $1\n",
                    options: .regularExpression
                )
            }

            // Paragraphs
            result = result.replacingOccurrences(
                of: #"<p[^>]*>(.*?)</p>"#,
                with: "$1\n\n",
                options: .regularExpression
            )

            // Bold and italic
            result = result.replacingOccurrences(
                of: #"<strong[^>]*>(.*?)</strong>"#,
                with: "**$1**",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<b[^>]*>(.*?)</b>"#,
                with: "**$1**",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<em[^>]*>(.*?)</em>"#,
                with: "*$1*",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<i[^>]*>(.*?)</i>"#,
                with: "*$1*",
                options: .regularExpression
            )

            // Code
            result = result.replacingOccurrences(
                of: #"<code[^>]*>(.*?)</code>"#,
                with: "`$1`",
                options: .regularExpression
            )

            // Links
            result = result.replacingOccurrences(
                of: #"<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>"#,
                with: "[$2]($1)",
                options: .regularExpression
            )

            // Lists
            result = result.replacingOccurrences(
                of: #"<li[^>]*>(.*?)</li>"#,
                with: "- $1\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"</?[ou]l[^>]*>"#,
                with: "\n",
                options: .regularExpression
            )

            // Remove remaining HTML tags
            result = result.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )

            // Decode HTML entities
            result = decodeHTMLEntities(result)

            // Clean up whitespace
            result = result.replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)

            return result
        }

        private func decodeHTMLEntities(_ text: String) -> String {
            var result = text
            let entities: [(String, String)] = [
                ("&amp;", "&"),
                ("&lt;", "<"),
                ("&gt;", ">"),
                ("&quot;", "\""),
                ("&apos;", "'"),
                ("&#39;", "'"),
                ("&nbsp;", " "),
                ("&mdash;", "—"),
                ("&ndash;", "–"),
                ("&hellip;", "..."),
            ]

            for (entity, replacement) in entities {
                result = result.replacingOccurrences(of: entity, with: replacement)
            }

            return result
        }

        private func escapeYAML(_ text: String) -> String {
            text.replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
        }

        private func sanitizeFilename(_ name: String) -> String {
            let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
            return name.components(separatedBy: invalidChars).joined(separator: "-")
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            #if canImport(WebKit)
            let memoryMB = fetcher?.getMemoryUsageMB() ?? 0
            let memoryMsg = "\(String(format: "%.1f", memoryMB))MB | \(message)"
            Log.info(memoryMsg, category: .hig)
            #else
            Log.info(message, category: .hig)
            #endif
        }

        private func logError(_ message: String) {
            Log.error("Error: \(message)", category: .hig)
        }

        private func logStatistics(_ stats: HIGStatistics) {
            let messages = [
                "Statistics:",
                "   Total pages: \(stats.totalPages)",
                "   New: \(stats.newPages)",
                "   Updated: \(stats.updatedPages)",
                "   Skipped: \(stats.skippedPages)",
                "   Errors: \(stats.errors)",
                stats.duration.map { "   Duration: \(Int($0))s" } ?? "",
                "",
                "Output: \(outputDirectory.path)",
            ]

            for message in messages where !message.isEmpty {
                Log.info(message, category: .hig)
            }
        }
    }
}

// swiftlint:enable type_body_length

// MARK: - Models

/// Represents an HIG page to crawl
public struct HIGPage: Sendable {
    public let url: URL
    public let title: String
    public let category: HIGCategory
    public let platforms: [HIGPlatform]

    public init(url: URL, title: String, category: HIGCategory, platforms: [HIGPlatform]) {
        self.url = url
        self.title = title
        self.category = category
        self.platforms = platforms
    }
}

/// HIG content categories
public enum HIGCategory: String, Sendable, CaseIterable {
    case foundations
    case patterns
    case components
    case technologies
    case inputs
    case general

    public var displayName: String {
        switch self {
        case .foundations: return "Foundations"
        case .patterns: return "Patterns"
        case .components: return "Components"
        case .technologies: return "Technologies"
        case .inputs: return "Inputs"
        case .general: return "General"
        }
    }
}

/// HIG platforms
public enum HIGPlatform: String, Sendable, CaseIterable {
    case iOS
    case macOS
    case watchOS
    case visionOS
    case tvOS
    case all

    public var displayName: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        case .watchOS: return "watchOS"
        case .visionOS: return "visionOS"
        case .tvOS: return "tvOS"
        case .all: return "All Platforms"
        }
    }
}

// MARK: - Statistics

public struct HIGStatistics: Sendable {
    public var totalPages: Int = 0
    public var newPages: Int = 0
    public var updatedPages: Int = 0
    public var skippedPages: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalPages: Int = 0,
        newPages: Int = 0,
        updatedPages: Int = 0,
        skippedPages: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalPages = totalPages
        self.newPages = newPages
        self.updatedPages = updatedPages
        self.skippedPages = skippedPages
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}

// MARK: - Progress

public struct HIGProgress: Sendable {
    public let currentPage: Int
    public let totalPages: Int
    public let currentItem: String
    public let stats: HIGStatistics

    public var percentage: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage) / Double(totalPages) * 100
    }
}

// MARK: - Errors

public enum HIGCrawlerError: Error, LocalizedError {
    case invalidResponse(URL)
    case webKitNotAvailable
    case webViewNotInitialized

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let url):
            return "Invalid response from \(url)"
        case .webKitNotAvailable:
            return "WebKit not available - HIG crawler requires macOS"
        case .webViewNotInitialized:
            return "WebView not initialized"
        }
    }
}

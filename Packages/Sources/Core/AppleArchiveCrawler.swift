import Foundation
import Logging
import Shared

// MARK: - Apple Archive Crawler

/// Crawls Apple's archived documentation (static HTML pages)
/// These are the pre-2016 guides that are no longer updated but still valuable
extension Core {
    @MainActor
    public final class AppleArchiveCrawler {
        private let outputDirectory: URL
        private let guides: [ArchiveGuideInfo]
        private let forceRecrawl: Bool

        public init(
            outputDirectory: URL,
            guides: [ArchiveGuideInfo],
            forceRecrawl: Bool = false
        ) {
            self.outputDirectory = outputDirectory
            self.guides = guides
            self.forceRecrawl = forceRecrawl
        }

        /// Convenience initializer for backward compatibility (uses empty framework)
        public convenience init(
            outputDirectory: URL,
            guideURLs: [URL],
            forceRecrawl: Bool = false
        ) {
            let guides = guideURLs.map { ArchiveGuideInfo(url: $0, framework: "") }
            self.init(outputDirectory: outputDirectory, guides: guides, forceRecrawl: forceRecrawl)
        }

        // MARK: - Public API

        /// Crawl all specified archive guides
        public func crawl(
            onProgress: (@Sendable (ArchiveProgress) -> Void)? = nil
        ) async throws -> ArchiveStatistics {
            var stats = ArchiveStatistics(startTime: Date())

            logInfo("Starting Apple Archive crawler")
            logInfo("   Output: \(outputDirectory.path)")
            logInfo("   Guides: \(guides.count)")

            // Create output directory
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            var totalPages = 0
            var currentGuide = 0

            for guide in guides {
                currentGuide += 1
                logInfo("\n[\(currentGuide)/\(guides.count)] Crawling: \(guide.url.lastPathComponent)")

                do {
                    // Fetch book.json to get TOC
                    let bookJSON = try await fetchBookJSON(for: guide.url)
                    let pages = extractPages(from: bookJSON, baseURL: guide.url)

                    logInfo("   Found \(pages.count) pages")

                    // Create guide subdirectory
                    let guideDir = outputDirectory.appendingPathComponent(bookJSON.uid)
                    try FileManager.default.createDirectory(
                        at: guideDir,
                        withIntermediateDirectories: true
                    )

                    // Save book.json for reference
                    let bookJSONPath = guideDir.appendingPathComponent("book.json")
                    let bookData = try JSONCoding.encode(bookJSON)
                    try bookData.write(to: bookJSONPath)

                    // Crawl each page
                    for (index, page) in pages.enumerated() {
                        do {
                            try await crawlPage(page, to: guideDir, framework: guide.framework, stats: &stats)
                            totalPages += 1

                            // Progress callback
                            if let onProgress {
                                let progress = ArchiveProgress(
                                    currentGuide: currentGuide,
                                    totalGuides: guides.count,
                                    currentPage: index + 1,
                                    totalPages: pages.count,
                                    guideName: bookJSON.title,
                                    pageName: page.title,
                                    stats: stats
                                )
                                onProgress(progress)
                            }

                            // Rate limiting
                            try await Task.sleep(for: Shared.Constants.Delay.archivePage)
                        } catch {
                            stats.errors += 1
                            logError("Failed to crawl page \(page.title): \(error)")
                        }
                    }

                    stats.totalGuides += 1
                } catch {
                    stats.errors += 1
                    logError("Failed to crawl guide \(guide.url): \(error)")
                }
            }

            stats.endTime = Date()

            logInfo("\nCrawl completed!")
            logStatistics(stats)

            return stats
        }

        // MARK: - Private Methods

        private func fetchBookJSON(for guideURL: URL) async throws -> BookJSON {
            // book.json is at the guide root (e.g., .../ObjCRuntimeGuide/book.json)
            let bookURL = guideURL.appendingPathComponent("book.json")

            let (data, response) = try await URLSession.shared.data(from: bookURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw ArchiveCrawlerError.invalidResponse(bookURL)
            }

            return try JSONDecoder().decode(BookJSON.self, from: data)
        }

        private func extractPages(from book: BookJSON, baseURL: URL) -> [ArchivePage] {
            var pages: [ArchivePage] = []
            var seenHrefs: Set<String> = []

            func extractFromSections(_ sections: [BookSection], parentPath: String = "") {
                for section in sections {
                    // Only add if it has an href (actual page)
                    if let href = section.href {
                        // Remove fragment identifier for file path
                        let cleanHref = href.components(separatedBy: "#").first ?? href

                        // Skip if we've already seen this file (different anchor same page)
                        guard !seenHrefs.contains(cleanHref) else {
                            // Recursively extract from nested sections anyway
                            if let nestedSections = section.sections {
                                extractFromSections(nestedSections, parentPath: section.title)
                            }
                            continue
                        }

                        seenHrefs.insert(cleanHref)
                        let pageURL = baseURL.appendingPathComponent(cleanHref)
                        let page = ArchivePage(
                            title: section.title,
                            href: cleanHref,
                            url: pageURL,
                            type: section.type ?? "section",
                            aref: section.aref
                        )
                        pages.append(page)
                    }

                    // Recursively extract from nested sections
                    if let nestedSections = section.sections {
                        extractFromSections(nestedSections, parentPath: section.title)
                    }
                }
            }

            extractFromSections(book.sections)
            return pages
        }

        private func crawlPage(
            _ page: ArchivePage,
            to guideDir: URL,
            framework: String,
            stats: inout ArchiveStatistics
        ) async throws {
            // Determine output path - preserve directory structure
            let relativePath = page.href.replacingOccurrences(of: ".html", with: ".md")
            let outputPath = guideDir.appendingPathComponent(relativePath)

            // Create parent directories
            let parentDir = outputPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            // Check if already crawled (unless force recrawl)
            let isNew = !FileManager.default.fileExists(atPath: outputPath.path)
            if !isNew, !forceRecrawl {
                stats.skippedPages += 1
                return
            }

            // Fetch HTML
            let (data, response) = try await URLSession.shared.data(from: page.url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw ArchiveCrawlerError.invalidResponse(page.url)
            }

            guard let html = String(data: data, encoding: .utf8) else {
                throw ArchiveCrawlerError.invalidEncoding
            }

            // Parse HTML to extract metadata and content
            let parsed = parseArchiveHTML(html, page: page)

            // Convert to markdown
            let markdown = convertToMarkdown(parsed, framework: framework)

            // Save
            try markdown.write(to: outputPath, atomically: true, encoding: .utf8)

            if isNew {
                stats.newPages += 1
            } else {
                stats.updatedPages += 1
            }

            stats.totalPages += 1
        }

        private func parseArchiveHTML(_ html: String, page: ArchivePage) -> ParsedArchivePage {
            // Extract metadata from meta tags
            let bookTitle = extractMetaContent(from: html, name: "book-title") ?? "Unknown"
            let chapterId = extractMetaContent(from: html, name: "chapterId")
            let date = extractMetaContent(from: html, name: "date")
            let description = extractMetaContent(from: html, name: "description")
            let identifier = extractMetaContent(from: html, name: "identifier")
            let platforms = extractMetaContent(from: html, name: "platforms")

            // Extract article content
            let content = extractArticleContent(from: html)

            return ParsedArchivePage(
                title: page.title,
                bookTitle: bookTitle,
                chapterId: chapterId,
                date: date,
                description: description,
                identifier: identifier,
                platforms: platforms,
                content: content,
                href: page.href
            )
        }

        private func extractMetaContent(from html: String, name: String) -> String? {
            // Match <meta id="name" name="name" content="value">
            // or <meta name="name" content="value">
            let patterns = [
                #"<meta[^>]*name=[\"']\#(name)[\"'][^>]*content=[\"']([^\"']*)[\"']"#,
                #"<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*name=[\"']\#(name)[\"']"#,
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = regex.firstMatch(
                          in: html,
                          range: NSRange(html.startIndex..., in: html)
                      )
                else {
                    continue
                }

                // Content is in group 1 or 2 depending on pattern
                for group in 1...match.numberOfRanges - 1 {
                    if let range = Range(match.range(at: group), in: html) {
                        let value = String(html[range])
                        if !value.isEmpty, value != name {
                            return value
                        }
                    }
                }
            }

            return nil
        }

        private func extractArticleContent(from html: String) -> String {
            // Extract content from <article id="contents">...</article>
            guard let articleStart = html.range(of: #"<article[^>]*id=[\"']contents[\"'][^>]*>"#, options: .regularExpression),
                  let articleEnd = html.range(of: "</article>", range: articleStart.upperBound..<html.endIndex)
            else {
                // Fallback: try to find any article tag
                if let fallbackStart = html.range(of: "<article", options: .caseInsensitive),
                   let tagEnd = html.range(of: ">", range: fallbackStart.upperBound..<html.endIndex),
                   let articleEnd = html.range(of: "</article>", range: tagEnd.upperBound..<html.endIndex) {
                    return String(html[tagEnd.upperBound..<articleEnd.lowerBound])
                }
                return ""
            }

            return String(html[articleStart.upperBound..<articleEnd.lowerBound])
        }

        private func convertToMarkdown(_ parsed: ParsedArchivePage, framework: String) -> String {
            var lines: [String] = []

            // YAML front matter
            lines.append("---")
            lines.append("title: \"\(escapeYAML(parsed.title))\"")
            lines.append("book: \"\(escapeYAML(parsed.bookTitle))\"")
            if !framework.isEmpty {
                lines.append("framework: \"\(escapeYAML(framework))\"")
            }
            if let chapterId = parsed.chapterId {
                lines.append("chapterId: \"\(chapterId)\"")
            }
            if let date = parsed.date {
                lines.append("date: \"\(date)\"")
            }
            if let description = parsed.description {
                lines.append("description: \"\(escapeYAML(description))\"")
            }
            if let identifier = parsed.identifier {
                lines.append("identifier: \"\(identifier)\"")
            }
            if let platforms = parsed.platforms {
                lines.append("platforms: \"\(platforms)\"")
            }
            lines.append("source: apple-archive")
            lines.append("---")
            lines.append("")

            // Title
            lines.append("# \(parsed.title)")
            lines.append("")

            // Book info
            lines.append("> **\(parsed.bookTitle)**")
            if let date = parsed.date {
                lines.append("> Last updated: \(date)")
            }
            lines.append("")

            // Convert HTML content to markdown
            let markdownContent = htmlToMarkdown(parsed.content)
            lines.append(markdownContent)

            return lines.joined(separator: "\n")
        }

        private func escapeYAML(_ text: String) -> String {
            text.replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
        }

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
            result = result.replacingOccurrences(
                of: #"<h1[^>]*>(.*?)</h1>"#,
                with: "# $1\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<h2[^>]*>(.*?)</h2>"#,
                with: "## $1\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<h3[^>]*>(.*?)</h3>"#,
                with: "### $1\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<h4[^>]*>(.*?)</h4>"#,
                with: "#### $1\n",
                options: .regularExpression
            )

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

            // Pre/code blocks - simplified
            result = result.replacingOccurrences(
                of: #"<pre[^>]*><code[^>]*>([\s\S]*?)</code></pre>"#,
                with: "\n```\n$1\n```\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<pre[^>]*>([\s\S]*?)</pre>"#,
                with: "\n```\n$1\n```\n",
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

            // Important/Note boxes
            result = result.replacingOccurrences(
                of: #"<div class=[\"']importantbox[\"'][^>]*>[\s\S]*?<p><strong>Important:</strong>\s*([\s\S]*?)</p>[\s\S]*?</div>"#,
                with: "\n> **Important:** $1\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<aside[^>]*>([\s\S]*?)</aside>"#,
                with: "\n> $1\n",
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
                ("&copy;", "(c)"),
                ("&reg;", "(R)"),
                ("&trade;", "(TM)"),
            ]

            for (entity, replacement) in entities {
                result = result.replacingOccurrences(of: entity, with: replacement)
            }

            // Numeric entities
            let numericPattern = #"&#(\d+);"#
            if let regex = try? NSRegularExpression(pattern: numericPattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: ""
                )
            }

            return result
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            Log.info(message, category: .archive)
        }

        private func logError(_ message: String) {
            Log.error("Error: \(message)", category: .archive)
        }

        private func logStatistics(_ stats: ArchiveStatistics) {
            let messages = [
                "Statistics:",
                "   Total guides: \(stats.totalGuides)",
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
                Log.info(message, category: .archive)
            }
        }
    }
}

// MARK: - Models

/// Guide info containing URL and framework name for archive crawling
public struct ArchiveGuideInfo: Sendable {
    public let url: URL
    public let framework: String

    public init(url: URL, framework: String) {
        self.url = url
        self.framework = framework
    }
}

/// Represents the book.json structure from Apple Archive
public struct BookJSON: Codable, Sendable {
    public let type: String?
    public let title: String
    public let technology: String?
    public let version: String?
    public let sections: [BookSection]
    public let uid: String

    public init(
        type: String? = nil,
        title: String,
        technology: String? = nil,
        version: String? = nil,
        sections: [BookSection],
        uid: String
    ) {
        self.type = type
        self.title = title
        self.technology = technology
        self.version = version
        self.sections = sections
        self.uid = uid
    }
}

/// Section within book.json
public struct BookSection: Codable, Sendable {
    public let title: String
    public let href: String?
    public let aref: String?
    public let type: String?
    public let isPart: Bool?
    public let sections: [BookSection]?

    public init(
        title: String,
        href: String? = nil,
        aref: String? = nil,
        type: String? = nil,
        isPart: Bool? = nil,
        sections: [BookSection]? = nil
    ) {
        self.title = title
        self.href = href
        self.aref = aref
        self.type = type
        self.isPart = isPart
        self.sections = sections
    }
}

/// Represents a page to crawl
struct ArchivePage {
    let title: String
    let href: String
    let url: URL
    let type: String
    let aref: String?
}

/// Parsed content from an archive HTML page
struct ParsedArchivePage {
    let title: String
    let bookTitle: String
    let chapterId: String?
    let date: String?
    let description: String?
    let identifier: String?
    let platforms: String?
    let content: String
    let href: String
}

// MARK: - Statistics

public struct ArchiveStatistics: Sendable {
    public var totalGuides: Int = 0
    public var totalPages: Int = 0
    public var newPages: Int = 0
    public var updatedPages: Int = 0
    public var skippedPages: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalGuides: Int = 0,
        totalPages: Int = 0,
        newPages: Int = 0,
        updatedPages: Int = 0,
        skippedPages: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalGuides = totalGuides
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

public struct ArchiveProgress: Sendable {
    public let currentGuide: Int
    public let totalGuides: Int
    public let currentPage: Int
    public let totalPages: Int
    public let guideName: String
    public let pageName: String
    public let stats: ArchiveStatistics

    public var percentage: Double {
        let guideProgress = Double(currentGuide - 1) / Double(totalGuides)
        let pageProgress = Double(currentPage) / Double(max(totalPages, 1)) / Double(totalGuides)
        return (guideProgress + pageProgress) * 100
    }

    public var currentItem: String {
        "\(guideName) - \(pageName)"
    }
}

// MARK: - Errors

public enum ArchiveCrawlerError: Error, LocalizedError {
    case invalidResponse(URL)
    case invalidEncoding
    case bookJSONNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let url):
            return "Invalid response from \(url)"
        case .invalidEncoding:
            return "Invalid text encoding"
        case .bookJSONNotFound(let url):
            return "book.json not found at \(url)"
        }
    }
}

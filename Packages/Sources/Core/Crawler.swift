import Foundation
import Logging
import os
import Shared

// MARK: - Documentation Crawler

// swiftlint:disable function_body_length
// Justification: This class implements the core web crawling engine with WKWebView integration.
// It manages: page navigation, URL queue processing, change detection, content extraction,
// progress tracking, session persistence, and navigation delegation. The crawling logic is
// inherently stateful and requires coordinating multiple async operations in sequence.
// Function body length: 67 lines
// Disabling: function_body_length (50 line limit for main crawl loop)

/// Main crawler for Apple documentation using WKWebView
extension Core {
    @MainActor
    public final class Crawler: NSObject {
        private let configuration: Shared.CrawlerConfiguration
        private let changeDetection: Shared.ChangeDetectionConfiguration
        private let output: Shared.OutputConfiguration
        private let state: CrawlerState

        private var webPageFetcher: WKWebCrawler.WKWebContentFetcher!
        private var visited = Set<String>()
        private var queue: [(url: URL, depth: Int)] = []
        private var stats: CrawlStatistics

        private var onProgress: (@Sendable (CrawlProgress) -> Void)?
        private var logFileHandle: FileHandle?

        public init(configuration: Shared.Configuration) async {
            self.configuration = configuration.crawler
            changeDetection = configuration.changeDetection
            output = configuration.output
            state = CrawlerState(configuration: configuration.changeDetection)
            stats = CrawlStatistics()
            super.init()

            // Initialize WKWebContentFetcher from WKWebCrawler namespace
            webPageFetcher = WKWebCrawler.WKWebContentFetcher()

            // Temporary debug logging for #25
            let logPath = self.configuration.outputDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("crawl-debug.log")
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
            logFileHandle = try? FileHandle(forWritingTo: logPath)
        }

        // MARK: - Public API

        /// Start crawling from the configured start URL
        public func crawl(onProgress: (@Sendable (CrawlProgress) -> Void)? = nil) async throws -> CrawlStatistics {
            self.onProgress = onProgress

            // Check for resumable session
            let hasActiveSession = await state.hasActiveSession()
            if hasActiveSession {
                logInfo("🔄 Found resumable session!")
                if let savedSession = await state.getSavedSession() {
                    logInfo("   Resuming from \(savedSession.visited.count) visited URLs")
                    logInfo("   Queue has \(savedSession.queue.count) pending URLs")

                    // Restore state
                    visited = savedSession.visited
                    queue = savedSession.queue.compactMap { queued in
                        guard let url = URL(string: queued.url) else { return nil }
                        return (url: url, depth: queued.depth)
                    }

                    // Restore or initialize stats
                    await state.updateStatistics { stats in
                        if stats.startTime == nil {
                            stats.startTime = savedSession.sessionStartTime
                        }
                    }
                }
            } else {
                // Initialize stats for new crawl
                let startTime = Date()
                await state.updateStatistics { stats in
                    stats = CrawlStatistics(startTime: startTime)
                }

                // Initialize queue
                queue = [(url: configuration.startURL, depth: 0)]

                logInfo("🚀 Starting new crawl")
            }

            // Create output directory
            try FileManager.default.createDirectory(
                at: configuration.outputDirectory,
                withIntermediateDirectories: true
            )

            // Log start
            logInfo("   Start URL: \(configuration.startURL.absoluteString)")
            logInfo("   Max pages: \(configuration.maxPages)")
            logInfo("   Current: \(visited.count) visited, \(queue.count) queued")
            logInfo("   Output: \(configuration.outputDirectory.path)")

            // Crawl loop
            while !queue.isEmpty, visited.count < configuration.maxPages {
                let (url, depth) = queue.removeFirst()

                guard let normalizedURL = URLUtilities.normalize(url),
                      !visited.contains(normalizedURL.absoluteString)
                else {
                    continue
                }

                visited.insert(normalizedURL.absoluteString)

                do {
                    try await crawlPageWithRetry(url: normalizedURL, depth: depth, maxRetries: 2)

                    // Auto-save session state periodically
                    try await state.autoSaveIfNeeded(
                        visited: visited,
                        queue: queue,
                        startURL: configuration.startURL,
                        outputDirectory: configuration.outputDirectory
                    )

                    // Log progress periodically
                    if visited.count % Shared.Constants.Interval.progressLogEvery == 0 {
                        await logProgressUpdate()
                    }

                    // Recycle WKWebView every 50 pages to prevent memory buildup (#25)
                    if visited.count % 50 == 0 {
                        await recycleWebView()
                    }
                } catch {
                    await state.updateStatistics { $0.errors += 1 }
                    logError("Error crawling \(normalizedURL.absoluteString): \(error)")
                }

                // Delay between requests
                try await Task.sleep(for: .seconds(configuration.requestDelay))
            }

            // Finalize - get final stats from state
            var finalStats = await state.getStatistics()
            finalStats.endTime = Date()

            // Clear session state on successful completion
            await state.clearSessionState()

            try await state.finalizeCrawl(stats: finalStats)

            logInfo("\n✅ Crawl completed!")
            await logStatistics()

            // Auto-generate priority package list if this was a Swift.org crawl
            try await generatePriorityPackagesIfSwiftOrg()

            return finalStats
        }

        // MARK: - Private Methods

        /// Crawl a page with retry mechanism for difficult pages (#25)
        /// On failure, recycles WKWebView and retries up to maxRetries times
        private func crawlPageWithRetry(url: URL, depth: Int, maxRetries: Int) async throws {
            var lastError: Error?

            for attempt in 0...maxRetries {
                if attempt > 0 {
                    logInfo("🔄 Retry \(attempt)/\(maxRetries) for \(url.lastPathComponent) - recycling WebView")
                    await recycleWebView()
                    // Brief pause before retry
                    try await Task.sleep(for: .seconds(1))
                }

                do {
                    try await crawlPage(url: url, depth: depth)
                    return // Success
                } catch {
                    lastError = error
                    logError("Attempt \(attempt + 1) failed for \(url.absoluteString): \(error)")
                }
            }

            // All retries exhausted
            throw lastError ?? CrawlerError.invalidState
        }

        private func crawlPage(url: URL, depth: Int) async throws {
            let framework = URLUtilities.extractFramework(from: url)

            // Get framework page count for display
            let fwStats = await state.getFrameworkStats(framework: framework)
            let fwPageCount = fwStats?.pageCount ?? 0

            let urlString = url.absoluteString
            let progress = "[\(visited.count)/\(configuration.maxPages)] [\(framework):\(fwPageCount + 1)]"
            logInfo("📄 \(progress) depth=\(depth) \(urlString)")

            // Try JSON API first (better data quality), fall back to HTML if unavailable
            var structuredPage: StructuredDocumentationPage?
            var markdown: String
            var links: [URL]

            // Check if this URL could have a JSON API endpoint (Apple docs)
            let hasJSONEndpoint = AppleJSONToMarkdown.jsonAPIURL(from: url) != nil

            if hasJSONEndpoint {
                do {
                    (structuredPage, markdown, links) = try await loadPageViaJSON(url: url)
                } catch {
                    // JSON API failed, fall back to HTML
                    logInfo("   ⚠️ JSON API unavailable, using HTML fallback")
                    let html = try await loadPage(url: url)
                    markdown = HTMLToMarkdown.convert(html, url: url)
                    links = extractLinks(from: html, baseURL: url)
                    structuredPage = HTMLToMarkdown.toStructuredPage(html, url: url)
                }
            } else {
                // No JSON endpoint available, use HTML directly
                let html = try await loadPage(url: url)
                markdown = HTMLToMarkdown.convert(html, url: url)
                links = extractLinks(from: html, baseURL: url)
                structuredPage = HTMLToMarkdown.toStructuredPage(html, url: url)
            }

            // Compute content hash from structured page or markdown
            let contentHash = structuredPage?.contentHash ?? HashUtilities.sha256(of: markdown)

            // Determine output path
            let frameworkDir = configuration.outputDirectory.appendingPathComponent(framework)
            try FileManager.default.createDirectory(
                at: frameworkDir,
                withIntermediateDirectories: true
            )

            let filename = URLUtilities.filename(from: url)

            // JSON file path (primary output format)
            let jsonFilePath = frameworkDir.appendingPathComponent(
                "\(filename)\(Shared.Constants.FileName.jsonExtension)"
            )

            // Markdown file path (optional, for backwards compatibility)
            let markdownFilePath = frameworkDir.appendingPathComponent(
                "\(filename)\(Shared.Constants.FileName.markdownExtension)"
            )

            // Check if we should recrawl
            let shouldRecrawl = await state.shouldRecrawl(
                url: url.absoluteString,
                contentHash: contentHash,
                filePath: jsonFilePath
            )

            if !shouldRecrawl {
                logInfo("   ⏩ No changes detected, skipping")
                await state.updateStatistics { $0.skippedPages += 1 }
                await state.updateStatistics { $0.totalPages += 1 }
                return
            }

            // Save JSON file (primary output)
            let isNew = !FileManager.default.fileExists(atPath: jsonFilePath.path)

            if let page = structuredPage {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let jsonData = try encoder.encode(page)
                try jsonData.write(to: jsonFilePath)
            }

            // Optionally save markdown (can be disabled in config later)
            if output.includeMarkdown {
                try markdown.write(to: markdownFilePath, atomically: true, encoding: .utf8)
            }

            // Update metadata with framework tracking
            await state.updatePage(
                url: url.absoluteString,
                framework: framework,
                filePath: jsonFilePath.path,
                contentHash: contentHash,
                depth: depth,
                isNew: isNew
            )

            // Update stats
            if isNew {
                await state.updateStatistics { $0.newPages += 1 }
                logInfo("   ✅ Saved new page: \(jsonFilePath.lastPathComponent)")
            } else {
                await state.updateStatistics { $0.updatedPages += 1 }
                logInfo("   ♻️  Updated page: \(jsonFilePath.lastPathComponent)")
            }

            await state.updateStatistics { $0.totalPages += 1 }

            // Enqueue discovered links
            if depth < configuration.maxDepth {
                for link in links where shouldVisit(url: link) {
                    queue.append((url: link, depth: depth + 1))
                }
            }

            // Notify progress
            if let onProgress {
                let progress = await CrawlProgress(
                    currentURL: url,
                    visitedCount: visited.count,
                    totalPages: configuration.maxPages,
                    stats: state.getStatistics()
                )
                onProgress(progress)
            }
        }

        /// Load page via Apple's JSON API - avoids WKWebView memory issues
        /// Returns structured page data for JSON output and links for crawling
        private func loadPageViaJSON(url: URL) async throws -> (
            structuredPage: StructuredDocumentationPage?,
            markdown: String,
            links: [URL]
        ) {
            guard let jsonURL = AppleJSONToMarkdown.jsonAPIURL(from: url) else {
                throw CrawlerError.invalidState
            }

            logInfo("   📡 Using JSON API: \(jsonURL.lastPathComponent)")

            let (data, response) = try await URLSession.shared.data(from: jsonURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw CrawlerError.invalidHTML
            }

            // Create structured page from JSON
            let structuredPage = AppleJSONToMarkdown.toStructuredPage(data, url: url)

            // Also create markdown for backwards compatibility
            guard let markdown = AppleJSONToMarkdown.convert(data, url: url) else {
                throw CrawlerError.invalidHTML
            }

            let links = AppleJSONToMarkdown.extractLinks(from: data)

            return (structuredPage, markdown, links)
        }

        private func loadPage(url: URL) async throws -> String {
            // Delegate to WKWebCrawler's WKWebContentFetcher
            try await webPageFetcher.fetch(url: url)
        }

        private func extractLinks(from html: String, baseURL: URL) -> [URL] {
            var links: [URL] = []

            // Extract href attributes from <a> tags
            let pattern = Shared.Constants.Pattern.htmlHref
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = html as NSString
                let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

                for match in matches where match.numberOfRanges >= 2 {
                    let hrefRange = match.range(at: 1)
                    let href = nsString.substring(with: hrefRange)

                    // Resolve relative URLs
                    if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                        links.append(url)
                    }
                }
            }

            return links
        }

        private func shouldVisit(url: URL) -> Bool {
            // Check if URL starts with allowed prefixes
            let urlString = url.absoluteString
            guard configuration.allowedPrefixes.contains(where: { urlString.hasPrefix($0) }) else {
                return false
            }

            // Check if already visited
            guard let normalized = URLUtilities.normalize(url) else {
                return false
            }

            return !visited.contains(normalized.absoluteString)
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            let memoryMsg = "🧠 \(String(format: "%.1f", getMemoryUsageMB()))MB | \(message)"
            Log.info(memoryMsg, category: .crawler)
            logToFile(memoryMsg)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            Log.error(errorMessage, category: .crawler)
        }

        private func logProgressUpdate() async {
            let stats = await state.getStatistics()
            let elapsed = stats.startTime.map { Date().timeIntervalSince($0) } ?? 0
            let pagesPerSecond = elapsed > 0 ? Double(visited.count) / elapsed : 0
            let remaining = configuration.maxPages - visited.count
            let etaSeconds = pagesPerSecond > 0 ? Double(remaining) / pagesPerSecond : 0

            let messages = [
                "",
                "📊 Progress Update [\(visited.count)/\(configuration.maxPages)]:",
                "   Visited: \(visited.count) pages",
                "   Queue: \(queue.count) pending URLs",
                "   New: \(stats.newPages) | Updated: \(stats.updatedPages) | Skipped: \(stats.skippedPages)",
                "   Errors: \(stats.errors)",
                "   Speed: \(String(format: "%.2f", pagesPerSecond)) pages/sec",
                "   Elapsed: \(formatDuration(elapsed))",
                "   ETA: \(formatDuration(etaSeconds))",
                "",
            ]

            for message in messages {
                Log.info(message, category: .crawler)
            }
        }

        private func logStatistics() async {
            let stats = await state.getStatistics()
            let messages = [
                "📊 Statistics:",
                "   Total pages processed: \(stats.totalPages)",
                "   New pages: \(stats.newPages)",
                "   Updated pages: \(stats.updatedPages)",
                "   Skipped (unchanged): \(stats.skippedPages)",
                "   Errors: \(stats.errors)",
                stats.duration.map { "   Duration: \(formatDuration($0))" } ?? "",
                "",
                "📁 Output: \(configuration.outputDirectory.path)",
            ]

            for message in messages where !message.isEmpty {
                Log.info(message, category: .crawler)
            }
        }

        private func formatDuration(_ seconds: TimeInterval) -> String {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            let secs = Int(seconds) % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m \(secs)s"
            } else if minutes > 0 {
                return "\(minutes)m \(secs)s"
            } else {
                return "\(secs)s"
            }
        }

        // MARK: - Temporary Debug Logging (#25)

        private func logToFile(_ message: String) {
            guard let handle = logFileHandle else { return }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = Data(line.utf8)
            if !data.isEmpty {
                handle.write(data)
                try? handle.synchronize()
            }
        }

        private func getMemoryUsageMB() -> Double {
            // Delegate to WKWebCrawler's WKWebContentFetcher
            webPageFetcher.getMemoryUsageMB()
        }

        private func recycleWebView() async {
            let memBefore = getMemoryUsageMB()
            // Delegate to WKWebCrawler's WKWebContentFetcher
            webPageFetcher.recycle()
            let memAfter = getMemoryUsageMB()
            let before = String(format: "%.1f", memBefore)
            let after = String(format: "%.1f", memAfter)
            logInfo("♻️ Recycled WKWebContentFetcher: \(before)MB → \(after)MB")
        }

        /// Auto-generate priority package list if this was a Swift.org crawl
        private func generatePriorityPackagesIfSwiftOrg() async throws {
            // Check if start URL is Swift.org
            guard configuration.startURL.absoluteString.contains(Shared.Constants.HostDomain.swiftOrg) else {
                return
            }

            let sourceName = Shared.Constants.DisplayName.swiftOrg
            logInfo("\n📋 Generating priority package list from \(sourceName) documentation...")

            // Use the output directory as Swift.org docs path
            let outputPath = configuration.outputDirectory
                .deletingLastPathComponent()
                .appendingPathComponent(Shared.Constants.FileName.priorityPackages)

            let generator = PriorityPackageGenerator(
                swiftOrgDocsPath: configuration.outputDirectory,
                outputPath: outputPath
            )

            let priorityList = try await generator.generate()

            logInfo("   ✅ Found \(priorityList.stats.totalUniqueReposFound) unique packages")
            logInfo("   📁 Saved to: \(outputPath.path)")
            logInfo("   💡 This list will be used for prioritizing package documentation crawls")
        }
    }
}

// MARK: - Crawler Progress

/// Progress information during crawling
public struct CrawlProgress: Sendable {
    public let currentURL: URL
    public let visitedCount: Int
    public let totalPages: Int
    public let stats: CrawlStatistics

    public var percentage: Double {
        Double(visitedCount) / Double(totalPages) * 100
    }
}

// MARK: - Crawler Errors

public enum CrawlerError: Error, LocalizedError {
    case timeout
    case invalidState
    case invalidHTML
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Page load timeout"
        case .invalidState:
            return "Invalid crawler state"
        case .invalidHTML:
            return "Invalid HTML received"
        case .unsupportedPlatform:
            return "WKWebView is not available on this platform"
        }
    }
}

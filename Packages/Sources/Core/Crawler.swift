import Foundation
import Logging
import os
import Shared
import WebKit

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

        private var webView: WKWebView!
        private var visited = Set<String>()
        private var queue: [(url: URL, depth: Int)] = []
        private var stats: CrawlStatistics

        private var onProgress: (@Sendable (CrawlProgress) -> Void)?

        public init(configuration: Shared.Configuration) async {
            self.configuration = configuration.crawler
            changeDetection = configuration.changeDetection
            output = configuration.output
            state = CrawlerState(configuration: configuration.changeDetection)
            stats = CrawlStatistics()
            super.init()

            // Initialize WKWebView
            let webConfiguration = WKWebViewConfiguration()
            webView = WKWebView(frame: .zero, configuration: webConfiguration)
            webView.navigationDelegate = self
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
                    try await crawlPage(url: normalizedURL, depth: depth)

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

        private func crawlPage(url: URL, depth: Int) async throws {
            let framework = URLUtilities.extractFramework(from: url)

            logInfo("📄 [\(visited.count)/\(configuration.maxPages)] depth=\(depth) [\(framework)] \(url.absoluteString)")

            // Load page with WKWebView
            let html = try await loadPage(url: url)

            // Compute content hash
            let contentHash = HashUtilities.sha256(of: html)

            // Determine output path
            let frameworkDir = configuration.outputDirectory.appendingPathComponent(framework)
            try FileManager.default.createDirectory(
                at: frameworkDir,
                withIntermediateDirectories: true
            )

            let filename = URLUtilities.filename(from: url)
            let filePath = frameworkDir.appendingPathComponent(
                "\(filename)\(Shared.Constants.FileName.markdownExtension)"
            )

            // Check if we should recrawl
            let shouldRecrawl = await state.shouldRecrawl(
                url: url.absoluteString,
                contentHash: contentHash,
                filePath: filePath
            )

            if !shouldRecrawl {
                logInfo("   ⏩ No changes detected, skipping")
                await state.updateStatistics { $0.skippedPages += 1 }
                await state.updateStatistics { $0.totalPages += 1 }
                return
            }

            // Convert HTML to Markdown
            let markdown = HTMLToMarkdown.convert(html, url: url)

            // Save to file
            let isNew = !FileManager.default.fileExists(atPath: filePath.path)
            try markdown.write(to: filePath, atomically: true, encoding: .utf8)

            // Update metadata
            await state.updatePage(
                url: url.absoluteString,
                framework: framework,
                filePath: filePath.path,
                contentHash: contentHash,
                depth: depth
            )

            // Update stats
            if isNew {
                await state.updateStatistics { $0.newPages += 1 }
                logInfo("   ✅ Saved new page: \(filePath.lastPathComponent)")
            } else {
                await state.updateStatistics { $0.updatedPages += 1 }
                logInfo("   ♻️  Updated page: \(filePath.lastPathComponent)")
            }

            await state.updateStatistics { $0.totalPages += 1 }

            // Extract and enqueue links
            if depth < configuration.maxDepth {
                let links = extractLinks(from: html, baseURL: url)
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

        private func loadPage(url: URL) async throws -> String {
            // Use structured concurrency: proper task racing with withThrowingTaskGroup
            webView.load(URLRequest(url: url))

            // Race timeout vs page load - first to complete wins
            return try await withThrowingTaskGroup(of: String?.self) { group in
                // Task 1: Timeout task returns nil
                group.addTask {
                    try await Task.sleep(for: Shared.Constants.Timeout.pageLoad)
                    return nil
                }

                // Task 2: Load page content returns HTML
                group.addTask {
                    try await self.loadPageContent()
                }

                // Get first result - true racing behavior
                for try await result in group {
                    if let html = result {
                        // HTML loaded successfully - cancel timeout task
                        group.cancelAll()
                        return html
                    }
                    // If result is nil, timeout won - continue to next iteration
                    // which will throw or return remaining task result
                }

                // If we get here, timeout won the race
                group.cancelAll()
                throw CrawlerError.timeout
            }
        }

        /// Helper method to load page content (stays on MainActor)
        private func loadPageContent() async throws -> String {
            // Wait for page to load
            try await Task.sleep(for: .seconds(5))

            // Use modern async evaluateJavaScript API
            let result = try await webView.evaluateJavaScript(
                Shared.Constants.JavaScript.getDocumentHTML,
                in: nil,
                contentWorld: .page
            )

            guard let html = result as? String else {
                throw CrawlerError.invalidHTML
            }

            return html
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
            Logging.Logger.crawler.info(message)
            print(message)
            fflush(stdout)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            Logging.Logger.crawler.error(message)
            fputs("\(errorMessage)\n", stderr)
            fflush(stderr)
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
                Logging.Logger.crawler.info(message)
                print(message)
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
                Logging.Logger.crawler.info(message)
                print(message)
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

        /// Auto-generate priority package list if this was a Swift.org crawl
        private func generatePriorityPackagesIfSwiftOrg() async throws {
            // Check if start URL is Swift.org
            guard configuration.startURL.absoluteString.contains(Shared.Constants.HostDomain.swiftOrg) else {
                return
            }

            logInfo("\n📋 Generating priority package list from \(Shared.Constants.DisplayName.swiftOrg) documentation...")

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

// MARK: - WKNavigationDelegate

extension Core.Crawler: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logError("Navigation failed: \(error.localizedDescription)")
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

import Foundation
import Logging
import os
import Shared

// MARK: - Documentation Crawler

// swiftlint:disable function_body_length type_body_length
// Justification: This class implements the core web crawling engine with WKWebView integration.
// It manages: page navigation, URL queue processing, change detection, content extraction,
// progress tracking, session persistence, and navigation delegation. The crawling logic is
// inherently stateful and requires coordinating multiple async operations in sequence.

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
        // Tracks URLs currently in `queue` so the same URL discovered from
        // multiple parents is only enqueued once. Was an O(N) duplicate queue
        // before — measured at 72 % duplicates on the 2026-04-30 v1.0 recrawl
        // (629k entries / 176k unique). Persistence-free: rebuilt from `queue`
        // on resume so the existing CrawlSessionState schema doesn't need a
        // migration. (#206)
        private var enqueued = Set<String>()
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

            // Check for resumable session (must match current start URL)
            let savedSession = await state.getSavedSession()
            let canResume = savedSession != nil
                && savedSession!.isActive
                && savedSession!.startURL == configuration.startURL.absoluteString
            if canResume, let savedSession {
                logInfo("🔄 Found resumable session!")
                logInfo("   Resuming from \(savedSession.visited.count) visited URLs")
                logInfo("   Queue has \(savedSession.queue.count) pending URLs")

                // Restore state
                visited = savedSession.visited
                queue = savedSession.queue.compactMap { queued in
                    guard let url = URL(string: queued.url),
                          let normalized = URLUtilities.normalize(url) else { return nil }
                    return (url: normalized, depth: queued.depth)
                }
                // Rebuild the enqueued-URL set from the restored queue so the
                // dedup at enqueue is correct after resume. Schema-compatible:
                // we don't persist `enqueued` separately.
                enqueued = Set(queue.map(\.url.absoluteString))

                // Restore or initialize stats
                await state.updateStatistics { stats in
                    if stats.startTime == nil {
                        stats.startTime = savedSession.sessionStartTime
                    }
                }
            } else {
                // Clear stale session if start URL doesn't match
                if savedSession != nil {
                    logInfo("⚠️ Ignoring saved session (different start URL)")
                    await state.clearSessionState()
                }
                // Initialize stats for new crawl
                let startTime = Date()
                await state.updateStatistics { stats in
                    stats = CrawlStatistics(startTime: startTime)
                }

                // Initialize queue — seed from technologies.json for Apple docs root
                let isAppleDocs = configuration.startURL.host?.contains("developer.apple.com") == true
                let isDocsRoot = configuration.startURL.path == "/documentation"
                    || configuration.startURL.path == "/documentation/"

                if isAppleDocs, isDocsRoot {
                    do {
                        logInfo("📋 Fetching technology index for complete framework coverage...")
                        let frameworkURLs = try await TechnologiesIndexFetcher.fetchFrameworkURLs()
                        queue = frameworkURLs.compactMap { url in
                            URLUtilities.normalize(url).map { (url: $0, depth: 0) }
                        }
                        logInfo("   ✅ Seeded queue with \(frameworkURLs.count) framework root URLs")
                    } catch {
                        logInfo("   ⚠️ Failed to fetch technology index: \(error.localizedDescription)")
                        logInfo("   ⚠️ Falling back to start URL only")
                        let startURL = URLUtilities.normalize(configuration.startURL) ?? configuration.startURL
                        queue = [(url: startURL, depth: 0)]
                    }
                } else {
                    let startURL = URLUtilities.normalize(configuration.startURL) ?? configuration.startURL
                    queue = [(url: startURL, depth: 0)]
                }

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
                // No longer in the queue — clear from the enqueued set so a
                // re-enqueue (e.g. via --retry-errors) is allowed. Use the
                // raw URL string since enqueue keys on `link.absoluteString`.
                enqueued.remove(url.absoluteString)

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

                    // Recycle WKWebView every N pages to prevent memory buildup (#25)
                    if visited.count % Shared.Constants.Interval.webViewRecycleEvery == 0 {
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

            // Removed in #213: the post-Swift.org crawl side-effect that
            // overwrote `priority-packages.json` with the package-mention scan
            // result has been disabled. `cupertino fetch --type swift` is now
            // a pure Swift.org docs crawl. The `generatePriorityPackagesIfSwiftOrg`
            // helper is retained below for a future opt-in
            // `cupertino generate-priority-packages` subcommand or `--update-priority-packages`
            // flag, but is no longer called as a fetch side-effect.

            return finalStats
        }

        // MARK: - Private Methods

        /// Crawl a page with retry mechanism for difficult pages (#25)
        /// On failure, recycles WKWebView and retries up to maxRetries times
        private func crawlPageWithRetry(url: URL, depth: Int, maxRetries: Int) async throws {
            var lastError: Error?

            for attempt in 0...maxRetries {
                if attempt > 0 {
                    // Exponential backoff (#209): 1s, 3s, 9s for attempts 1/2/3.
                    // Apple's JSON API rate-limits hot framework prefixes for
                    // longer than the prior fixed 1-second pause; widening the
                    // gap between attempts lets all 3 retries land in different
                    // rate-limit windows. 2026-04-30 empirical: 187 of 192
                    // crawl-time failures recovered on a same-URL retry pass
                    // minutes later, confirming the rate-limit-burst hypothesis.
                    let delay = Shared.Constants.Delay.retryBackoff(attempt: attempt)
                    let last = url.lastPathComponent
                    logInfo("🔄 Retry \(attempt)/\(maxRetries) for \(last) — waiting \(delay), recycling WebView")
                    await recycleWebView()
                    try await Task.sleep(for: delay)
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
            let progress = "[\(visited.count)] [\(framework):\(fwPageCount + 1)]"
            logInfo("📄 \(progress) depth=\(depth) \(urlString)")

            // Try JSON API first (better data quality), fall back to HTML if unavailable
            var structuredPage: StructuredDocumentationPage?
            var markdown: String
            var links: [URL]

            // Check if this URL could have a JSON API endpoint (Apple docs)
            let hasJSONEndpoint = AppleJSONToMarkdown.jsonAPIURL(from: url) != nil

            // The HTML→markdown / link extraction calls below are synchronous
            // and allocate heavily through Foundation (NSString operations,
            // regex, JSON parsing). Wrap each in `autoreleasepool` so the
            // ephemeral NSObject buffers get released at the end of every
            // page instead of accumulating until the Task ends — critical for
            // multi-day crawls (e.g. v1.0 320k corpus on Claw Mini) where
            // the implicit Task-scoped pool would otherwise hoard megabytes
            // of pool buffers per thousand pages.
            // Discovery mode controls which path the crawler uses for content
            // and link extraction. See `Shared.DiscoveryMode` for semantics.
            // The webview-only mode skips JSON entirely so we can produce a
            // clean WKWebView-discovered corpus alongside a JSON-only corpus
            // in a separate output directory, then diff the two metadata.json
            // files to measure the discovery gap. (#203 methodology)
            let mode = configuration.discoveryMode
            let useJSON = hasJSONEndpoint && mode != .webViewOnly

            if useJSON {
                do {
                    (structuredPage, markdown, links) = try await loadPageViaJSON(url: url, depth: depth)
                    // Augment JSON-extracted links with HTML anchor tags when enabled. (#203)
                    // Catches ~9,600 URLs that Apple's DocC JSON references dict omits.
                    // Skipped in .jsonOnly mode (speed-critical) and when explicitly disabled.
                    if configuration.htmlLinkAugmentation, mode == .auto {
                        if let html = try? await loadPage(url: url) {
                            let htmlLinks = autoreleasepool { extractLinks(from: html, baseURL: url) }
                            let seen = Set(links.map(\.absoluteString))
                            let added = htmlLinks.filter { !seen.contains($0.absoluteString) }
                            if !added.isEmpty {
                                logInfo("   🔗 HTML augmentation: +\(added.count) links")
                                links += added
                            }
                        }
                    }
                } catch {
                    if mode == .jsonOnly {
                        // No fallback in pure JSON-only mode — propagate.
                        throw error
                    }
                    // JSON API failed, fall back to HTML
                    logInfo("   ⚠️ JSON API unavailable, using HTML fallback")
                    let html = try await loadPage(url: url)
                    (markdown, links, structuredPage) = autoreleasepool {
                        (
                            HTMLToMarkdown.convert(html, url: url),
                            extractLinks(from: html, baseURL: url),
                            HTMLToMarkdown.toStructuredPage(html, url: url, depth: depth)
                        )
                    }
                }
            } else {
                // No JSON endpoint available, use HTML directly
                let html = try await loadPage(url: url)
                (markdown, links, structuredPage) = autoreleasepool {
                    (
                        HTMLToMarkdown.convert(html, url: url),
                        extractLinks(from: html, baseURL: url),
                        HTMLToMarkdown.toStructuredPage(html, url: url, depth: depth)
                    )
                }
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

            // Enqueue discovered links before any early returns
            // so child pages are always discovered even when content is unchanged.
            //
            // Dedup at enqueue time (#206): skip links already visited or
            // already queued so the same URL discovered from multiple parents
            // is only enqueued once. Pre-#206 the queue ran ~72 % duplicates.
            if depth < configuration.maxDepth {
                for link in links where shouldVisit(url: link) {
                    let key = link.absoluteString
                    if visited.contains(key) || !enqueued.insert(key).inserted { continue }
                    queue.append((url: link, depth: depth + 1))
                }
            }

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
        private func loadPageViaJSON(url: URL, depth: Int) async throws -> (
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

            // Wrap the synchronous JSON parsing in `autoreleasepool` so the
            // NSData / NSDictionary / NSString buffers Foundation allocates
            // during decode get released at the end of this page instead of
            // accumulating in the implicit Task-scoped pool. See the comment
            // in the main crawl loop for the multi-day-crawl rationale.
            return try autoreleasepool {
                let structuredPage = AppleJSONToMarkdown.toStructuredPage(data, url: url, depth: depth)
                guard let markdown = AppleJSONToMarkdown.convert(data, url: url) else {
                    throw CrawlerError.invalidHTML
                }
                let links = AppleJSONToMarkdown.extractLinks(from: data)
                return (structuredPage, markdown, links)
            }
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
            // Check if URL starts with allowed prefixes (case-insensitive)
            let urlString = url.absoluteString.lowercased()
            guard configuration.allowedPrefixes.contains(where: { urlString.hasPrefix($0.lowercased()) }) else {
                return false
            }

            // Check if already visited
            guard let normalized = URLUtilities.normalize(url) else {
                return false
            }

            let normalizedString = normalized.absoluteString
            guard !visited.contains(normalizedString) else {
                return false
            }

            return !queue.contains { queuedURL, _ in
                URLUtilities.normalize(queuedURL)?.absoluteString == normalizedString
            }
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            let memoryMsg = "\(String(format: "%.1f", getMemoryUsageMB()))MB | \(message)"
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
                "📊 Progress Update [\(visited.count)]:",
                "   Visited: \(visited.count) pages",
                "   Queue: \(queue.count) pending URLs",
                "   New: \(stats.newPages) | Updated: \(stats.updatedPages) | Skipped: \(stats.skippedPages)",
                "   Errors: \(stats.errors)",
                "   Speed: \(String(format: "%.2f", pagesPerSecond)) pages/sec",
                "   Elapsed: \(Shared.Formatting.formatDurationVerbose(elapsed))",
                "   ETA: \(Shared.Formatting.formatDurationVerbose(etaSeconds))",
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
                stats.duration.map { "   Duration: \(Shared.Formatting.formatDurationVerbose($0))" } ?? "",
                "",
                "📁 Output: \(configuration.outputDirectory.path)",
            ]

            for message in messages where !message.isEmpty {
                Log.info(message, category: .crawler)
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

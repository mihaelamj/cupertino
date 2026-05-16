import CoreProtocols
import CrawlerModels
import Foundation
import LoggingModels
import os
import SharedConstants

// MARK: - Documentation Crawler

/// Main crawler for Apple documentation using WKWebView
extension Crawler {
    @MainActor
    public final class AppleDocs: NSObject {
        private let configuration: Shared.Configuration.Crawler
        private let changeDetection: Shared.Configuration.ChangeDetection
        private let output: Shared.Configuration.Output
        private let state: State

        private var webPageFetcher: Crawler.WebKit.ContentFetcher!
        private var visited = Set<String>()
        private var queue: [(url: URL, depth: Int)] = []
        private var retryQueue: [Shared.Models.QueuedRetryURL] = []
        // Tracks URLs currently in `queue` so the same URL discovered from
        // multiple parents is only enqueued once. Was an O(N) duplicate queue
        // before — measured at 72 % duplicates on the 2026-04-30 v1.0 recrawl
        // (629k entries / 176k unique). Persistence-free: rebuilt from `queue`
        // on resume so the existing CrawlSessionState schema doesn't need a
        // migration. (#206)
        private var enqueued = Set<String>()
        private var stats: Shared.Models.CrawlStatistics

        // GoF Strategy seams (#505). Concrete implementations live in
        // the CLI composition root and wrap `Core.Parser.HTML`,
        // `Core.JSONParser.AppleJSONToMarkdown`,
        // `Core.PackageIndexing.PriorityPackageGenerator`. The crawler
        // target itself imports neither `Core` nor `CoreJSONParser`
        // nor `CorePackageIndexing`.
        private let htmlParser: any Crawler.HTMLParserStrategy
        private let appleJSONParser: any Crawler.AppleJSONParserStrategy
        private let priorityPackageStrategy: any Crawler.PriorityPackageStrategy

        /// GoF Strategy seam for log emission (1994 p. 315). Injected by
        /// the CLI composition root via `Logging.LiveRecording()`. The
        /// Crawler target imports `LoggingModels` (the foundation-layer
        /// protocol surface) and never reaches for the `Logging.Log`
        /// static.
        private let logger: any LoggingModels.Logging.Recording

        private var progressObserver: (any Crawler.AppleDocsProgressObserving)?
        private var logFileHandle: FileHandle?

        public init(
            configuration: Shared.Configuration,
            htmlParser: any Crawler.HTMLParserStrategy,
            appleJSONParser: any Crawler.AppleJSONParserStrategy,
            priorityPackageStrategy: any Crawler.PriorityPackageStrategy,
            logger: any LoggingModels.Logging.Recording
        ) async {
            self.configuration = configuration.crawler
            changeDetection = configuration.changeDetection
            output = configuration.output
            state = State(configuration: configuration.changeDetection, logger: logger)
            stats = Shared.Models.CrawlStatistics()
            self.htmlParser = htmlParser
            self.appleJSONParser = appleJSONParser
            self.priorityPackageStrategy = priorityPackageStrategy
            self.logger = logger
            super.init()

            // Initialize Crawler.WebKit.ContentFetcher from WKWebCrawler namespace
            webPageFetcher = Crawler.WebKit.ContentFetcher()

            // Temporary debug logging for #25
            let logPath = self.configuration.outputDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("crawl-debug.log")
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
            logFileHandle = try? FileHandle(forWritingTo: logPath)
        }

        // MARK: - Public API

        /// Start crawling from the configured start URL. Pass an
        /// `any Crawler.AppleDocsProgressObserving` to receive per-URL
        /// progress updates; `nil` opts out.
        public func crawl(progress: (any Crawler.AppleDocsProgressObserving)? = nil) async throws -> Shared.Models.CrawlStatistics {
            progressObserver = progress

            // Check for resumable session (must match current start URL)
            let savedSession = await state.getSavedSession()
            let canResume = savedSession.map {
                $0.isActive && $0.startURL == configuration.startURL.absoluteString
            } ?? false
            if canResume, let savedSession {
                logInfo("🔄 Found resumable session!")
                logInfo("   Resuming from \(savedSession.visited.count) visited URLs")
                logInfo("   Queue has \(savedSession.queue.count) pending URLs")

                // Restore state
                visited = savedSession.visited
                queue = savedSession.queue.compactMap { queued in
                    guard let url = URL(string: queued.url),
                          let normalized = Shared.Models.URLUtilities.normalize(url) else { return nil }
                    return (url: normalized, depth: queued.depth)
                }
                // Rebuild the enqueued-URL set from the restored queue so the
                // dedup at enqueue is correct after resume. Schema-compatible:
                // we don't persist `enqueued` separately.
                enqueued = Set(queue.map(\.url.absoluteString))
                retryQueue = savedSession.retryQueue

                // Restore or initialize stats. The previous closure-form
                // `updateStatistics { if stats.startTime == nil { ... } }`
                // is now the dedicated `setStartTimeIfNil(_:)` actor method.
                await state.setStartTimeIfNil(savedSession.sessionStartTime)
            } else {
                // Clear stale session if start URL doesn't match
                if savedSession != nil {
                    logInfo("⚠️ Ignoring saved session (different start URL)")
                    await state.clearSessionState()
                }
                // Initialize stats for new crawl
                let startTime = Date()
                await state.setStatistics(Shared.Models.CrawlStatistics(startTime: startTime))

                // Initialize queue — seed from technologies.json for Apple docs root
                let isAppleDocs = configuration.startURL.host?.contains("developer.apple.com") == true
                let isDocsRoot = configuration.startURL.path == "/documentation"
                    || configuration.startURL.path == "/documentation/"

                if isAppleDocs, isDocsRoot {
                    do {
                        logInfo("📋 Fetching technology index for complete framework coverage...")
                        let frameworkURLs = try await Crawler.TechnologiesIndex.fetchFrameworkURLs()
                        queue = frameworkURLs.compactMap { url in
                            Shared.Models.URLUtilities.normalize(url).map { (url: $0, depth: 0) }
                        }
                        logInfo("   ✅ Seeded queue with \(frameworkURLs.count) framework root URLs")
                    } catch {
                        logInfo("   ⚠️ Failed to fetch technology index: \(error.localizedDescription)")
                        logInfo("   ⚠️ Falling back to start URL only")
                        let startURL = Shared.Models.URLUtilities.normalize(configuration.startURL) ?? configuration.startURL
                        queue = [(url: startURL, depth: 0)]
                    }
                } else {
                    let startURL = Shared.Models.URLUtilities.normalize(configuration.startURL) ?? configuration.startURL
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

                guard let normalizedURL = Shared.Models.URLUtilities.normalize(url),
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
                        retryQueue: retryQueue,
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
                } catch Error.httpErrorPage {
                    let delay = Self.deferredRetryDelay(forAttempt: 0)
                    retryQueue.append(Shared.Models.QueuedRetryURL(
                        url: normalizedURL.absoluteString,
                        attempts: 0,
                        nextAttempt: Date().addingTimeInterval(delay)
                    ))
                    await state.recordDeferredRetry()
                    logInfo("   🔁 Deferred \(normalizedURL.lastPathComponent) for retry in \(Int(delay))s (#292)")
                } catch {
                    await state.recordError()
                    logError("Error crawling \(normalizedURL.absoluteString): \(error)")
                }

                // Delay between requests
                try await Task.sleep(for: .seconds(configuration.requestDelay))
            }

            // Process URLs deferred due to HTTP error pages (#292)
            await processRetryQueue()

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
            var lastError: Swift.Error?

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
                } catch Error.httpErrorPage {
                    // Propagate immediately — the main loop handles deferral to retryQueue.
                    throw Error.httpErrorPage
                } catch {
                    lastError = error
                    logError("Attempt \(attempt + 1) failed for \(url.absoluteString): \(error)")
                }
            }

            // All retries exhausted
            throw lastError ?? Error.invalidState
        }

        // MARK: - Deferred Retry Queue (#292)

        /// Backoff delays for deferred retries: 30s → 5min → 30min.
        /// `attempt` is the number of retries already made (0 = about to make the 1st retry).
        static func deferredRetryDelay(forAttempt attempt: Int) -> TimeInterval {
            switch attempt {
            case 0: return 30
            case 1: return 300
            default: return 1800
            }
        }

        /// Process all URLs deferred due to HTTP error pages (#292).
        /// Runs after the main crawl queue is exhausted. Respects the per-URL
        /// `nextAttempt` timestamp, sleeping until the earliest window.
        /// Max 3 total attempts per URL; final failure writes to the rejection log.
        private func processRetryQueue() async {
            guard !retryQueue.isEmpty else { return }
            logInfo("🔄 Processing \(retryQueue.count) deferred retry URL(s)...")

            var pending = retryQueue
            retryQueue = []

            while !pending.isEmpty {
                let now = Date()
                var ready: [Shared.Models.QueuedRetryURL] = []
                var waiting: [Shared.Models.QueuedRetryURL] = []
                for item in pending {
                    if item.nextAttempt <= now { ready.append(item) } else { waiting.append(item) }
                }

                if ready.isEmpty {
                    guard let earliest = waiting.min(by: { $0.nextAttempt < $1.nextAttempt }) else { break }
                    let wait = earliest.nextAttempt.timeIntervalSinceNow
                    if wait > 0 {
                        logInfo("   ⏳ Waiting \(Int(wait))s for next retry window...")
                        try? await Task.sleep(for: .seconds(wait))
                    }
                    pending = waiting
                    continue
                }

                pending = waiting
                for var item in ready {
                    guard let url = URL(string: item.url) else { continue }
                    logInfo("   🔁 Retry attempt \(item.attempts + 1)/3: \(url.lastPathComponent)")
                    do {
                        try await crawlPage(url: url, depth: 0)
                        await state.recordRetrySucceeded()
                        logInfo("   ✅ Retry succeeded: \(url.lastPathComponent)")
                    } catch Error.httpErrorPage {
                        item.attempts += 1
                        if item.attempts >= 3 {
                            logInfo("   ⛔ All retries exhausted: \(url.lastPathComponent)")
                            let framework = Shared.Models.URLUtilities.extractFramework(from: url)
                            await state.recordRejection(
                                url: url,
                                framework: framework,
                                reason: .httpErrorTemplate,
                                outputDirectory: configuration.outputDirectory
                            )
                        } else {
                            let delay = Self.deferredRetryDelay(forAttempt: item.attempts)
                            item.nextAttempt = Date().addingTimeInterval(delay)
                            pending.append(item)
                            logInfo("   ↩️ Re-queued with \(Int(delay))s delay (attempt \(item.attempts + 1)/3 next)")
                        }
                    } catch {
                        logError("Retry failed for \(url.absoluteString): \(error)")
                        await state.recordError()
                    }
                }
            }
        }

        private func crawlPage(url: URL, depth: Int) async throws {
            let framework = Shared.Models.URLUtilities.extractFramework(from: url)

            // Get framework page count for display
            let fwStats = await state.getFrameworkStats(framework: framework)
            let fwPageCount = fwStats?.pageCount ?? 0

            let urlString = url.absoluteString
            let progress = "[\(visited.count)] [\(framework):\(fwPageCount + 1)]"
            logInfo("📄 \(progress) depth=\(depth) \(urlString)")

            // Try JSON API first (better data quality), fall back to HTML if unavailable
            var structuredPage: Shared.Models.StructuredDocumentationPage?
            var markdown: String
            var links: [URL]
            // storageURL is the post-redirect canonical URL used for all on-disk paths.
            // For HTML-only paths we have no redirect info, so we fall back to the request URL.
            var storageURL = url

            // Check if this URL could have a JSON API endpoint (Apple docs)
            let hasJSONEndpoint = appleJSONParser.jsonAPIURL(from: url) != nil

            // The HTML→markdown / link extraction calls below are synchronous
            // and allocate heavily through Foundation (NSString operations,
            // regex, JSON parsing). Wrap each in `autoreleasepool` so the
            // ephemeral NSObject buffers get released at the end of every
            // page instead of accumulating until the Task ends — critical for
            // multi-day crawls (e.g. v1.0 320k corpus on Claw Mini) where
            // the implicit Task-scoped pool would otherwise hoard megabytes
            // of pool buffers per thousand pages.
            // Discovery mode controls which path the crawler uses for content
            // and link extraction. See `Shared.Configuration.DiscoveryMode` for semantics.
            // The webview-only mode skips JSON entirely so we can produce a
            // clean WKWebView-discovered corpus alongside a JSON-only corpus
            // in a separate output directory, then diff the two metadata.json
            // files to measure the discovery gap. (#203 methodology)
            let mode = configuration.discoveryMode
            let useJSON = hasJSONEndpoint && mode != .webViewOnly

            if useJSON {
                do {
                    (structuredPage, markdown, links, storageURL) = try await loadPageViaJSON(url: url, depth: depth)
                    // Augment JSON-extracted links with HTML anchor-tag links when the
                    // page's JSON references dict is sparse. Catches URL patterns the
                    // DocC JSON omits (operator overloads, legacy numeric-IDs, REST
                    // sub-paths). Skipped on richly-cross-referenced pages where HTML
                    // would add nothing — keeps the per-page cost bounded to roughly
                    // the sparse third of Apple's corpus. (#203)
                    if mode == .auto,
                       configuration.htmlLinkAugmentation,
                       links.count < configuration.htmlLinkAugmentationMaxRefs,
                       let html = try? await loadPage(url: storageURL) {
                        let htmlLinks = autoreleasepool {
                            extractLinks(from: html, baseURL: storageURL)
                        }
                        let seen = Set(links.map(\.absoluteString))
                        let added = htmlLinks.filter { !seen.contains($0.absoluteString) }
                        if !added.isEmpty {
                            logInfo("   🔗 HTML augmentation: +\(added.count) links (page had \(links.count) JSON refs)")
                            links += added
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
                    if htmlParser.looksLikeHTTPErrorPage(html: html) {
                        logInfo("   ⏳ HTTP error template detected, deferring for retry (#292)")
                        throw Error.httpErrorPage
                    }
                    if htmlParser.looksLikeJavaScriptFallback(html: html) {
                        logInfo("   ⛔ Apple SPA no-content sub-view detected, skipping (#284)")
                        await state.recordRejection(
                            url: url,
                            framework: framework,
                            reason: .javaScriptFallback,
                            outputDirectory: configuration.outputDirectory
                        )
                        await state.recordError()
                        await state.recordTotalPage()
                        return
                    }
                    (markdown, links, structuredPage) = autoreleasepool {
                        (
                            htmlParser.convert(html: html, url: url),
                            extractLinks(from: html, baseURL: url),
                            htmlParser.toStructuredPage(html: html, url: url, source: .appleWebKit, depth: depth)
                        )
                    }
                }
            } else {
                // No JSON endpoint available, use HTML directly
                let html = try await loadPage(url: url)
                if htmlParser.looksLikeHTTPErrorPage(html: html) {
                    logInfo("   ⏳ HTTP error template detected, deferring for retry (#292)")
                    throw Error.httpErrorPage
                }
                if htmlParser.looksLikeJavaScriptFallback(html: html) {
                    logInfo("   ⛔ Apple SPA no-content sub-view detected, skipping (#284)")
                    await state.recordRejection(
                        url: url,
                        framework: framework,
                        reason: .javaScriptFallback,
                        outputDirectory: configuration.outputDirectory
                    )
                    await state.recordError()
                    await state.recordTotalPage()
                    return
                }
                (markdown, links, structuredPage) = autoreleasepool {
                    (
                        htmlParser.convert(html: html, url: url),
                        extractLinks(from: html, baseURL: url),
                        htmlParser.toStructuredPage(html: html, url: url, source: .appleWebKit, depth: depth)
                    )
                }
            }

            // Compute content hash from structured page or markdown
            let contentHash = structuredPage?.contentHash ?? Shared.Models.HashUtilities.sha256(of: markdown)

            // Derive output path from the canonical post-redirect URL so the on-disk
            // structure always reflects the final URL, not the stale request URL.
            let storageFramework = Shared.Models.URLUtilities.extractFramework(from: storageURL)
            let frameworkDir = configuration.outputDirectory.appendingPathComponent(storageFramework)
            try FileManager.default.createDirectory(
                at: frameworkDir,
                withIntermediateDirectories: true
            )

            let filename = Shared.Models.URLUtilities.filename(from: storageURL)

            // JSON file path (primary output format)
            let jsonFilePath = frameworkDir.appendingPathComponent(
                "\(filename)\(Shared.Constants.FileName.jsonExtension)"
            )

            // Markdown file path (optional, for backwards compatibility)
            let markdownFilePath = frameworkDir.appendingPathComponent(
                "\(filename)\(Shared.Constants.FileName.markdownExtension)"
            )

            // Check if we should recrawl (keyed on canonical URL)
            let shouldRecrawl = await state.shouldRecrawl(
                url: storageURL.absoluteString,
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
                await state.recordSkippedPage()
                await state.recordTotalPage()
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

            // Update metadata with framework tracking (keyed on canonical URL)
            await state.updatePage(
                url: storageURL.absoluteString,
                framework: storageFramework,
                filePath: jsonFilePath.path,
                contentHash: contentHash,
                depth: depth,
                isNew: isNew
            )

            // Update stats
            if isNew {
                await state.recordNewPage()
                logInfo("   ✅ Saved new page: \(jsonFilePath.lastPathComponent)")
            } else {
                await state.recordUpdatedPage()
                logInfo("   ♻️  Updated page: \(jsonFilePath.lastPathComponent)")
            }

            await state.recordTotalPage()

            // Notify progress
            if let progressObserver {
                let progress = await Crawler.AppleDocsProgress(
                    currentURL: url,
                    visitedCount: visited.count,
                    totalPages: configuration.maxPages,
                    stats: state.getStatistics()
                )
                progressObserver.observe(progress: progress)
            }
        }

        /// Load page via Apple's JSON API - avoids WKWebView memory issues
        /// Returns structured page data for JSON output, links for crawling, and the post-redirect canonical URL
        private func loadPageViaJSON(url: URL, depth: Int) async throws -> (
            structuredPage: Shared.Models.StructuredDocumentationPage?,
            markdown: String,
            links: [URL],
            canonicalURL: URL
        ) {
            guard let jsonURL = appleJSONParser.jsonAPIURL(from: url) else {
                throw Error.invalidState
            }

            logInfo("   📡 Using JSON API: \(jsonURL.lastPathComponent)")

            let (data, response) = try await URLSession.shared.data(from: jsonURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw Error.invalidHTML
            }

            // Derive the canonical documentation URL from the post-redirect JSON API response URL.
            // When Apple redirects a framework slug (e.g. professional_video_applications →
            // professional-video-applications), response.url reflects the final JSON API URL;
            // reversing it gives us the storage key that matches the canonical doc URL.
            let responseJSONURL = response.url ?? jsonURL
            let canonicalURL = appleJSONParser.documentationURL(from: responseJSONURL) ?? url

            if canonicalURL.absoluteString != url.absoluteString {
                logInfo("   🔀 Redirect detected: storing under \(canonicalURL.lastPathComponent)")
            }

            // Wrap the synchronous JSON parsing in `autoreleasepool` so the
            // NSData / NSDictionary / NSString buffers Foundation allocates
            // during decode get released at the end of this page instead of
            // accumulating in the implicit Task-scoped pool. See the comment
            // in the main crawl loop for the multi-day-crawl rationale.
            return try autoreleasepool {
                let structuredPage = appleJSONParser.toStructuredPage(json: data, url: canonicalURL, depth: depth)
                guard let markdown = appleJSONParser.convert(json: data, url: canonicalURL) else {
                    throw Error.invalidHTML
                }
                let links = appleJSONParser.extractLinks(from: data)
                return (structuredPage, markdown, links, canonicalURL)
            }
        }

        private func loadPage(url: URL) async throws -> String {
            // Delegate to WKWebCrawler's Crawler.WebKit.ContentFetcher
            try await webPageFetcher.fetch(url: url).content
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
            guard let normalized = Shared.Models.URLUtilities.normalize(url) else {
                return false
            }

            let normalizedString = normalized.absoluteString
            guard !visited.contains(normalizedString) else {
                return false
            }

            return !queue.contains { queuedURL, _ in
                Shared.Models.URLUtilities.normalize(queuedURL)?.absoluteString == normalizedString
            }
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            let memoryMsg = "\(String(format: "%.1f", getMemoryUsageMB()))MB | \(message)"
            logger.info(memoryMsg, category: .crawler)
            logToFile(memoryMsg)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            logger.error(errorMessage, category: .crawler)
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
                "   Elapsed: \(Shared.Utils.Formatting.formatDurationVerbose(elapsed))",
                "   ETA: \(Shared.Utils.Formatting.formatDurationVerbose(etaSeconds))",
                "",
            ]

            for message in messages {
                logger.info(message, category: .crawler)
            }
        }

        private func logStatistics() async {
            let stats = await state.getStatistics()
            var messages = [
                "📊 Statistics:",
                "   Total pages processed: \(stats.totalPages)",
                "   New pages: \(stats.newPages)",
                "   Updated pages: \(stats.updatedPages)",
                "   Skipped (unchanged): \(stats.skippedPages)",
                "   Errors: \(stats.errors)",
            ]
            if stats.deferredRetries > 0 {
                messages.append("   Deferred retries: \(stats.deferredRetries)")
                messages.append("   Retries succeeded: \(stats.retriesSucceeded)")
            }
            messages.append(contentsOf: [
                stats.duration.map { "   Duration: \(Shared.Utils.Formatting.formatDurationVerbose($0))" } ?? "",
                "",
                "📁 Output: \(configuration.outputDirectory.path)",
            ])

            for message in messages where !message.isEmpty {
                logger.info(message, category: .crawler)
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
                // #682 — intentional silent failure on synchronize().
                // The line was already written via handle.write(data)
                // above; synchronize is the explicit fsync for durability
                // guarantees. If it fails (rare — would indicate disk
                // pressure or the fs detached the file mid-write), the
                // data is still in the kernel buffer and will get flushed
                // on file close or next fsync. Worst case: log is up to
                // one fsync interval stale. Surfacing via a per-line
                // warn would spam during an outage; we accept the silent
                // skip + rely on the close path's synchronize to catch up.
                try? handle.synchronize()
            }
        }

        private func getMemoryUsageMB() -> Double {
            // Delegate to WKWebCrawler's Crawler.WebKit.ContentFetcher
            webPageFetcher.getMemoryUsageMB()
        }

        private func recycleWebView() async {
            let memBefore = getMemoryUsageMB()
            // Delegate to WKWebCrawler's Crawler.WebKit.ContentFetcher
            webPageFetcher.recycle()
            let memAfter = getMemoryUsageMB()
            let before = String(format: "%.1f", memBefore)
            let after = String(format: "%.1f", memAfter)
            logInfo("♻️ Recycled Crawler.WebKit.ContentFetcher: \(before)MB → \(after)MB")
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

            let priorityList = try await priorityPackageStrategy.generate(
                swiftOrgDocsPath: configuration.outputDirectory,
                outputPath: outputPath
            )

            logInfo("   ✅ Found \(priorityList.totalUniqueReposFound) unique packages")
            logInfo("   📁 Saved to: \(outputPath.path)")
            logInfo("   💡 This list will be used for prioritizing package documentation crawls")
        }
    }
}

// MARK: - Crawler Errors

extension Crawler.AppleDocs {
    public enum Error: Swift.Error, LocalizedError, Sendable {
        case timeout
        case invalidState
        case invalidHTML
        case unsupportedPlatform
        /// Apple's CDN served a styled HTTP error page (502/429/403 at HTTP 200).
        /// Thrown by `crawlPage` so callers can defer the URL for retry (#292).
        case httpErrorPage

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
            case .httpErrorPage:
                return "HTTP error template page received"
            }
        }
    }
}

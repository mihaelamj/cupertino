import Foundation
import WebKit
import DocsuckerShared

// MARK: - Documentation Crawler

/// Main crawler for Apple documentation using WKWebView
@MainActor
public final class DocumentationCrawler: NSObject {
    private let configuration: CrawlerConfiguration
    private let changeDetection: ChangeDetectionConfiguration
    private let output: OutputConfiguration
    private let state: CrawlerState

    private var webView: WKWebView!
    private var visited = Set<String>()
    private var queue: [(url: URL, depth: Int)] = []
    private var stats: CrawlStatistics

    private var onProgress: ((CrawlProgress) -> Void)?

    public init(configuration: DocsuckerConfiguration) async {
        self.configuration = configuration.crawler
        self.changeDetection = configuration.changeDetection
        self.output = configuration.output
        self.state = CrawlerState(configuration: configuration.changeDetection)
        self.stats = CrawlStatistics()
        super.init()

        // Initialize WKWebView
        let webConfiguration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: webConfiguration)
        self.webView.navigationDelegate = self
    }

    // MARK: - Public API

    /// Start crawling from the configured start URL
    public func crawl(onProgress: ((CrawlProgress) -> Void)? = nil) async throws -> CrawlStatistics {
        self.onProgress = onProgress

        // Initialize stats in state
        let startTime = Date()
        await state.updateStatistics { stats in
            stats = CrawlStatistics(startTime: startTime)
        }

        // Create output directory
        try FileManager.default.createDirectory(
            at: configuration.outputDirectory,
            withIntermediateDirectories: true
        )

        // Initialize queue
        queue = [(url: configuration.startURL, depth: 0)]

        // Log start
        logInfo("🚀 Starting crawl")
        logInfo("   Start URL: \(configuration.startURL.absoluteString)")
        logInfo("   Max pages: \(configuration.maxPages)")
        logInfo("   Output: \(configuration.outputDirectory.path)")

        // Crawl loop
        while !queue.isEmpty && visited.count < configuration.maxPages {
            let (url, depth) = queue.removeFirst()

            guard let normalizedURL = URLUtilities.normalize(url),
                  !visited.contains(normalizedURL.absoluteString)
            else {
                continue
            }

            visited.insert(normalizedURL.absoluteString)

            do {
                try await crawlPage(url: normalizedURL, depth: depth)
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
        try await state.finalizeCrawl(stats: finalStats)

        logInfo("\n✅ Crawl completed!")
        await logStatistics()

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
        let filePath = frameworkDir.appendingPathComponent("\(filename).md")

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
            for link in links {
                if shouldVisit(url: link) {
                    queue.append((url: link, depth: depth + 1))
                }
            }
        }

        // Notify progress
        if let onProgress {
            let progress = CrawlProgress(
                currentURL: url,
                visitedCount: visited.count,
                totalPages: configuration.maxPages,
                stats: await state.getStatistics()
            )
            onProgress(progress)
        }
    }

    private func loadPage(url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            webView.load(URLRequest(url: url))

            // Set timeout
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(30))
                continuation.resume(throwing: CrawlerError.timeout)
            }

            // Wait for load to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                timeoutTask.cancel()

                guard let self else {
                    continuation.resume(throwing: CrawlerError.invalidState)
                    return
                }

                self.webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let html = result as? String {
                        continuation.resume(returning: html)
                    } else {
                        continuation.resume(throwing: CrawlerError.invalidHTML)
                    }
                }
            }
        }
    }

    private func extractLinks(from html: String, baseURL: URL) -> [URL] {
        var links: [URL] = []

        // Extract href attributes from <a> tags
        let pattern = #"<a[^>]*href=[\"']([^\"']*)[\"']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsString = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if match.numberOfRanges >= 2 {
                    let hrefRange = match.range(at: 1)
                    let href = nsString.substring(with: hrefRange)

                    // Resolve relative URLs
                    if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                        links.append(url)
                    }
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
        print(message)
    }

    private func logError(_ message: String) {
        fputs("❌ \(message)\n", stderr)
    }

    private func logStatistics() async {
        let stats = await state.getStatistics()
        print("📊 Statistics:")
        print("   Total pages processed: \(stats.totalPages)")
        print("   New pages: \(stats.newPages)")
        print("   Updated pages: \(stats.updatedPages)")
        print("   Skipped (unchanged): \(stats.skippedPages)")
        print("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            print("   Duration: \(Int(duration))s")
        }
        print("\n📁 Output: \(configuration.outputDirectory.path)")
    }
}

// MARK: - WKNavigationDelegate

extension DocumentationCrawler: WKNavigationDelegate {
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

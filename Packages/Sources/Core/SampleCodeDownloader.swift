import Foundation
import Logging
import Shared
import WebKit
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Sample Code Downloader

// swiftlint:disable type_body_length function_body_length
// Justification: This file contains a complete sample code downloading system
// with WebKit integration for authentication and download handling. Components include:
// - WebKit webview management and navigation delegation
// - Authentication cookie handling (loading/saving)
// - Download progress tracking and file management
// - ZIP/TAR archive extraction
// - State machine for download workflow (authentication, extraction, cleanup)
// - Statistics tracking and logging
// The class manages complex async workflows with browser automation and must handle
// multiple edge cases (authentication, redirects, different archive formats).
// Splitting would separate tightly-coupled browser automation logic and make debugging harder.
// File length: 583 lines | Type body length: 400+ lines | Function body length: 70+ lines
// Disabling: file_length (400 line limit), type_body_length (250 line limit),
//            function_body_length (50 line limit for complex download workflows)

/// Downloads Apple sample code projects (zip/tar files)
@MainActor
public final class SampleCodeDownloader {
    private let outputDirectory: URL
    private let maxSamples: Int?
    private let forceDownload: Bool
    private let visibleBrowser: Bool
    private let sampleCodeListURL = Shared.Constants.BaseURL.appleSampleCode
    private let cookiesPath: URL

    private var sharedWebView: WKWebView?

    public init(
        outputDirectory: URL,
        maxSamples: Int? = nil,
        forceDownload: Bool = false,
        visibleBrowser: Bool = false
    ) {
        self.outputDirectory = outputDirectory
        self.maxSamples = maxSamples
        self.forceDownload = forceDownload
        self.visibleBrowser = visibleBrowser

        // Store cookies in output directory
        cookiesPath = outputDirectory.appendingPathComponent(Shared.Constants.FileName.authCookies)
    }

    // MARK: - Public API

    /// Download sample code projects
    public func download(onProgress: (@Sendable (SampleProgress) -> Void)? = nil) async throws -> SampleStatistics {
        var stats = SampleStatistics(startTime: Date())

        logInfo("🚀 Starting sample code downloader")
        logInfo("   Source: \(sampleCodeListURL)")
        logInfo("   Output: \(outputDirectory.path)")

        // Create output directory
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        // Show authentication prompt if requested
        if visibleBrowser {
            try await showAuthenticationPrompt()
            logInfo("")
        }

        // Fetch sample list
        logInfo("\n📋 Fetching sample code list...")
        let samples = try await fetchSampleList()
        logInfo("   Found \(samples.count) samples")

        // Limit if needed
        let samplesToDownload = if let maxSamples {
            Array(samples.prefix(maxSamples))
        } else {
            samples
        }

        logInfo("   Downloading \(samplesToDownload.count) samples\n")

        // Download each sample
        for (index, sample) in samplesToDownload.enumerated() {
            do {
                try await downloadSample(sample, stats: &stats)

                // Progress callback
                if let onProgress {
                    let progress = SampleProgress(
                        current: index + 1,
                        total: samplesToDownload.count,
                        sampleName: sample.name,
                        stats: stats
                    )
                    onProgress(progress)
                }

                // Rate limiting - be respectful to Apple's servers
                try await Task.sleep(for: Shared.Constants.Delay.sampleCodeBetweenPages)
            } catch {
                stats.errors += 1
                logError("Failed to download \(sample.name): \(error)")
            }
        }

        stats.endTime = Date()

        logInfo("\n✅ Download completed!")
        logStatistics(stats)

        return stats
    }

    // MARK: - Private Methods

    private func fetchSampleList() async throws -> [SampleMetadata] {
        // Load the sample code listing page
        let webView = await createWebView()
        _ = try await loadPage(webView, url: URL(string: sampleCodeListURL)!)

        // Wait extra time for dynamic content to load
        try await Task.sleep(for: Shared.Constants.Delay.sampleCodePageLoad)

        // Extract samples using JavaScript
        let samples = try await extractSamplesWithJavaScript(webView)

        return samples
    }

    private func extractSamplesWithJavaScript(_ webView: WKWebView) async throws -> [SampleMetadata] {
        // Use JavaScript to extract all sample code links from the rendered page
        let script = """
        (function() {
            const samples = [];
            const links = document.querySelectorAll('a[href*="/documentation/"]');

            links.forEach(link => {
                const href = link.getAttribute('href');
                const text = link.textContent.trim();

                // Filter for actual sample pages (not navigation, not the main SampleCode page)
                if (href && text &&
                    !href.includes('#') &&
                    href !== '/documentation/SampleCode' &&
                    href !== '/documentation/samplecode/' &&
                    href.split('/').length >= 3 &&
                    text.length > 5) {

                    samples.push({
                        url: href.startsWith('http') ? href : 'https://developer.apple.com' + href,
                        name: text
                    });
                }
            });

            // Remove duplicates
            const unique = [];
            const seen = new Set();
            samples.forEach(sample => {
                if (!seen.has(sample.url)) {
                    seen.add(sample.url);
                    unique.push(sample);
                }
            });

            return unique;
        })();
        """

        let result = try await webView.evaluateJavaScript(script)

        guard let samplesArray = result as? [[String: Any]] else {
            logInfo("⚠️  Failed to extract samples, got: \(type(of: result))")
            return []
        }

        var samples: [SampleMetadata] = []
        for sampleDict in samplesArray {
            guard let urlString = sampleDict["url"] as? String,
                  let name = sampleDict["name"] as? String else {
                continue
            }

            let slug = urlString
                .replacingOccurrences(of: Shared.Constants.BaseURL.appleDeveloperDocs, with: "")
                .replacingOccurrences(of: "/", with: "-")
                .lowercased()

            let sample = SampleMetadata(name: name, url: urlString, slug: slug)
            samples.append(sample)
        }

        return samples
    }

    private func downloadSample(
        _ sample: SampleMetadata,
        stats: inout SampleStatistics
    ) async throws {
        logInfo("📦 [\(stats.totalSamples + 1)] \(sample.name)")

        // Check if already downloaded
        let existingFiles = try? FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(sample.slug) }

        if !forceDownload, !(existingFiles?.isEmpty ?? true) {
            stats.skippedSamples += 1
            stats.totalSamples += 1
            logInfo("   ⏭️  Already exists, skipping")
            return
        }

        // Load sample page to find download link
        let webView = await createWebView()
        _ = try await loadPage(webView, url: URL(string: sample.url)!)

        // Wait for page to fully load
        try await Task.sleep(for: Shared.Constants.Delay.sampleCodeInteraction)

        // Find download link using JavaScript
        guard let downloadURL = try await findDownloadLinkWithJavaScript(webView, sampleURL: sample.url) else {
            throw SampleDownloaderError.downloadLinkNotFound(sample.name)
        }

        logInfo("   📥 Downloading from: \(downloadURL)")

        // Download the file
        let (tempFileURL, response) = try await URLSession.shared.download(from: downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SampleDownloaderError.downloadFailed(sample.name)
        }

        // Determine file extension from Content-Type or URL
        let fileExtension = determineFileExtension(from: response, url: downloadURL)

        // Move to output directory with clean filename
        let filename = "\(sample.slug).\(fileExtension)"
        let destinationURL = outputDirectory.appendingPathComponent(filename)

        // Remove existing file if force download
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)

        stats.downloadedSamples += 1
        stats.totalSamples += 1
        logInfo("   ✅ Saved: \(filename)")
    }

    private func findDownloadLinkWithJavaScript(_ webView: WKWebView, sampleURL: String) async throws -> URL? {
        // Use JavaScript to find download links
        let script = """
        (function() {
            // Look for download buttons/links
            const downloadLinks = [];

            // Check for links with "download" text or containing .zip/.tar.gz
            const allLinks = document.querySelectorAll('a');
            allLinks.forEach(link => {
                const href = link.getAttribute('href');
                const text = link.textContent.toLowerCase();

                if (href) {
                    // Priority 1: Direct zip/tar.gz links
                    if (href.endsWith('.zip') || href.endsWith('.tar.gz')) {
                        downloadLinks.push({ href: href, priority: 1 });
                    }
                    // Priority 2: Links with "download" in URL
                    else if (href.includes('download')) {
                        downloadLinks.push({ href: href, priority: 2 });
                    }
                    // Priority 3: Links with download text
                    else if (text.includes('download') || text.includes('sample code')) {
                        downloadLinks.push({ href: href, priority: 3 });
                    }
                }
            });

            // Sort by priority and return first match
            if (downloadLinks.length > 0) {
                downloadLinks.sort((a, b) => a.priority - b.priority);
                return downloadLinks[0].href;
            }

            return null;
        })();
        """

        if let result = try await webView.evaluateJavaScript(script) as? String {
            // Convert relative URLs to absolute
            if result.hasPrefix("http") {
                return URL(string: result)
            } else if result.hasPrefix("/") {
                return URL(string: "\(Shared.Constants.BaseURL.appleDeveloper)\(result)")
            } else {
                // Relative to current page
                if let baseURL = URL(string: sampleURL) {
                    return URL(string: result, relativeTo: baseURL)?.absoluteURL
                }
            }
        }

        return nil
    }

    private func determineFileExtension(from response: URLResponse, url: URL) -> String {
        // Check Content-Type header
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            if contentType.contains("zip") {
                return "zip"
            } else if contentType.contains("gzip") || contentType.contains("tar") {
                return "tar.gz"
            }
        }

        // Check URL path extension
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }

        // Check if URL path contains .tar.gz
        if url.path.contains(".tar.gz") {
            return "tar.gz"
        }

        // Default to zip
        return "zip"
    }

    private func createWebView() async -> WKWebView {
        // Reuse the same webview to maintain session
        if let existing = sharedWebView {
            return existing
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Use default to persist cookies

        #if os(macOS)
        let frame: CGRect
        if visibleBrowser {
            // Create visible window for authentication
            frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        } else {
            frame = .zero
        }
        #else
        let frame = CGRect.zero
        #endif

        let webView = WKWebView(frame: frame, configuration: config)
        webView.customUserAgent = """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
        AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15
        """

        // Load saved cookies
        await loadCookies(into: webView)

        sharedWebView = webView
        return webView
    }

    private func showAuthenticationPrompt() async throws {
        logInfo("🔐 Authentication required")
        logInfo("   Opening browser window for sign in...")
        logInfo("   Please sign in to your Apple Developer account")
        logInfo("")

        #if os(macOS)
        if visibleBrowser {
            // Create webview with proper frame
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))

            // Load saved cookies first
            await loadCookies(into: webView)

            // Create and show window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Apple Developer Sign In"
            window.contentView = webView
            window.center()
            window.isReleasedWhenClosed = false // Important: keep window alive

            // Load Apple Developer login page
            let loginURL = URL(string: Shared.Constants.BaseURL.appleDeveloperAccount)!
            webView.load(URLRequest(url: loginURL))

            // Show window
            window.makeKeyAndOrderFront(nil)

            // Activate app to bring window to front
            NSApp.activate(ignoringOtherApps: true)

            logInfo("✅ Browser window opened")
            logInfo("   Sign in to your Apple Developer account")
            logInfo("   Press Enter when you're done signing in...")

            // Wait for user to press enter
            // Note: Using Task.detached to avoid blocking MainActor with synchronous readLine()
            await Task.detached {
                _ = readLine()
            }.value

            // Save cookies
            await saveCookies(from: webView)

            window.close()
            logInfo("✅ Authentication complete, cookies saved")
        }
        #endif
    }

    private func loadCookies(into webView: WKWebView) async {
        guard FileManager.default.fileExists(atPath: cookiesPath.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: cookiesPath)
            let cookieData = try JSONDecoder().decode([CookieData].self, from: data)

            for cookieInfo in cookieData {
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: cookieInfo.name,
                    .value: cookieInfo.value,
                    .domain: cookieInfo.domain,
                    .path: cookieInfo.path,
                ]

                if let expiresDate = cookieInfo.expiresDate {
                    properties[.expires] = expiresDate
                }

                if cookieInfo.isSecure {
                    properties[.secure] = true
                }

                if let cookie = HTTPCookie(properties: properties) {
                    await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }

            logInfo("   Loaded \(cookieData.count) saved cookies")
        } catch {
            logError("Failed to load cookies: \(error)")
        }
    }

    private func saveCookies(from webView: WKWebView) async {
        do {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

            // Filter for Apple-related cookies
            let appleCookies = cookies.filter { cookie in
                cookie.domain.contains(Shared.Constants.HostDomain.appleCom)
            }

            let cookieData = appleCookies.map { cookie in
                CookieData(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    expiresDate: cookie.expiresDate,
                    isSecure: cookie.isSecure
                )
            }

            let data = try JSONEncoder().encode(cookieData)
            try data.write(to: cookiesPath)

            logInfo("   Saved \(cookieData.count) cookies to \(cookiesPath.path)")
        } catch {
            logError("Failed to save cookies: \(error)")
        }
    }

    private func loadPage(_ webView: WKWebView, url: URL) async throws -> String {
        // Load the page
        _ = webView.load(URLRequest(url: url))

        // Wait for page to fully render
        try await Task.sleep(for: Shared.Constants.Delay.sampleCodeDownload)

        // Get HTML content
        let html = try await webView.evaluateJavaScript(Shared.Constants.JavaScript.getDocumentHTML) as? String ?? ""

        return html
    }

    // MARK: - Logging

    private func logInfo(_ message: String) {
        Log.info(message, category: .samples)
    }

    private func logError(_ message: String) {
        let errorMessage = "❌ \(message)"
        Log.error(errorMessage, category: .samples)
    }

    private func logStatistics(_ stats: SampleStatistics) {
        let messages = [
            "📊 Statistics:",
            "   Total samples: \(stats.totalSamples)",
            "   Downloaded: \(stats.downloadedSamples)",
            "   Skipped: \(stats.skippedSamples)",
            "   Errors: \(stats.errors)",
            stats.duration.map { "   Duration: \(Int($0))s" } ?? "",
            "",
            "📁 Output: \(outputDirectory.path)",
        ]

        for message in messages where !message.isEmpty {
            Log.info(message, category: .samples)
        }
    }
}

// MARK: - Models

struct SampleMetadata {
    let name: String
    let url: String
    let slug: String
}

public struct SampleStatistics: Sendable {
    public var totalSamples: Int = 0
    public var downloadedSamples: Int = 0
    public var skippedSamples: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalSamples: Int = 0,
        downloadedSamples: Int = 0,
        skippedSamples: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalSamples = totalSamples
        self.downloadedSamples = downloadedSamples
        self.skippedSamples = skippedSamples
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

public struct SampleProgress: Sendable {
    public let current: Int
    public let total: Int
    public let sampleName: String
    public let stats: SampleStatistics

    public var percentage: Double {
        Double(current) / Double(total) * 100
    }
}

// MARK: - Errors

enum SampleDownloaderError: Error {
    case downloadLinkNotFound(String)
    case downloadFailed(String)
    case invalidResponse
}

// MARK: - Cookie Storage

struct CookieData: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
}

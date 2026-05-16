import CoreSampleCodeModels
import Foundation
import LoggingModels
import WebKit
#if canImport(AppKit)
import AppKit
import SharedConstants
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

extension Sample.Core {
    /// Downloads Apple sample code projects (zip/tar files)
    @MainActor
    public final class Downloader {
        #if os(macOS)
        /// Activation policy required to make the authentication window appear (#6).
        /// A bare CLI process defaults to `.prohibited`, which silently drops
        /// `NSWindow.makeKeyAndOrderFront` calls. `.regular` lets the window server
        /// display the auth window; a transient Dock icon is acceptable.
        /// `nonisolated` because it's a constant that doesn't read `NSApp` state.
        /// Exposed for direct test coverage — any regression to `.prohibited` or
        /// `.accessory` will fail `SampleCodeAuthPolicyTests`.
        nonisolated static var authFlowActivationPolicy: NSApplication.ActivationPolicy {
            .regular
        }
        #endif

        private let outputDirectory: URL
        private let maxSamples: Int?
        private let forceDownload: Bool
        private let visibleBrowser: Bool
        private let sampleCodeListURL = Shared.Constants.BaseURL.appleSampleCode
        private let cookiesPath: URL
        /// GoF Strategy seam for log emission (1994 p. 315). Declared
        /// `nonisolated` because the WKNavigationDelegate callbacks
        /// (e.g. `webView(_:didFail:withError:)`) are also `nonisolated`
        /// and need direct access without an actor hop. Safe because
        /// `Logging.Recording` is `Sendable`.
        private nonisolated let logger: any LoggingModels.Logging.Recording

        /// GoF Strategy seam (1994 p. 315) for the "is stdin a TTY?" check.
        /// Replaces the deleted `nonisolated(unsafe) static var
        /// _isInteractiveStdinOverride` test seam with constructor
        /// injection. Production default is `Sample.Core.LiveInteractiveStdinCheck`
        /// (calls `isatty(fileno(stdin))`); tests pass a stub returning
        /// a fixed `Bool`.
        private nonisolated let interactiveStdinCheck: any Sample.Core.InteractiveStdinChecking

        private var sharedWebView: WKWebView?

        public init(
            outputDirectory: URL,
            maxSamples: Int? = nil,
            forceDownload: Bool = false,
            visibleBrowser: Bool = false,
            logger: any LoggingModels.Logging.Recording,
            interactiveStdinCheck: any Sample.Core.InteractiveStdinChecking = Sample.Core.LiveInteractiveStdinCheck()
        ) {
            self.outputDirectory = outputDirectory
            self.maxSamples = maxSamples
            self.forceDownload = forceDownload
            self.visibleBrowser = visibleBrowser
            self.logger = logger
            self.interactiveStdinCheck = interactiveStdinCheck

            // Store cookies in output directory
            cookiesPath = outputDirectory.appendingPathComponent(Shared.Constants.FileName.authCookies)
        }

        // MARK: - Public API

        /// Download sample code projects.
        ///
        /// `progress` is a GoF Observer (1994 p. 293) replacing the
        /// previous `((Sample.Core.Progress) -> Void)?` closure. The
        /// Observer protocol + payload value type live in the
        /// foundation-only `CoreSampleCodeModels` seam target
        /// (`Sample.Core.DownloaderProgressObserving` /
        /// `Sample.Core.Progress`) so any conformer can implement
        /// without `import CoreSampleCode` pulling in WebKit / AppKit.
        public func download(
            progress: (any Sample.Core.DownloaderProgressObserving)? = nil
        ) async throws -> Sample.Core.Statistics {
            var stats = Sample.Core.Statistics(startTime: Date())

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

                    // Observer notify
                    if let progress {
                        let event = Sample.Core.Progress(
                            current: index + 1,
                            total: samplesToDownload.count,
                            sampleName: sample.name,
                            stats: stats
                        )
                        progress.observe(progress: event)
                    }

                    // Rate limiting - be respectful to Apple's servers
                    try await Task.sleep(for: Shared.Constants.Delay.sampleCodeBetweenPages)
                } catch {
                    stats.errors += 1
                    logError("Failed to download \(sample.name): \(error)")
                }
            }

            stats.endTime = Date()

            // Write a fresh catalog.json next to the downloaded zips. After #215
            // there is no embedded fallback — this file is the only source the
            // search-index builder will read. If this write fails the user has
            // to re-run fetch (or hand-roll a catalog.json); save will skip
            // sample-code indexing with a clear hint pointing back here.
            // Source: Apple's `tutorials/data/documentation/samplecode.json`.
            await writeCatalogJSON()

            logInfo("\n✅ Download completed!")
            logStatistics(stats)

            return stats
        }

        /// Fetch Apple's sample-code listing JSON and write a `catalog.json`
        /// next to the downloaded zips, in the same shape as
        /// `SampleCodeCatalogJSON`. Best-effort; logs and returns on any error.
        /// Exposed `internal` so tests can drive it independently of a full
        /// `download()` run.
        func writeCatalogJSON() async {
            let catalogURL = outputDirectory.appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)
            do {
                guard let listingURL = URL(string: Shared.Constants.BaseURL.appleSampleCodeJSON) else {
                    logError("Could not construct Apple sample-code listing URL — skipping catalog.json write.")
                    return
                }
                let (data, _) = try await URLSession.shared.data(from: listingURL)
                guard let catalog = Self.transformAppleListingToCatalog(data: data) else {
                    logError("Could not transform Apple sample-code listing — skipping catalog.json write.")
                    return
                }
                try Self.writeCatalog(catalog, to: catalogURL)
                logInfo("📝 Wrote sample-code catalog: \(catalogURL.path) (\(catalog.count) entries)")
            } catch {
                logError("Failed to write catalog.json (\(error)) — `cupertino save` will skip sample-code indexing.")
            }
        }

        /// Pure write step: serialize `catalog` to `url` atomically. Extracted
        /// from `writeCatalogJSON` so unit tests can exercise the disk
        /// behaviour without touching the network. `nonisolated` because
        /// there's no instance state — it's a static utility.
        nonisolated static func writeCatalog(_ catalog: SampleCodeCatalogJSON, to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(catalog)
            try encoded.write(to: url, options: .atomic)
        }

        /// Transform Apple's `tutorials/data/documentation/samplecode.json` into
        /// a `SampleCodeCatalogJSON`. Returns nil when the input doesn't decode
        /// as expected. Pure on its inputs (no instance state, no MainActor
        /// hop) so tests can call it directly from any context.
        nonisolated static func transformAppleListingToCatalog(data: Data) -> SampleCodeCatalogJSON? {
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let refs = raw["references"] as? [String: [String: Any]] else {
                return nil
            }

            var entries: [Sample.Core.Entry] = []
            for (_, ref) in refs {
                guard ref["role"] as? String == "sampleCode",
                      let title = ref["title"] as? String,
                      let urlString = ref["url"] as? String else {
                    continue
                }

                // framework + slug from /documentation/<Framework>/<slug>
                let parts = urlString.split(separator: "/").map(String.init)
                guard parts.count >= 3 else { continue }
                let framework = parts[1]
                let slug = parts[2...].joined(separator: "/")

                // description from abstract array
                var description = ""
                if let abstract = ref["abstract"] as? [[String: Any]] {
                    description = abstract.compactMap { $0["text"] as? String }.joined()
                }

                let zipFilename = "\(framework.lowercased().replacingOccurrences(of: "_", with: "-"))-\(slug).zip"
                let webURL = "\(Shared.Constants.BaseURL.appleDeveloper)\(urlString)"

                entries.append(Sample.Core.Entry(
                    title: title,
                    url: urlString,
                    framework: framework,
                    description: description,
                    zipFilename: zipFilename,
                    webURL: webURL
                ))
            }

            entries.sort { lhs, rhs in
                if lhs.framework.lowercased() == rhs.framework.lowercased() {
                    return lhs.title.lowercased() < rhs.title.lowercased()
                }
                return lhs.framework.lowercased() < rhs.framework.lowercased()
            }

            let now = ISO8601DateFormatter().string(from: Date())
            return SampleCodeCatalogJSON(
                version: "fetched",
                lastCrawled: now,
                count: entries.count,
                entries: entries
            )
        }

        // MARK: - Private Methods

        private func fetchSampleList() async throws -> [SampleMetadata] {
            // Load the sample code listing page
            let webView = await createWebView()
            _ = try await loadPage(webView, url: URL(knownGood: sampleCodeListURL))

            // Wait extra time for dynamic content to load
            try await Task.sleep(for: Shared.Constants.Delay.sampleCodePageLoad)

            // Extract samples using JavaScript
            return try await extractSamplesWithJavaScript(webView)
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

        func downloadSample(
            _ sample: SampleMetadata,
            stats: inout Sample.Core.Statistics
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

            // Validate sample.url before allocating an expensive WKWebView so a
            // malformed catalog row short-circuits without WebKit work.
            guard let samplePageURL = URL(string: sample.url) else {
                logInfo("   ⚠️  Malformed sample.url, skipping: \(sample.url)")
                stats.errors += 1
                stats.totalSamples += 1
                return
            }

            // Load sample page to find download link
            let webView = await createWebView()
            _ = try await loadPage(webView, url: samplePageURL)

            // Wait for page to fully load
            try await Task.sleep(for: Shared.Constants.Delay.sampleCodeInteraction)

            // Find download link using JavaScript
            guard let downloadURL = try await findDownloadLinkWithJavaScript(webView, sampleURL: sample.url) else {
                throw Error.downloadLinkNotFound(sample.name)
            }

            logInfo("   📥 Downloading from: \(downloadURL)")

            // Download the file
            let (tempFileURL, response) = try await URLSession.shared.download(from: downloadURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw Error.downloadFailed(sample.name)
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

            // #657 — Apple's CDN occasionally returns an HTML landing
            // page or a partial body with HTTP 200 (transient CDN
            // issues, redirect chains, auth gates). The fetcher just
            // saw `httpResponse.statusCode == 200` and trusted the
            // body. Validate the on-disk artefact with a 4-byte magic-
            // signature check before declaring the download a success.
            // Invalid downloads are renamed to `<filename>.invalid` so
            // they don't pollute the directory or trip up `cupertino
            // save --samples` later, and counted in a new statistics
            // bucket so the fetch summary surfaces the failure mode
            // instead of hiding it under the "downloaded" total.
            if fileExtension == "zip", !Shared.Utils.ZipMagic.isValid(at: destinationURL) {
                let invalidURL = destinationURL.appendingPathExtension("invalid")
                if FileManager.default.fileExists(atPath: invalidURL.path) {
                    try? FileManager.default.removeItem(at: invalidURL)
                }
                try? FileManager.default.moveItem(at: destinationURL, to: invalidURL)
                logInfo("   ⚠️  Downloaded body isn't a valid ZIP (likely HTML landing page or partial); parked at \(invalidURL.lastPathComponent)")
                stats.invalidDownloads += 1
                stats.totalSamples += 1
                return
            }

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
            guard visibleBrowser else { return }

            // Fix for #6: a bare CLI process is created with activation policy
            // `.prohibited`, which makes `NSWindow.makeKeyAndOrderFront` a silent
            // no-op. Flip to `.regular` so the auth window actually appears
            // (transient Dock icon is acceptable), then flip back on exit.
            //
            // Use `NSApplication.shared` rather than `NSApp`: in a bare Swift CLI,
            // `NSApp` is an implicitly-unwrapped nil until `.shared` materializes it.
            NSApplication.shared.setActivationPolicy(Self.authFlowActivationPolicy)

            // Call `finishLaunching()` explicitly — `NSApplication.run()` normally
            // does this, but we don't use `.run()`. Without it the CA runloop
            // observer that commits WKWebView layers isn't attached.
            NSApplication.shared.finishLaunching()
            defer { NSApplication.shared.setActivationPolicy(.prohibited) }

            // Explicit config so the auth WebView uses the persistent cookie jar.
            // We do NOT set `customUserAgent` here: idmsa.apple.com returns 403 to
            // our spoofed Safari UA (verified with curl during #6 deep-dive). Let
            // WebKit send its native Safari-compatible UA, which idmsa accepts.
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
            await loadCookies(into: webView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Apple Developer Sign In"
            window.contentView = webView
            window.center()
            window.isReleasedWhenClosed = false

            let loginURL = try URL(knownGood: Shared.Constants.BaseURL.appleDeveloperAccount)

            // NOTE: show the window BEFORE load()+delegate wiring so the user
            // immediately sees something; but do NOT call webView.load() here —
            // the delegate must be attached first, otherwise the initial
            // navigation's success/failure is invisible (cause of #6's empty-
            // window diagnosis: didFailProvisionalNavigation couldn't log because
            // the delegate wasn't attached yet).
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            // Surface progress on stdout (bypasses logger.info's category router
            // which in visible-browser invocations wasn't reaching stdout).
            logger.info("✅ Browser window opened")
            logger.info("   Sign in to your Apple Developer account")
            if interactiveStdinCheck.isInteractive() {
                logger.info("   The window closes automatically when sign-in is detected.")
                logger.info("   (Or close the window / press Enter here to finish.)")
            } else {
                logger.info("   The window closes automatically when sign-in is detected.")
                logger.info("   (Or close the window to finish, stdin is not a TTY.)")
            }

            let outcome = await Self.awaitAuthOutcome(
                webView: webView,
                window: window,
                initialURL: loginURL,
                logger: logger,
                interactiveStdinCheck: interactiveStdinCheck
            )

            await saveCookies(from: webView)
            window.close()

            switch outcome {
            case .autoDetected:
                logInfo("✅ Sign-in detected automatically, cookies saved.")
            case .userConfirmed:
                logInfo("✅ Authentication complete (Enter), cookies saved.")
            case .userClosedWindow:
                logInfo("⚠️  Auth window closed before sign-in was detected. Any cookies present were saved.")
            }
            #endif
        }

        // MARK: - Auth flow coordination (#6 follow-up)

        /// Terminal state of an interactive auth session.
        enum AuthOutcome {
            /// Target session cookie appeared without user input.
            case autoDetected
            /// User pressed Enter at the prompt.
            case userConfirmed
            /// User closed the auth window.
            case userClosedWindow
        }

        /// Names of Apple session cookies whose presence on an `*.apple.com` domain
        /// we treat as "the user has completed sign-in". Exposed for tests.
        nonisolated static let appleSessionCookieNames: Set<String> = ["myacinfo"]

        /// Pure predicate: does this cookie set contain evidence of an Apple sign-in?
        nonisolated static func containsAppleSessionCookie(_ cookies: [HTTPCookie]) -> Bool {
            cookies.contains { cookie in
                cookie.domain.lowercased().contains("apple.com")
                    && appleSessionCookieNames.contains(cookie.name)
            }
        }

        #if os(macOS)
        /// Races three signals: (1) WebView navigation reports an Apple session
        /// cookie present, (2) the user presses Enter at the prompt, (3) the user
        /// closes the auth window. Returns whichever fires first.
        @MainActor
        private static func awaitAuthOutcome(
            webView: WKWebView,
            window: NSWindow,
            initialURL: URL,
            logger: any LoggingModels.Logging.Recording,
            interactiveStdinCheck: any Sample.Core.InteractiveStdinChecking
        ) async -> AuthOutcome {
            await withCheckedContinuation { (continuation: CheckedContinuation<AuthOutcome, Never>) in
                let coordinator = AuthFlowCoordinator(
                    onComplete: { outcome in
                        continuation.resume(returning: outcome)
                    },
                    logger: logger
                )
                webView.navigationDelegate = coordinator

                // (2) Terminal Enter, only if stdin is interactive.
                if interactiveStdinCheck.isInteractive() {
                    Task.detached {
                        if readLine() != nil {
                            await MainActor.run { coordinator.userPressedEnter() }
                        }
                    }
                }

                // (3) Window close.
                let token = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    Task { @MainActor in coordinator.userClosedWindow() }
                }
                coordinator.onFinish = { [weak coordinator] in
                    NotificationCenter.default.removeObserver(token)
                    webView.navigationDelegate = nil
                    _ = coordinator
                }

                // (1) Kick off the initial navigation AFTER the delegate is wired.
                _ = webView.load(URLRequest(url: initialURL))
            }
        }
        #endif

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
            return try await webView.evaluateJavaScript(Shared.Constants.JavaScript.getDocumentHTML) as? String ?? ""
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            logger.info(message, category: .samples)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            logger.error(errorMessage, category: .samples)
        }

        private func logStatistics(_ stats: Sample.Core.Statistics) {
            let messages = [
                "📊 Statistics:",
                "   Total samples: \(stats.totalSamples)",
                "   Downloaded: \(stats.downloadedSamples)",
                "   Skipped: \(stats.skippedSamples)",
                "   Errors: \(stats.errors)",
                // #657 — only surface the invalid-downloads line when it's
                // non-zero; on a clean run the count is 0 and the line
                // would just be noise.
                stats.invalidDownloads > 0 ? "   Invalid downloads (parked as .invalid): \(stats.invalidDownloads)" : "",
                stats.duration.map { "   Duration: \(Int($0))s" } ?? "",
                "",
                "📁 Output: \(outputDirectory.path)",
            ]

            for message in messages where !message.isEmpty {
                logger.info(message, category: .samples)
            }
        }
    }
}

// MARK: - Models

struct SampleMetadata {
    let name: String
    let url: String
    let slug: String
}

// Statistics / Progress / Error split into their own files:
//   Sample.Core.Statistics.swift
//   Sample.Core.Progress.swift
//   Sample.Core.Downloader.Error.swift

// MARK: - Cookie Storage

struct CookieData: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
}

// MARK: - Auth Flow Coordinator (#6 follow-up)

#if os(macOS)
/// Owns the WKNavigationDelegate plus the Enter / window-close bookkeeping for
/// the auth flow. Resumes a continuation with the first outcome it sees.
/// Subsequent signals are dropped (idempotent).
@MainActor
private final class AuthFlowCoordinator: NSObject, WKNavigationDelegate {
    private let onComplete: (Sample.Core.Downloader.AuthOutcome) -> Void
    private var completed = false
    /// Called exactly once, when the coordinator finishes, to let the caller
    /// tear down the notification observer and nil out the webView delegate.
    var onFinish: (() -> Void)?

    /// GoF Strategy seam for log emission (1994 p. 315). Declared
    /// `nonisolated` because the WKNavigationDelegate callbacks fire
    /// outside main-actor isolation; `Logging.Recording` is `Sendable`.
    nonisolated let logger: any LoggingModels.Logging.Recording

    init(
        onComplete: @escaping (Sample.Core.Downloader.AuthOutcome) -> Void,
        logger: any LoggingModels.Logging.Recording
    ) {
        self.onComplete = onComplete
        self.logger = logger
    }

    // MARK: WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Force a render commit. In a Swift CLI host the async/await runloop
        // doesn't always tick the CoreAnimation observer, so layers can stay
        // uncomitted even after successful page load. These hints give CA a
        // deterministic commit point. See followup issue: JSON-endpoint refactor
        // supersedes this whole path.
        Task { @MainActor in
            webView.needsDisplay = true
            webView.layer?.setNeedsDisplay()
            webView.window?.displayIfNeeded()
            CATransaction.flush()
        }

        Task { @MainActor [weak self] in
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            if Sample.Core.Downloader.containsAppleSessionCookie(cookies) {
                self?.complete(.autoDetected)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("🔐 Auth WebView navigation failed: \(error.localizedDescription)")
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("🔐 Auth WebView provisional navigation failed: \(error.localizedDescription)")
    }

    // MARK: Explicit signals

    func userPressedEnter() {
        complete(.userConfirmed)
    }

    func userClosedWindow() {
        complete(.userClosedWindow)
    }

    private func complete(_ outcome: Sample.Core.Downloader.AuthOutcome) {
        guard !completed else { return }
        completed = true
        onComplete(outcome)
        onFinish?()
        onFinish = nil
    }
}
#endif

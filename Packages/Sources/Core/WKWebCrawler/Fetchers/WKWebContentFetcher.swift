import Foundation
import SharedCore
#if canImport(WebKit)
import WebKit
import SharedConstants
import CoreProtocols
#endif

// MARK: - WKWeb Content Fetcher

/// Fetches HTML content using WKWebView for JavaScript-rendered pages
/// This is required for sites that render content via JavaScript
extension WKWebCrawler {
    #if canImport(WebKit)
    @MainActor
    public final class ContentFetcher: NSObject, @preconcurrency CoreProtocols.ContentFetcher {
        public typealias RawContent = String

        // `webView` is an IUO on purpose: `recycle()` (below) is called
        // specifically to free WebKit memory during long crawls, and it does
        // that by setting `webView = nil` *before* allocating the replacement.
        // A non-optional `var` would force the RHS to be evaluated (allocating
        // a second WKWebView) before the assignment releases the old one,
        // doubling peak memory exactly when we're trying to relieve pressure.
        // The IUO form preserves release-first ordering; every read inside
        // this class is on the same MainActor as the init/recycle writes, so
        // an accidental nil-read is structurally impossible.
        private var webView: WKWebView!
        private let pageLoadTimeout: Duration
        private let javascriptWaitTime: Duration

        /// Initialize with configurable timeouts
        /// - Parameters:
        ///   - pageLoadTimeout: Maximum time to wait for page load
        ///   - javascriptWaitTime: Time to wait for JavaScript to render content
        public init(
            pageLoadTimeout: Duration = Shared.Constants.Timeout.pageLoad,
            javascriptWaitTime: Duration = Shared.Constants.Timeout.javascriptWait
        ) {
            self.pageLoadTimeout = pageLoadTimeout
            self.javascriptWaitTime = javascriptWaitTime
            super.init()
            webView = Self.makeWebView()
            webView.navigationDelegate = self
        }

        /// Fetch HTML content from a URL using WKWebView
        /// - Parameter url: The URL to fetch
        /// - Returns: A FetchResult containing the rendered HTML and the post-redirect final URL
        public func fetch(url: URL) async throws -> FetchResult<String> {
            webView.load(URLRequest(url: url))

            let html = try await withThrowingTaskGroup(of: String?.self) { group in
                // Task 1: Timeout
                group.addTask {
                    try await Task.sleep(for: self.pageLoadTimeout)
                    return nil
                }

                // Task 2: Load page content
                group.addTask {
                    try await self.loadPageContent()
                }

                for try await result in group {
                    if let html = result {
                        group.cancelAll()
                        return html
                    }
                }

                group.cancelAll()
                throw WebKitFetcherError.timeout
            }

            let finalURL = webView.url ?? url
            return FetchResult(content: html, url: finalURL)
        }

        /// Recycle the WKWebView to free memory.
        ///
        /// Called periodically during long crawls to bound WebKit's resident
        /// footprint. Order matters here: the IUO-typed property is set to
        /// `nil` *first* so ARC releases the previous WKWebView (and its
        /// caches, navigation state, JS heap, etc.) before we allocate the
        /// replacement. A non-optional var would double peak memory during
        /// the swap; see the IUO comment on the property above.
        public func recycle() {
            webView = nil
            webView = Self.makeWebView()
            webView.navigationDelegate = self
        }

        private static func makeWebView() -> WKWebView {
            WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        }

        /// Get current memory usage in MB
        public func getMemoryUsageMB() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? Double(info.resident_size) / 1048576 : 0
        }

        // MARK: - Private Methods

        private func loadPageContent() async throws -> String {
            // Wait for JavaScript to render content
            try await Task.sleep(for: javascriptWaitTime)

            let result = try await webView.evaluateJavaScript(
                "document.documentElement.outerHTML",
                in: nil,
                contentWorld: .page
            )

            guard let html = result as? String else {
                throw WebKitFetcherError.invalidHTML
            }

            return html
        }
    }
    #endif
}

// MARK: - WKNavigationDelegate

#if canImport(WebKit)
extension WKWebCrawler.ContentFetcher: WKNavigationDelegate {
    public nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // Navigation errors are handled by timeout
    }
}
#endif

// MARK: - WebKit Fetcher Errors

public enum WebKitFetcherError: Error, LocalizedError {
    case timeout
    case invalidHTML
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Page load timeout"
        case .invalidHTML:
            return "Invalid HTML received from JavaScript evaluation"
        case .unsupportedPlatform:
            return "WKWebView is not available on this platform"
        }
    }
}

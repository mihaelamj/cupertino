import Foundation
#if canImport(WebKit)
import WebKit
#endif

// MARK: - WKWeb Content Fetcher

/// Fetches HTML content using WKWebView for JavaScript-rendered pages
/// This is required for sites that render content via JavaScript
extension WKWebCrawler {
    #if canImport(WebKit)
    @MainActor
    public final class WKWebContentFetcher: NSObject, @preconcurrency ContentFetcher {
        public typealias RawContent = String

        private var webView: WKWebView!
        private let pageLoadTimeout: Duration
        private let javascriptWaitTime: Duration

        /// Initialize with configurable timeouts
        /// - Parameters:
        ///   - pageLoadTimeout: Maximum time to wait for page load
        ///   - javascriptWaitTime: Time to wait for JavaScript to render content
        public init(
            pageLoadTimeout: Duration = .seconds(30),
            javascriptWaitTime: Duration = .seconds(5)
        ) {
            self.pageLoadTimeout = pageLoadTimeout
            self.javascriptWaitTime = javascriptWaitTime
            super.init()

            let config = WKWebViewConfiguration()
            webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
        }

        /// Fetch HTML content from a URL using WKWebView
        /// - Parameter url: The URL to fetch
        /// - Returns: The rendered HTML content
        public func fetch(url: URL) async throws -> String {
            webView.load(URLRequest(url: url))

            return try await withThrowingTaskGroup(of: String?.self) { group in
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
        }

        /// Recycle the WKWebView to free memory
        /// Call this periodically during long crawls to prevent memory buildup
        public func recycle() {
            webView = nil
            let config = WKWebViewConfiguration()
            webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
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
extension WKWebCrawler.WKWebContentFetcher: WKNavigationDelegate {
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

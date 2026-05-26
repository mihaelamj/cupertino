import CoreJSONParser
import CoreProtocols
import Foundation
import WebKit

// MARK: - WKWebView title fetcher (#904)

/// Lifted from `Core.JSONParser` into the `CoreJSONParserWebKit` sibling
/// target (#904) so the CoreJSONParser producer stays foundation-only and
/// never links WebKit.
extension Core.JSONParser {
    /// Last-resort title fetcher for documentation URLs that Apple's JSON
    /// API can't serve (some tutorial / article landing pages, deeply
    /// numeric symbol IDs occasionally redirect, etc.). Loads the page in
    /// a real WKWebView and reads `document.title`.
    ///
    /// **Warning:** WKWebView requires a main-thread runloop; the caller
    /// is responsible for bootstrapping
    /// `NSApplication.shared.finishLaunching()` before constructing this.
    /// The CLI command does this on demand.
    @MainActor
    public final class WKWebViewTitleFetcher: NSObject, Core.JSONParser.RefResolver.TitleFetcher {
        public nonisolated func resolveTitle(for documentationURL: URL) async -> String? {
            // The body is @MainActor; the implicit hop happens at this await.
            await fetchTitleSync(documentationURL)
        }

        private let webView: WKWebView
        private let pageLoadTimeout: Duration

        public init(pageLoadTimeout: Duration = .seconds(20)) {
            self.pageLoadTimeout = pageLoadTimeout
            // Construct the WKWebView before `super.init()` so the property is
            // a non-optional `let`. WKWebViewConfiguration's init doesn't touch
            // `self`, so this is safe pre-super, and the class is `@MainActor`
            // so we're on the WebKit-required main thread either way.
            webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            super.init()
        }

        private func fetchTitleSync(_ url: URL) async -> String? {
            webView.load(URLRequest(url: url))
            // Give the page time to load + JS to fill in document.title.
            // Apple's docs SPA flips the title once the route handler runs;
            // the 20s budget is conservative and matches the production crawler.
            let nanos = UInt64(Self.timeoutNanos(pageLoadTimeout))
            try? await Task.sleep(nanoseconds: nanos)
            return await readDocumentTitle()
        }

        private func readDocumentTitle() async -> String? {
            await withCheckedContinuation { continuation in
                webView.evaluateJavaScript("document.title") { result, _ in
                    let title = (result as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: title?.isEmpty == false ? title : nil)
                }
            }
        }

        private static func timeoutNanos(_ duration: Duration) -> UInt64 {
            let parts = duration.components
            let seconds = max(parts.seconds, 0)
            return UInt64(seconds) * 1000000000
        }
    }
}

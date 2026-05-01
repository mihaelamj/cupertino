import Foundation
import Shared
#if canImport(WebKit)
import WebKit
#endif

// MARK: - JSON API title fetcher

/// Resolves a documentation URL's title via Apple's DocC JSON API
/// (`/tutorials/data/.../<page>.json`). Fast (~150-300 ms per call) and
/// covers the vast majority of pages that the in-corpus harvest missed.
public struct AppleJSONAPITitleFetcher: RefResolver.TitleFetcher {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public func resolveTitle(for documentationURL: URL) async -> String? {
        guard let jsonURL = AppleJSONToMarkdown.jsonAPIURL(from: documentationURL) else {
            return nil
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: jsonURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.extractTitle(from: data)
        } catch {
            return nil
        }
    }

    /// Pull just the title field out of an Apple DocC JSON payload —
    /// avoids decoding the full structured page when all we need is the
    /// readable title.
    static func extractTitle(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let metadata = json["metadata"] as? [String: Any] else {
            return nil
        }
        return (metadata["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - WKWebView title fetcher (macOS only)

#if canImport(WebKit)
/// Last-resort title fetcher for documentation URLs that Apple's JSON
/// API can't serve (some tutorial / article landing pages, deeply
/// numeric symbol IDs occasionally redirect, etc.). Loads the page in a
/// real WKWebView and reads `document.title`.
///
/// **Warning:** WKWebView requires a main-thread runloop; the caller is
/// responsible for bootstrapping `NSApplication.shared.finishLaunching()`
/// before constructing this. The CLI command does this on demand.
@MainActor
public final class WKWebViewTitleFetcher: NSObject, RefResolver.TitleFetcher {
    public nonisolated func resolveTitle(for documentationURL: URL) async -> String? {
        // The body is @MainActor; the implicit hop happens at this await.
        await fetchTitleSync(documentationURL)
    }

    private var webView: WKWebView!
    private let pageLoadTimeout: Duration

    public init(pageLoadTimeout: Duration = .seconds(20)) {
        self.pageLoadTimeout = pageLoadTimeout
        super.init()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
    }

    private func fetchTitleSync(_ url: URL) async -> String? {
        webView.load(URLRequest(url: url))
        // Give the page time to load + JS to fill in document.title.
        // Apple's docs SPA flips the title once the route handler runs; the
        // 20s budget is conservative and matches the production crawler.
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
#endif

// MARK: - Composite (try JSON API first, then WebView)

/// Tries `primary` first; if it returns nil, falls through to
/// `fallback`. Used by the CLI to chain JSON API → WKWebView.
public struct CompositeTitleFetcher: RefResolver.TitleFetcher {
    private let primary: any RefResolver.TitleFetcher
    private let fallback: any RefResolver.TitleFetcher

    public init(primary: any RefResolver.TitleFetcher, fallback: any RefResolver.TitleFetcher) {
        self.primary = primary
        self.fallback = fallback
    }

    public func resolveTitle(for documentationURL: URL) async -> String? {
        if let title = await primary.resolveTitle(for: documentationURL) {
            return title
        }
        return await fallback.resolveTitle(for: documentationURL)
    }
}

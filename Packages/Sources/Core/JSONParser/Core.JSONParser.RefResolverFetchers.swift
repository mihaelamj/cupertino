import CoreProtocols
import Foundation

// MARK: - JSON API title fetcher

extension Core.JSONParser {
    /// Resolves a documentation URL's title via Apple's DocC JSON API
    /// (`/tutorials/data/.../<page>.json`). Fast (~150-300 ms per call) and
    /// covers the vast majority of pages that the in-corpus harvest missed.
    public struct AppleJSONAPITitleFetcher: Core.JSONParser.RefResolver.TitleFetcher {
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
}

// MARK: - Composite (try JSON API first, then WebView)

// Note: `Core.JSONParser.WKWebViewTitleFetcher` (the WKWebView-backed
// last-resort fetcher) lives in the `CoreJSONParserWebKit` sibling target
// post-#904 so this producer stays foundation-only.

extension Core.JSONParser {
    /// Tries `primary` first; if it returns nil, falls through to
    /// `fallback`. Used by the CLI to chain JSON API → WKWebView.
    public struct CompositeTitleFetcher: Core.JSONParser.RefResolver.TitleFetcher {
        private let primary: any Core.JSONParser.RefResolver.TitleFetcher
        private let fallback: any Core.JSONParser.RefResolver.TitleFetcher

        public init(
            primary: any Core.JSONParser.RefResolver.TitleFetcher,
            fallback: any Core.JSONParser.RefResolver.TitleFetcher
        ) {
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
}

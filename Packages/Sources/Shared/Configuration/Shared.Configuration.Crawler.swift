import Foundation
import SharedConstants
import SharedUtils

// MARK: - Shared.Configuration.Crawler

extension Shared.Configuration {
    /// Configuration for the Apple Documentation crawler
    public struct Crawler: Codable, Sendable {
        public let startURL: URL
        public let allowedPrefixes: [String]
        public let maxPages: Int
        public let maxDepth: Int
        public let outputDirectory: URL
        public let logFile: URL?
        public let requestDelay: TimeInterval
        public let retryAttempts: Int
        public let discoveryMode: DiscoveryMode
        /// In `.auto` mode, after a successful JSON API fetch, also fetch the rendered
        /// HTML and union its `<a href>` links with JSON's `references` walker output.
        /// Catches URL patterns Apple's DocC JSON omits (operator overloads, legacy
        /// numeric-IDs, REST API sub-paths) at the cost of an extra WebView render
        /// per page. Gated by `htmlLinkAugmentationMaxRefs` so the cost is bounded
        /// to pages with sparse JSON references — well-structured DocC pages are
        /// skipped because their JSON references already cover everything HTML would
        /// add. (#203)
        public let htmlLinkAugmentation: Bool
        /// Threshold for the `htmlLinkAugmentation` heuristic: skip the HTML pass
        /// when the JSON-extracted link count is at or above this value (the page is
        /// already richly cross-referenced and HTML wouldn't surface new URLs).
        /// Default 10 puts roughly the sparse third of Apple's pages through the
        /// augmentation, matching the issue's "30-50% of pages" performance budget.
        /// Set to `Int.max` to disable the heuristic and augment every page; set to
        /// 0 to skip augmentation entirely (equivalent to `htmlLinkAugmentation = false`).
        public let htmlLinkAugmentationMaxRefs: Int

        public init(
            startURL: URL = try! URL(knownGood: Shared.Constants.BaseURL.appleDeveloperDocs),
            allowedPrefixes: [String]? = nil,
            maxPages: Int = Shared.Constants.Limit.defaultMaxPages,
            maxDepth: Int = 15,
            outputDirectory: URL,
            logFile: URL? = nil,
            requestDelay: TimeInterval = 0.05,
            retryAttempts: Int = 3,
            discoveryMode: DiscoveryMode = .auto,
            htmlLinkAugmentation: Bool = true,
            htmlLinkAugmentationMaxRefs: Int = 10
        ) {
            self.startURL = startURL

            // Auto-detect allowed prefixes based on start URL if not provided
            if let allowedPrefixes {
                self.allowedPrefixes = allowedPrefixes
            } else if let host = startURL.host {
                // Build prefix from scheme + host
                let scheme = startURL.scheme ?? "https"
                let basePrefix = "\(scheme)://\(host)"

                // Add common documentation paths based on host
                if host.contains(Shared.Constants.HostDomain.swiftOrg) {
                    // Allow entire swift.org domain - user can curate via start URL
                    self.allowedPrefixes = [basePrefix]
                } else if host.contains(Shared.Constants.HostDomain.appleCom) {
                    self.allowedPrefixes = ["\(basePrefix)/documentation"]
                } else {
                    // Generic: allow entire host
                    self.allowedPrefixes = [basePrefix]
                }
            } else {
                // Fallback to Apple docs
                let docsURL = Shared.Constants.BaseURL.appleDeveloperDocs
                self.allowedPrefixes = [docsURL.replacingOccurrences(of: "/documentation/", with: "/documentation")]
            }

            self.maxPages = maxPages
            self.maxDepth = maxDepth
            self.outputDirectory = outputDirectory
            self.logFile = logFile
            self.requestDelay = requestDelay
            self.retryAttempts = retryAttempts
            self.discoveryMode = discoveryMode
            self.htmlLinkAugmentation = htmlLinkAugmentation
            self.htmlLinkAugmentationMaxRefs = htmlLinkAugmentationMaxRefs
        }

        /// Custom decoder so legacy config JSON without later-added fields still
        /// loads cleanly. Each `decodeIfPresent` falls back to the same default
        /// the memberwise initializer uses.
        private enum CodingKeys: String, CodingKey {
            case startURL, allowedPrefixes, maxPages, maxDepth, outputDirectory
            case logFile, requestDelay, retryAttempts, discoveryMode
            case htmlLinkAugmentation, htmlLinkAugmentationMaxRefs
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startURL = try container.decode(URL.self, forKey: .startURL)
            allowedPrefixes = try container.decode([String].self, forKey: .allowedPrefixes)
            maxPages = try container.decode(Int.self, forKey: .maxPages)
            maxDepth = try container.decode(Int.self, forKey: .maxDepth)
            outputDirectory = try container.decode(URL.self, forKey: .outputDirectory)
            logFile = try container.decodeIfPresent(URL.self, forKey: .logFile)
            requestDelay = try container.decode(TimeInterval.self, forKey: .requestDelay)
            retryAttempts = try container.decode(Int.self, forKey: .retryAttempts)
            discoveryMode = try container.decodeIfPresent(DiscoveryMode.self, forKey: .discoveryMode) ?? .auto
            htmlLinkAugmentation = try container
                .decodeIfPresent(Bool.self, forKey: .htmlLinkAugmentation) ?? true
            htmlLinkAugmentationMaxRefs = try container
                .decodeIfPresent(Int.self, forKey: .htmlLinkAugmentationMaxRefs) ?? 10
        }

        /// Load configuration from JSON file
        public static func load(from url: URL) throws -> Crawler {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(Crawler.self, from: data)
        }

        /// Save configuration to JSON file
        public func save(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url)
        }
    }
}

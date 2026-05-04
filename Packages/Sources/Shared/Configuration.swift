import Foundation

// MARK: - Cupertino Configuration

/// Configuration for the Apple Documentation crawler
extension Shared {
    /// Selects how the crawler discovers child URLs.
    /// - `auto`: JSON API primary, fall back to WKWebView when JSON 404s. (default)
    /// - `jsonOnly`: JSON API only, no WKWebView fallback (fastest, narrowest).
    /// - `webViewOnly`: WKWebView for everything (matches pre-2025-11-30 behavior, broadest discovery).
    public enum DiscoveryMode: String, Codable, Sendable {
        case auto
        case jsonOnly = "json-only"
        case webViewOnly = "webview-only"
    }

    public struct CrawlerConfiguration: Codable, Sendable {
        public let startURL: URL
        public let allowedPrefixes: [String]
        public let maxPages: Int
        public let maxDepth: Int
        public let outputDirectory: URL
        public let logFile: URL?
        public let requestDelay: TimeInterval
        public let retryAttempts: Int
        public let discoveryMode: DiscoveryMode

        public init(
            startURL: URL = URL(string: Shared.Constants.BaseURL.appleDeveloperDocs)!,
            allowedPrefixes: [String]? = nil,
            maxPages: Int = Shared.Constants.Limit.defaultMaxPages,
            maxDepth: Int = 15,
            outputDirectory: URL = Shared.Constants.defaultDocsDirectory,
            logFile: URL? = nil,
            requestDelay: TimeInterval = 0.05,
            retryAttempts: Int = 3,
            discoveryMode: DiscoveryMode = .auto
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
        }

        /// Custom decoder so legacy config JSON without `discoveryMode` still
        /// loads cleanly — defaults to `.auto`. Encode is auto-synthesized.
        private enum CodingKeys: String, CodingKey {
            case startURL, allowedPrefixes, maxPages, maxDepth, outputDirectory
            case logFile, requestDelay, retryAttempts, discoveryMode
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
        }

        /// Load configuration from JSON file
        public static func load(from url: URL) throws -> CrawlerConfiguration {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(CrawlerConfiguration.self, from: data)
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

// MARK: - Change Detection Configuration

/// Configuration for change detection system
extension Shared {
    public struct ChangeDetectionConfiguration: Codable, Sendable {
        public let enabled: Bool
        public let metadataFile: URL
        public let forceRecrawl: Bool

        public init(
            enabled: Bool = true,
            metadataFile: URL? = nil,
            forceRecrawl: Bool = false,
            outputDirectory: URL? = nil
        ) {
            self.enabled = enabled

            // If metadataFile is provided, use it
            // Otherwise, derive from outputDirectory (per-directory metadata)
            // Fall back to global metadata file if neither is provided
            if let metadataFile {
                self.metadataFile = metadataFile
            } else if let outputDirectory {
                // Store metadata.json in the output directory itself
                self.metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            } else {
                // Global fallback
                self.metadataFile = Shared.Constants.defaultMetadataFile
            }

            self.forceRecrawl = forceRecrawl
        }
    }
}

// MARK: - Output Configuration

/// Configuration for output format
extension Shared {
    public struct OutputConfiguration: Codable, Sendable {
        public let format: OutputFormat
        public let includeMarkdown: Bool

        public init(
            format: OutputFormat = .json,
            includeMarkdown: Bool = false
        ) {
            self.format = format
            self.includeMarkdown = includeMarkdown
        }

        public enum OutputFormat: String, Codable, Sendable {
            /// Primary output is JSON (StructuredDocumentationPage)
            case json
            /// Primary output is markdown
            case markdown
            /// Primary output is HTML
            case html
        }
    }
}

// MARK: - Complete Configuration

/// Complete Cupertino configuration
extension Shared {
    public struct Configuration: Codable, Sendable {
        public let crawler: CrawlerConfiguration
        public let changeDetection: ChangeDetectionConfiguration
        public let output: OutputConfiguration

        public init(
            crawler: CrawlerConfiguration = CrawlerConfiguration(),
            changeDetection: ChangeDetectionConfiguration = ChangeDetectionConfiguration(),
            output: OutputConfiguration = OutputConfiguration()
        ) {
            self.crawler = crawler
            self.changeDetection = changeDetection
            self.output = output
        }

        /// Load complete configuration from JSON file
        public static func load(from url: URL) throws -> Shared.Configuration {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(Shared.Configuration.self, from: data)
        }

        /// Save complete configuration to JSON file
        public func save(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url)
        }

        /// Create default configuration file if it doesn't exist
        public static func createDefaultIfNeeded(at url: URL) throws {
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            let defaultConfig = Configuration()
            try defaultConfig.save(to: url)
        }
    }
}

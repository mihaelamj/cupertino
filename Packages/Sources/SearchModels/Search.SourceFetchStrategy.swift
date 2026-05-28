import CrawlerModels
import Foundation
import LoggingModels

// MARK: - Search.SourceFetchStrategy

extension Search {
    /// 2026-05-26 audit Finding 9.7 + 11.1: composition-root-supplied
    /// state required by a `Search.SourceFetchStrategy` to do its
    /// work. Each shipped source's CLI-flag set differs (e.g.
    /// `--only-accepted` is only meaningful for swift-evolution; `--refresh-metadata` /
    /// `--skip-archives` / `--annotate-availability` only for packages).
    /// We carry every flag on the env value and let each strategy
    /// read what it needs; this keeps `Search.SourceProvider.makeFetchStrategy`
    /// arg-free and the dispatch in `CLIImpl.Command.Fetch` a single
    /// call. Per-source-specific flags that don't apply to a strategy
    /// are simply ignored.
    public struct FetchEnvironment: Sendable {
        // MARK: - Output

        /// Destination directory for the fetch output. Resolved at the
        /// composition root from `--output-dir` (when supplied) or
        /// `provider.fetchInfo.defaultOutputDirKey` + `Shared.Paths`.
        public let outputDirectory: URL

        // MARK: - Crawl shape (web-crawl sources)

        public let maxPages: Int
        public let maxDepth: Int
        public let requestDelay: TimeInterval
        public let force: Bool
        public let startClean: Bool
        public let retryErrors: Bool
        public let baseline: URL?
        public let urls: URL?
        /// Override seed URL. When non-nil, the strategy MUST crawl
        /// from here instead of `provider.fetchInfo.crawlBaseURLs.first`.
        public let startURL: URL?
        public let allowedPrefixes: [String]?
        /// `auto` / `json-only` / `webview-only`. String-typed to keep
        /// SearchModels free of the `Shared.Configuration.DiscoveryMode`
        /// enum (which lives higher in the dep graph).
        public let discoveryModeRawValue: String

        // MARK: - Evolution-specific

        public let onlyAccepted: Bool

        // MARK: - Packages / Code

        /// Maximum items to fetch (packages metadata, code archives).
        public let limit: Int?
        /// Opt into the Swift Package Index metadata + star-count
        /// refresh stage of `--source packages`. Off by default; only
        /// the TUI's stars-sort consumes the output, so the indexing
        /// fetch pipeline never needs it. (#1108)
        public let refreshMetadata: Bool
        /// Skip the GitHub archive download stage of `--source packages`
        /// (run only the metadata refresh).
        public let skipArchives: Bool
        /// After `--source packages` stage 2, walk the on-disk corpus
        /// and write per-package `availability.json` records.
        public let annotateAvailability: Bool
        /// Sample-code download: recurse into subdirectories.
        public let recurse: Bool
        /// Re-fetch even if a previous artifact exists on disk.
        public let refresh: Bool

        // MARK: - Availability

        /// Use higher-concurrency, shorter-timeout availability fetch.
        public let fast: Bool

        // MARK: - Shared services

        public let logger: any LoggingModels.Logging.Recording
        /// GoF Strategy seam (1994 p. 315) for producing
        /// `Core.Protocols.StringContentFetcher` instances. Per-source
        /// targets that need a web-crawling fetcher invoke this
        /// factory; sources without a crawl ignore it.
        public let httpFetcherFactory: any Crawler.HTTPFetcherFactory
        /// GoF Strategy seam for HTML → structured-page parsing.
        /// Wired at the CLI composition root from
        /// `LiveHTMLParserStrategy`. AppleDocs / SwiftOrg / SwiftBook
        /// FetchStrategies consume this when constructing
        /// `Crawler.AppleDocs`. Sources without a web-crawl can ignore.
        public let htmlParser: any Crawler.HTMLParserStrategy
        /// GoF Strategy seam for Apple-DocC JSON → markdown.
        public let appleJSONParser: any Crawler.AppleJSONParserStrategy
        /// GoF Strategy seam for package priority-catalog generation.
        public let priorityPackageStrategy: any Crawler.PriorityPackageStrategy

        public init(
            outputDirectory: URL,
            maxPages: Int = 100,
            maxDepth: Int = 15,
            requestDelay: TimeInterval = 0.05,
            force: Bool = false,
            startClean: Bool = false,
            retryErrors: Bool = false,
            baseline: URL? = nil,
            urls: URL? = nil,
            startURL: URL? = nil,
            allowedPrefixes: [String]? = nil,
            discoveryModeRawValue: String = "auto",
            onlyAccepted: Bool = true,
            limit: Int? = nil,
            refreshMetadata: Bool = false,
            skipArchives: Bool = false,
            annotateAvailability: Bool = false,
            recurse: Bool = true,
            refresh: Bool = false,
            fast: Bool = false,
            logger: any LoggingModels.Logging.Recording,
            httpFetcherFactory: any Crawler.HTTPFetcherFactory,
            htmlParser: any Crawler.HTMLParserStrategy,
            appleJSONParser: any Crawler.AppleJSONParserStrategy,
            priorityPackageStrategy: any Crawler.PriorityPackageStrategy
        ) {
            self.outputDirectory = outputDirectory
            self.maxPages = maxPages
            self.maxDepth = maxDepth
            self.requestDelay = requestDelay
            self.force = force
            self.startClean = startClean
            self.retryErrors = retryErrors
            self.baseline = baseline
            self.urls = urls
            self.startURL = startURL
            self.allowedPrefixes = allowedPrefixes
            self.discoveryModeRawValue = discoveryModeRawValue
            self.onlyAccepted = onlyAccepted
            self.limit = limit
            self.refreshMetadata = refreshMetadata
            self.skipArchives = skipArchives
            self.annotateAvailability = annotateAvailability
            self.recurse = recurse
            self.refresh = refresh
            self.fast = fast
            self.logger = logger
            self.httpFetcherFactory = httpFetcherFactory
            self.htmlParser = htmlParser
            self.appleJSONParser = appleJSONParser
            self.priorityPackageStrategy = priorityPackageStrategy
        }
    }

    /// Per-source fetch strategy. Each `<X>Source` target that has a
    /// fetch capability declares a concrete (`<X>FetchStrategy`) and
    /// returns an instance from `Search.SourceProvider.makeFetchStrategy()`.
    /// `CLIImpl.Command.Fetch` invokes the strategy returned by the
    /// registered provider — there is no source-id switch anywhere
    /// in the dispatch.
    ///
    /// Sources without a fetch capability (today: `swift-book`, a
    /// view-source co-crawled by `swift-org`'s strategy) return nil
    /// from `makeFetchStrategy()`.
    public protocol SourceFetchStrategy: Sendable {
        /// Resolve a complete fetch using the supplied environment.
        /// May span hours (full apple-docs crawl), short minutes
        /// (HIG / evolution), or single-digit minutes (packages
        /// metadata refresh). Throws to abort the CLI command.
        func run(env: Search.FetchEnvironment) async throws
    }
}

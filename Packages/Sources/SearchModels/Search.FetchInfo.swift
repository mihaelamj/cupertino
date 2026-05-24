import Foundation

// MARK: - Search.FetchInfo

extension Search {
    /// Fetch-side per-source metadata replacing the pre-#1007
    /// `FetchType` enum's switch arms (displayName, crawlBaseURLs,
    /// defaultOutputDirKey, isWebCrawlable). Each `<X>Source/` target
    /// exposes a static `FetchInfo` literal alongside its
    /// `SourceDefinition`; the CLI composition root resolves the
    /// `defaultOutputDirKey` against `Shared.Paths.live()` at
    /// invocation time rather than letting per-source targets reach
    /// into a CLI-side path resolver.
    ///
    /// Per `gof-di-rules.md` Rule 1 (no Service Locator) the value
    /// holds keys the CLI resolves, not function values reaching out
    /// of the per-source target.
    public struct FetchInfo: Sendable, Equatable {
        /// Human-readable name surfaced by `cupertino fetch --help`
        /// and progress logs (e.g. `"Apple Documentation"`).
        public let displayName: String

        /// Stable identifier matching `Search.SourceDefinition.id`
        /// (e.g. `"apple-docs"`). The composition root keys per-source
        /// fetch routing off this value.
        public let sourceID: String

        /// Base URLs to crawl, when this source uses web-crawl
        /// fetching. Empty for sources fetched via other means
        /// (API, git clone, archive download). Sources with multiple
        /// host roots (e.g. `swift` spans www.swift.org +
        /// docs.swift.org) list all roots.
        public let crawlBaseURLs: [String]

        /// Default output sub-directory under the CLI base directory.
        /// One of:
        /// - `"docs"` -> `Shared.Paths.docsDirectory`
        /// - `"swift-org"` -> `Shared.Paths.swiftOrgDirectory`
        /// - `"swift-evolution"` -> `Shared.Paths.swiftEvolutionDirectory`
        /// - `"packages"` -> `Shared.Paths.packagesDirectory`
        /// - `"sample-code"` -> `Shared.Paths.sampleCodeDirectory`
        /// - `"archive"` -> `Shared.Paths.archiveDirectory`
        /// - `"hig"` -> `Shared.Paths.higDirectory`
        /// - `"base-directory"` -> `Shared.Paths.baseDirectory` (catch-all
        ///   for sources whose fetch dumps directly under the base dir
        ///   without a per-source subdir; pinned by the
        ///   `fetchInfoOutputDirCases` test at the 8-case count).
        ///
        /// The CLI's path-DI layer translates the key to a concrete
        /// URL at composition time; per-source targets do not reach
        /// into `Shared.Paths` themselves (per Rule 1).
        public let defaultOutputDirKey: DefaultOutputDirKey

        /// Whether `cupertino fetch --source <id>` runs a web crawl
        /// for this source (`true`) vs uses a per-source fetcher
        /// concrete like Apple's sample-code archive downloader
        /// (`false`).
        public let isWebCrawlable: Bool

        public init(
            displayName: String,
            sourceID: String,
            crawlBaseURLs: [String] = [],
            defaultOutputDirKey: DefaultOutputDirKey,
            isWebCrawlable: Bool
        ) {
            self.displayName = displayName
            self.sourceID = sourceID
            self.crawlBaseURLs = crawlBaseURLs
            self.defaultOutputDirKey = defaultOutputDirKey
            self.isWebCrawlable = isWebCrawlable
        }
    }
}

// MARK: - Search.FetchInfo.DefaultOutputDirKey

extension Search.FetchInfo {
    /// Per-source key naming the `Shared.Paths.*Directory` accessor
    /// the CLI uses to resolve the default output URL for this
    /// source's fetch. Stays in the Models tier (rawValue strings) so
    /// no per-source target reaches into `Shared.Paths`.
    public enum DefaultOutputDirKey: String, Sendable, Equatable, CaseIterable {
        case docs
        case swiftOrg = "swift-org"
        case swiftEvolution = "swift-evolution"
        case packages
        case sampleCode = "sample-code"
        case archive
        case hig
        case baseDirectory = "base-directory"
    }
}

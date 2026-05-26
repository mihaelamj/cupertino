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
    /// Per-source key naming the dirname the CLI uses to resolve the
    /// default output URL for this source's fetch. Post-#1042 Cluster 9
    /// this is a rawValue-String struct instead of a closed enum:
    /// adding a new source is a `static let <name> = Self(rawValue: "<dirname>")`
    /// declaration, no enum case + no resolveDirectory switch arm.
    /// The CLI's `resolveDirectory(forKey:paths:)` post-Cluster-13
    /// delegates to `Shared.Paths.directory(named:)` using the raw
    /// value verbatim (with a single special case for `baseDirectory`,
    /// which is the base itself, not a sub-directory).
    ///
    /// `allKnownCases` is the post-refactor stand-in for the closed
    /// enum's `allCases`. Tests / inventory surfaces that need to
    /// iterate the 8 shipped keys still can; new sources can declare
    /// keys outside the list and they'll resolve at runtime via the
    /// generic `paths.directory(named:)`.
    public struct DefaultOutputDirKey: RawRepresentable, Sendable, Equatable, Hashable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let docs = Self(rawValue: "docs")
        public static let swiftOrg = Self(rawValue: "swift-org")
        public static let swiftEvolution = Self(rawValue: "swift-evolution")
        public static let packages = Self(rawValue: "packages")
        public static let sampleCode = Self(rawValue: "sample-code")
        public static let archive = Self(rawValue: "archive")
        public static let hig = Self(rawValue: "hig")
        public static let baseDirectory = Self(rawValue: "base-directory")

        /// The 8 keys shipped at v1.2.0. New sources declare additional
        /// keys outside this list; tests iterating the production set
        /// keep using this property.
        public static let allKnownCases: [DefaultOutputDirKey] = [
            .docs, .swiftOrg, .swiftEvolution, .packages,
            .sampleCode, .archive, .hig, .baseDirectory,
        ]

        /// Back-compat alias for code paths that previously used the
        /// closed enum's `CaseIterable` conformance. Aliased to
        /// `allKnownCases` post-#1042 Cluster 9.
        public static let allCases: [DefaultOutputDirKey] = allKnownCases
    }
}

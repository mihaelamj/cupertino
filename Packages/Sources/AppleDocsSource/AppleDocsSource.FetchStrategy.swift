import CrawlerModels
import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - AppleDocsFetchStrategy

/// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy
/// for `--source apple-docs`. Wraps `Crawler.AppleDocs` (the generic
/// web-crawler that drives apple-docs, swift-org, and swift-book).
/// Lifted from `CLIImpl.Command.Fetch.runStandardCrawl` +
/// `executeCrawl`.
///
/// The 3 web-crawl-tier sources (apple-docs / swift-org / swift-book)
/// each return an instance of `WebCrawlFetchStrategy` from their
/// `makeFetchStrategy()`. The strategy reads `env.startURL` (CLI
/// override) or falls back to the supplied `defaultCrawlBaseURL`. The
/// per-source allowedPrefixes are caller-supplied so each source can
/// scope its crawl correctly.
public struct WebCrawlFetchStrategy: Search.SourceFetchStrategy {
    /// Fallback crawl base URL when `env.startURL` is nil. The
    /// composition root (CLI / `<X>Source.makeFetchStrategy`)
    /// supplies the source's canonical seed.
    public let defaultCrawlBaseURL: String
    /// URL prefix allowlist for the crawler when `env.allowedPrefixes`
    /// is nil. Sources whose corpus spans multiple hosts (e.g.
    /// swift-org spans `www.swift.org` + `docs.swift.org`) supply
    /// the multi-prefix list here.
    public let defaultAllowedPrefixes: [String]?
    /// Per-source candidate session directories searched when
    /// `--output-dir` isn't supplied. The CLI passes the canonical
    /// 3-dir list (docsDirectory / swiftOrgDirectory /
    /// swiftBookDirectory); a custom source can pass its own.
    public let candidateSessionDirectories: [URL]

    public init(
        defaultCrawlBaseURL: String,
        defaultAllowedPrefixes: [String]?,
        candidateSessionDirectories: [URL]
    ) {
        self.defaultCrawlBaseURL = defaultCrawlBaseURL
        self.defaultAllowedPrefixes = defaultAllowedPrefixes
        self.candidateSessionDirectories = candidateSessionDirectories
    }

    public func run(env: Search.FetchEnvironment) async throws {
        let url = try validateStartURL(env: env)
        let outputDirectory = try await determineOutputDirectory(for: url, env: env)

        if env.startClean {
            try Ingest.Session.clearSavedSession(at: outputDirectory, logger: env.logger)
        }
        if env.retryErrors {
            try Ingest.Session.requeueErroredURLs(at: outputDirectory, maxDepth: env.maxDepth, logger: env.logger)
        }
        if let baselineURL = env.baseline {
            try Ingest.Session.requeueFromBaseline(at: outputDirectory, baselineDir: baselineURL, maxDepth: env.maxDepth, logger: env.logger)
        }
        if let urlsURL = env.urls {
            try Ingest.Session.enqueueURLsFromFile(
                at: outputDirectory,
                urlsFile: urlsURL,
                maxDepth: env.maxDepth,
                startURL: url,
                logger: env.logger
            )
        }

        let prefixes = env.allowedPrefixes ?? defaultAllowedPrefixes
        let discoveryMode =
            Shared.Configuration.DiscoveryMode(rawValue: env.discoveryModeRawValue) ?? .auto

        let config = Shared.Configuration(
            crawler: Shared.Configuration.Crawler(
                startURL: url,
                allowedPrefixes: prefixes,
                maxPages: env.maxPages,
                maxDepth: env.maxDepth,
                outputDirectory: outputDirectory,
                requestDelay: env.requestDelay,
                discoveryMode: discoveryMode
            ),
            changeDetection: Shared.Configuration.ChangeDetection(
                forceRecrawl: env.force,
                outputDirectory: outputDirectory
            ),
            output: Shared.Configuration.Output(format: .markdown)
        )

        let crawler = await Crawler.AppleDocs(
            configuration: config,
            htmlParser: env.htmlParser,
            appleJSONParser: env.appleJSONParser,
            priorityPackageStrategy: env.priorityPackageStrategy,
            fetcherFactory: env.httpFetcherFactory,
            logger: env.logger
        )
        let stats = try await crawler.crawl(progress: WebCrawlProgressObserver(recording: env.logger))

        env.logger.output("")
        env.logger.info("✅ Crawl completed!")
        env.logger.info("   Total: \(stats.totalPages) pages")
        env.logger.info("   New: \(stats.newPages)")
        env.logger.info("   Updated: \(stats.updatedPages)")
        env.logger.info("   Skipped: \(stats.skippedPages)")
        if let duration = stats.duration {
            env.logger.info("   Duration: \(Int(duration))s")
        }
    }

    private func validateStartURL(env: Search.FetchEnvironment) throws -> URL {
        if let startURL = env.startURL {
            return startURL
        }
        guard let url = URL(string: defaultCrawlBaseURL) else {
            throw FetchError.invalidStartURL(defaultCrawlBaseURL)
        }
        return url
    }

    private func determineOutputDirectory(for url: URL, env: Search.FetchEnvironment) async throws -> URL {
        // env.outputDirectory comes from CLI `--output-dir` resolved at
        // dispatch site against provider.fetchInfo.defaultOutputDirKey.
        // If the user didn't pass `--output-dir`, the dispatch site
        // resolved to the source's default; we still look for an
        // existing session under candidate dirs to resume gracefully.
        // When the user passed an explicit `--output-dir`, use it
        // verbatim (matches pre-fix behavior).
        for candidate in candidateSessionDirectories {
            if let sessionDir = Ingest.Session.checkForSession(at: candidate, matching: url, logger: env.logger) {
                return sessionDir
            }
        }
        return env.outputDirectory
    }

    public enum FetchError: Error, CustomStringConvertible {
        case invalidStartURL(String)
        public var description: String {
            switch self {
            case .invalidStartURL(let raw):
                return "Invalid start URL: \(raw)"
            }
        }
    }
}

private struct WebCrawlProgressObserver: Crawler.AppleDocsProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(progress: Crawler.AppleDocsProgress) {
        let percentage = String(format: "%.1f", progress.percentage)
        let urlComponent = progress.currentURL.lastPathComponent
        recording.output("   Progress: \(percentage)% - \(urlComponent)")
    }
}

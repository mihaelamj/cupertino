import Crawler
import CrawlerModels
import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - AppleArchiveFetchStrategy

/// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy
/// for `--source apple-archive`. Wraps `Crawler.AppleArchive`. Lifted
/// from `CLIImpl.Command.Fetch.runArchiveCrawl`.
public struct AppleArchiveFetchStrategy: Search.SourceFetchStrategy {
    public init() {}

    public func run(env: Search.FetchEnvironment) async throws {
        try FileManager.default.createDirectory(
            at: env.outputDirectory,
            withIntermediateDirectories: true
        )

        let guides = try await loadArchiveGuides(env: env)

        guard !guides.isEmpty else {
            env.logger.error("❌ No archive guides configured")
            env.logger.info("   Use --start-url to specify guide URLs or configure the manifest")
            throw FetchError.noGuidesConfigured
        }

        env.logger.info("📚 Crawling \(guides.count) Apple Archive guides...")
        env.logger.info("   Output: \(env.outputDirectory.path)\n")

        let crawler = await Crawler.AppleArchive(
            outputDirectory: env.outputDirectory,
            guides: guides,
            forceRecrawl: env.force,
            logger: env.logger
        )

        let stats = try await crawler.crawl(progress: AppleArchiveFetchProgressObserver(
            recording: env.logger
        ))

        env.logger.output("")
        env.logger.info("✅ Crawl completed!")
        env.logger.info("   Total guides: \(stats.totalGuides)")
        env.logger.info("   Total pages: \(stats.totalPages)")
        env.logger.info("   New: \(stats.newPages)")
        env.logger.info("   Updated: \(stats.updatedPages)")
        env.logger.info("   Skipped: \(stats.skippedPages)")
        env.logger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            env.logger.info("   Duration: \(Int(duration))s")
        }
        env.logger.info("\n📁 Output: \(env.outputDirectory.path)/")
    }

    /// Lifted from `CLIImpl.Command.Fetch.loadArchiveGuides`.
    /// When `env.startURL` is non-nil, treat it as a single guide.
    /// Otherwise, load the curated essential-guides list from
    /// `Crawler.ArchiveGuideCatalog`.
    private func loadArchiveGuides(env: Search.FetchEnvironment) async throws -> [Crawler.AppleArchive.GuideInfo] {
        if let startURL = env.startURL {
            return [Crawler.AppleArchive.GuideInfo(url: startURL, framework: "")]
        }
        return Crawler.ArchiveGuideCatalog.essentialGuidesWithInfo(
            baseDirectory: env.outputDirectory.deletingLastPathComponent()
        )
    }

    public enum FetchError: Error, CustomStringConvertible {
        case noGuidesConfigured
        public var description: String { "No archive guides configured" }
    }
}

private struct AppleArchiveFetchProgressObserver: Crawler.AppleArchiveProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(progress: Crawler.AppleArchiveProgress) {
        let percent = String(format: "%.1f", progress.percentage)
        recording.output("   Progress: \(percent)% - \(progress.currentItem)")
    }
}

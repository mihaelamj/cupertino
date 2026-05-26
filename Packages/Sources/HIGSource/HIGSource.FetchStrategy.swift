import Crawler
import CrawlerModels
import Foundation
import LoggingModels
import SearchModels

// MARK: - HIGFetchStrategy

/// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy
/// for `--source hig`. Wraps `Crawler.HIG` with the CLI-flag plumbing
/// the dispatch needs. Lifted from `CLIImpl.Command.Fetch.runHIGCrawl`
/// so adding a new source no longer requires editing Fetch.swift.
public struct HIGFetchStrategy: Search.SourceFetchStrategy {
    public init() {}

    public func run(env: Search.FetchEnvironment) async throws {
        try FileManager.default.createDirectory(
            at: env.outputDirectory,
            withIntermediateDirectories: true
        )

        env.logger.info("📖 Crawling Human Interface Guidelines...")
        env.logger.info("   Output: \(env.outputDirectory.path)\n")

        let crawler = await Crawler.HIG(
            outputDirectory: env.outputDirectory,
            forceRecrawl: env.force,
            fetcherFactory: env.httpFetcherFactory,
            logger: env.logger
        )

        let stats = try await crawler.crawl(progress: HIGFetchProgressObserver(
            recording: env.logger
        ))

        env.logger.output("")
        env.logger.info("✅ Crawl completed!")
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
}

/// Closure-free progress observer for HIG crawls. Lifted from
/// `CLIImpl.Command.Fetch.HIGCrawlProgressObserver` — same shape, same
/// behaviour, now owned by the per-source target.
private struct HIGFetchProgressObserver: Crawler.HIGProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(progress: Crawler.HIGProgress) {
        let percent = String(format: "%.1f", progress.percentage)
        recording.output("   Progress: \(percent)% - \(progress.currentItem)")
    }
}

import CrawlerModels
import Foundation
import LoggingModels
import SearchModels

// MARK: - SwiftEvolutionFetchStrategy

/// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy
/// for `--source swift-evolution`. Wraps `Crawler.Evolution`. Lifted
/// from `CLIImpl.Command.Fetch.runEvolutionCrawl`.
public struct SwiftEvolutionFetchStrategy: Search.SourceFetchStrategy {
    public init() {}

    public func run(env: Search.FetchEnvironment) async throws {
        let crawler = await Crawler.Evolution(
            outputDirectory: env.outputDirectory,
            onlyAccepted: env.onlyAccepted,
            logger: env.logger
        )

        let stats = try await crawler.crawl(progress: EvolutionFetchProgressObserver(
            recording: env.logger
        ))

        env.logger.output("")
        env.logger.info("✅ Download completed!")
        env.logger.info("   Total: \(stats.totalProposals) proposals")
        env.logger.info("   New: \(stats.newProposals)")
        env.logger.info("   Updated: \(stats.updatedProposals)")
        env.logger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            env.logger.info("   Duration: \(Int(duration))s")
        }
    }
}

private struct EvolutionFetchProgressObserver: Crawler.EvolutionProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(progress: Crawler.EvolutionProgress) {
        let percentage = String(format: "%.1f", progress.percentage)
        recording.output("   Progress: \(percentage)% - \(progress.proposalID)")
    }
}

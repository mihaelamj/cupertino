import CoreSampleCode
import CoreSampleCodeModels
import CrawlerModels
import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - SampleCodeFetchStrategy

/// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy
/// for `--source samples`. Wraps `Sample.Core.GitHubFetcher`
/// (refreshes sample-code metadata from GitHub). Lifted from
/// `CLIImpl.Command.Fetch.runSamplesFetch`.
///
/// The legacy `apple-sample-code` alias historically routed to a
/// different fetch (`Sample.Core.Downloader` against Apple's
/// sample-code zips). Post-fix both id forms canonicalize to
/// `samples` at dispatch + run this strategy; the Apple downloader
/// path is retired (the bundled corpus + the GitHub-based catalog
/// cover the same content).
public struct SampleCodeFetchStrategy: Search.SourceFetchStrategy {
    public init() {}

    public func run(env: Search.FetchEnvironment) async throws {
        let fetcher = Sample.Core.GitHubFetcher(
            outputDirectory: env.outputDirectory,
            logger: env.logger
        )
        let observer = SampleCodeFetchProgressObserver(recording: env.logger)
        let stats = try await fetcher.fetch(progress: observer)

        env.logger.output("")
        env.logger.info("✅ Fetch completed!")
        env.logger.info("   Action: \(stats.action.description)")
        env.logger.info("   Projects: \(stats.projectCount)")
        if let duration = stats.duration {
            env.logger.info("   Duration: \(Int(duration))s")
        }
        env.logger.info("\n📁 Output: \(env.outputDirectory.path)/cupertino-sample-code")
    }
}

private struct SampleCodeFetchProgressObserver: Sample.Core.GitHubFetcherProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(progress: Sample.Core.GitHubFetcherProgress) {
        recording.output("   \(progress.message)")
    }
}

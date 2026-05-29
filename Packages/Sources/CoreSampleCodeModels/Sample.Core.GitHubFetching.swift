import Foundation
import LoggingModels
import SharedConstants

// MARK: - Sample.Core.GitHubFetching seam + factory

//
// GoF Strategy seam (1994 p. 315) for the GitHub sample-code fetch. The
// concrete `Sample.Core.GitHubFetcher` lives in the `CoreSampleCode`
// producer; this foundation-only protocol lets the `SampleCodeSource`
// fetch strategy depend on the seam (not the producer) per #536 (lift 3).
//
// `GitHubFetcherFactory` is a GoF Abstract Factory (1994 p. 87): the
// composition root supplies the `Live` concrete, the provider holds it,
// and the strategy asks for a fetcher at run time (when `outputDirectory`
// + `logger` are known on the fetch environment). Parallel to
// `Crawler.HTTPFetcherFactory`.
//

extension Sample.Core {
    public protocol GitHubFetching: Sendable {
        /// Clone or pull the sample-code repository, returning a summary.
        /// `progress` is a GoF Observer for fetch events.
        func fetch(
            progress: (any Sample.Core.GitHubFetcherProgressObserving)?
        ) async throws -> Sample.Core.FetchStatistics
    }

    public protocol GitHubFetcherFactory: Sendable {
        /// Produce a fetcher that writes into `outputDirectory` and logs
        /// through `logger`. Invoked by the SampleCodeSource fetch
        /// strategy with the values resolved on the fetch environment.
        func makeFetcher(
            outputDirectory: URL,
            logger: any LoggingModels.Logging.Recording
        ) -> any Sample.Core.GitHubFetching
    }
}

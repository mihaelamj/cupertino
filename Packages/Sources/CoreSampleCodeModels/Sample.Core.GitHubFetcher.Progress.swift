import Foundation
import SharedConstants

// MARK: - Sample.Core.GitHubFetcher value types + Observer protocol

//
// Naming note: the producer-target `Sample.Core.GitHubFetcher` is a
// `public final class` in the `CoreSampleCode` SPM target. To keep its
// progress payload + Observer protocol in this foundation-only seam
// target (so any conformer can implement without `import CoreSampleCode`,
// which pulls in WebKit + AppKit), the seam types are flat-named under
// `Sample.Core` (`GitHubFetcherProgress`, `GitHubFetcherProgressObserving`)
// rather than nested under the producer class.
//
// `Sample.Core` namespace anchor lives in `SharedConstants`
// (`Packages/Sources/Shared/Sample.swift`). This file extends it.

extension Sample.Core {
    /// Progress information emitted during a
    /// `Sample.Core.GitHubFetcher.fetch` run. Pure value type; lives
    /// here in `CoreSampleCodeModels` so any conformer of
    /// `GitHubFetcherProgressObserving` can receive these values
    /// without `import CoreSampleCode`.
    ///
    /// Renamed from `Sample.Core.FetchProgress` during the closures-to-
    /// Observer epic so the type-name carries the producer it
    /// belongs to (parallel to `Crawler.AppleDocsProgress`, etc.).
    public struct GitHubFetcherProgress: Sendable {
        public let message: String
        public let percentage: Double?

        public init(message: String, percentage: Double? = nil) {
            self.message = message
            self.percentage = percentage
        }
    }

    /// GoF Observer (1994 p. 293) for
    /// `Sample.Core.GitHubFetcher.fetch` progress. Replaces the
    /// previous inline
    /// `onProgress: ((FetchProgress) -> Void)?` closure parameter
    /// per the standing cupertino rule against opaque closure seams
    /// in producer-target public APIs.
    public protocol GitHubFetcherProgressObserving: Sendable {
        /// Called periodically as the GitHub fetch / clone / pull
        /// progresses. Implementations should be non-blocking.
        func observe(progress: Sample.Core.GitHubFetcherProgress)
    }
}

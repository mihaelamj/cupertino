import Foundation
import SharedConstants

// MARK: - Sample.Core.Downloader Observer protocol

//
// Naming note: the producer-target `Sample.Core.Downloader` is an actor
// in the `CoreSampleCode` SPM target. To keep its progress Observer
// protocol in this foundation-only seam target (so any conformer can
// implement without `import CoreSampleCode`, which pulls in WebKit +
// AppKit), the seam type is flat-named under `Sample.Core`
// (`DownloaderProgressObserving`) rather than nested under the producer
// actor. Mirrors the `GitHubFetcherProgressObserving` shape from #567.
//
// The payload type `Sample.Core.Progress` lives next to this file in the
// same seam target. The `Sample.Core` namespace anchor is owned by
// `SharedConstants` (`Packages/Sources/Shared/Sample.swift`) and
// extended here.

extension Sample.Core {
    /// GoF Observer (1994 p. 293) for
    /// `Sample.Core.Downloader.download` progress. Replaces the
    /// previous inline
    /// `onProgress: (@Sendable (Sample.Core.Progress) -> Void)?`
    /// closure parameter per the standing cupertino rule against
    /// opaque closure seams in producer-target public APIs.
    public protocol DownloaderProgressObserving: Sendable {
        /// Called once per sample as the downloader processes the
        /// catalog. Implementations should be non-blocking.
        func observe(progress: Sample.Core.Progress)
    }
}

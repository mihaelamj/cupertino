import Foundation

// MARK: - IndexerProgressObserving

extension RemoteSync {
    /// GoF Observer (1994 p. 293) for high-frequency progress events
    /// emitted by `RemoteSync.Indexer.run`. Replaces the previous
    /// `onProgress: @escaping (RemoteSync.Progress) -> Void` closure
    /// parameter.
    ///
    /// Implementations should be non-blocking — `run` calls
    /// `observe(progress:)` on every framework + every file boundary.
    /// The CLI binds this to an animated progress bar through
    /// `RemoteSync.ProgressReporter`.
    public protocol IndexerProgressObserving: Sendable {
        /// Called frequently as the remote index advances. Payload
        /// carries phase, current framework, file index / total,
        /// elapsed seconds, and overall percentage.
        func observe(progress: RemoteSync.Progress)
    }
}

import Foundation

// MARK: - IndexerDocumentObserving

extension RemoteSync {
    /// GoF Observer (1994 p. 293) for per-document outcomes emitted by
    /// `RemoteSync.Indexer.run`. Replaces the previous
    /// `onDocument: ((RemoteSync.Indexer.IndexResult) -> Void)?`
    /// closure parameter.
    ///
    /// The CLI binds this to success / error counters; tests can bind
    /// it to a recorder to assert on indexed URIs.
    public protocol IndexerDocumentObserving: Sendable {
        /// Called once per document the indexer attempted, whether the
        /// indexing succeeded or threw. Payload carries the URI, title,
        /// success flag, and (on failure) a stringified error.
        func observe(result: RemoteSync.IndexerResult)
    }
}

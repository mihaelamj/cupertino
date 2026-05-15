import Foundation

// MARK: - Indexer Result

//
// `RemoteSync.IndexerResult` is flat-named under `RemoteSync` because the
// producer `RemoteSync.Indexer` is a `public actor` in the `RemoteSync`
// target. Nesting the value type inside the actor (the previous
// `RemoteSync.Indexer.IndexResult`) coupled callers to the producer just
// to spell the payload. Flat-naming under the seam-owned `RemoteSync`
// namespace lets any conformer of `IndexerDocumentObserving` import only
// `RemoteSyncModels`.

extension RemoteSync {
    /// Outcome for a single document processed by `RemoteSync.Indexer.run`.
    /// Forwarded to any `IndexerDocumentObserving` conformer.
    ///
    /// Renamed from `RemoteSync.Indexer.IndexResult` during the closures-to-
    /// Observer epic so the type-name carries the producer it belongs to
    /// (matching `RemoteSync.IndexerError`).
    public struct IndexerResult: Sendable {
        public let uri: String
        public let title: String
        public let success: Bool
        public let error: String?

        public init(uri: String, title: String, success: Bool, error: String? = nil) {
            self.uri = uri
            self.title = title
            self.success = success
            self.error = error
        }
    }
}

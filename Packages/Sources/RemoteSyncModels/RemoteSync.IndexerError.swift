import Foundation

// MARK: - Indexer Error

//
// Flat-named under `RemoteSync` (was `RemoteSync.Indexer.Error`) for the
// same reason as `RemoteSync.IndexerResult`: the producer
// `RemoteSync.Indexer` is an actor and can't be extended from this
// foundation-only seam target. Conformers of `IndexerDocumentObserving`
// receive these via `IndexerResult.error` (the stringified description),
// while the producer throws them directly.

extension RemoteSync {
    public enum IndexerError: Swift.Error, Sendable, CustomStringConvertible {
        case stateVersionMismatch(expected: String, found: String)
        case phaseNotFound(String)
        case indexingFailed(uri: String, underlying: String)

        public var description: String {
            switch self {
            case let .stateVersionMismatch(expected, found):
                return "State version mismatch: expected \(expected), found \(found)"
            case let .phaseNotFound(phase):
                return "Phase not found: \(phase)"
            case let .indexingFailed(uri, underlying):
                return "Failed to index \(uri): \(underlying)"
            }
        }
    }
}

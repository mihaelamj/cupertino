import Foundation

// MARK: - Indexer Error

extension RemoteSync.Indexer {
    public enum Error: Swift.Error, Sendable, CustomStringConvertible {
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

import Foundation

// MARK: - Ingest module namespace (#247)

/// Ingest is the write-side counterpart to `Search` / `Indexer` (read +
/// build) and `Distribution` (download). Lifted out of CLI in #247.
///
/// Hosts the orchestration that powers `cupertino fetch` — crawl
/// pipelines for docs / evolution / packages / samples / archive / hig
/// / availability, plus session-resume / baseline-prepend / retry-error
/// helpers.
///
/// **This is the package skeleton.** Today only `Ingest.Session` (pure
/// session-state helpers) is lifted — those are static helpers with no
/// UI coupling. The seven `<Type>Pipeline` files land in follow-up
/// PRs as that orchestration gets a callback-based shape.
public enum Ingest {}

// MARK: - Errors

extension Ingest {
    public enum FetchURLsError: Error, CustomStringConvertible, Equatable {
        case invalidURL(line: String)

        public var description: String {
            switch self {
            case .invalidURL(let line):
                return "Invalid URL in --urls file: \(line)"
            }
        }
    }
}

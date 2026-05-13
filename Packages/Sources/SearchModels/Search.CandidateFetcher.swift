import Foundation

/// A `CandidateFetcher` turns a natural-language question into a ranked
/// list of `Search.SmartCandidate` results pulled from one data source
/// (packages.db, the apple-docs half of search.db, swift-evolution,
/// swift-org, etc.).
///
/// `Search.SmartQuery` fans several fetchers out in parallel and cross-
/// ranks their candidates via reciprocal rank fusion so the final
/// ordering is source-agnostic.
///
/// The protocol lives in SearchModels (not in Search) so consumers
/// outside the Search target — Services-side adapters that bridge
/// cupertino-internal stores into the smart-query fan-out — can
/// conform without taking a behavioural dependency on the Search
/// target.
///
/// Implementations should return candidates already ordered best-first.
/// `limit` is an advisory cap; fetchers may return fewer results but
/// should not exceed it. Network / DB-missing conditions should
/// surface as thrown errors so `SmartQuery` can attribute failures;
/// returning an empty array signals "query ran, nothing matched".
extension Search {
    public protocol CandidateFetcher: Sendable {
        /// Short human-readable name, used for logs + attribution headers.
        var sourceName: String { get }

        /// Fetch candidates for the given question, capped at `limit`.
        func fetch(question: String, limit: Int) async throws -> [SmartCandidate]
    }
}

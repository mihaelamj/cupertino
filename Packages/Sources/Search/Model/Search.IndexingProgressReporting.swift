import Foundation

// MARK: - Search.IndexingProgressReporting

extension Search {
    /// GoF Observer (1994 p. 293) for indexing-run progress. Replaces the
    /// previous `Search.IndexingProgressCallback = @Sendable (Int, Int) -> Void`
    /// closure typealias. Consumers that want progress updates implement this
    /// protocol on a named, Sendable type and pass the instance into a
    /// strategy's `indexItems(into:progress:)` or
    /// `Search.IndexBuilder.buildIndex(clearExisting:progress:)`.
    ///
    /// Why a protocol instead of a typealiased closure: the typealias declared
    /// the intent to elevate the closure to a contract but never followed
    /// through. A typed protocol surfaces the operation name (`report(...)`),
    /// the arguments by name, and lets implementations be discoverable, mock-
    /// able, testable, and documented in one place. Aligns with the standing
    /// cupertino rule "no closures, they ate magic" (see
    /// `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5).
    public protocol IndexingProgressReporting: Sendable {
        /// Called periodically during an indexing run with the running
        /// `(processed, total)` count. Implementations should be non-blocking;
        /// the indexer waits for return before continuing.
        ///
        /// - Parameters:
        ///   - processed: Number of items handled so far.
        ///   - total: Total number of items in the source.
        func report(processed: Int, total: Int)
    }
}

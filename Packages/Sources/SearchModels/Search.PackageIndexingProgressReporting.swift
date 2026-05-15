import Foundation

// MARK: - Search.PackageIndexingProgressReporting

extension Search {
    /// GoF Observer (1994 p. 293) for per-package indexing progress.
    /// Replaces the inline `onProgress: @escaping @Sendable (String, Int, Int) -> Void`
    /// closure parameter previously taken by `Search.PackageIndexingRunner.run`.
    ///
    /// The previous design comment said "the progress callback stays a closure
    /// — it's a genuine (name, done, total) callback, not a strategy seam."
    /// That documented choice is reversed here per the standing cupertino
    /// rule "no closures, they ate magic" (see
    /// `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5). A typed
    /// protocol surfaces the operation name, the arguments by name, and
    /// lets implementations be discoverable, mockable, testable, and
    /// documented in one place — even when the call is "genuinely" a
    /// callback rather than a swappable algorithm.
    public protocol PackageIndexingProgressReporting: Sendable {
        /// Called periodically as each package is processed.
        ///
        /// - Parameters:
        ///   - packageName: Identifier of the package currently being indexed.
        ///   - processed: Number of packages handled so far (1-based).
        ///   - total: Total packages in the queue.
        func report(packageName: String, processed: Int, total: Int)
    }
}

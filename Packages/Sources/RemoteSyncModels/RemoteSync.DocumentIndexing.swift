import Foundation

// MARK: - DocumentIndexing Strategy

extension RemoteSync {
    /// GoF Strategy (1994 p. 315) for indexing one document into a
    /// search backend. `RemoteSync.Indexer.run` calls this for every
    /// `.json` / `.md` file it pulls from GitHub.
    ///
    /// Replaces the previous
    /// `RemoteSync.Indexer.DocumentIndexer` closure typealias. The
    /// binary supplies the concrete (today: the CLI wraps
    /// `Search.Index.indexDocument`); the actor itself never knows
    /// about the search target, so `RemoteSync` stays standalone-
    /// portable (foundation tier only) per the cupertino package
    /// independence rule.
    public protocol DocumentIndexing: Sendable {
        /// Persist a single document to whichever search backend the
        /// composition root supplies.
        ///
        /// `framework` is `nil` for non-docs phases (Swift Evolution,
        /// Swift.org, etc.). `jsonData` is the same payload as
        /// `content` today; the parameter is kept so a future caller
        /// can supply a separately-parsed JSON form without an API
        /// break.
        func indexDocument(
            uri: String,
            source: String,
            framework: String?,
            title: String,
            content: String,
            jsonData: String?
        ) async throws
    }
}

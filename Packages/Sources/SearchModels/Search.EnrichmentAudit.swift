import Foundation

// MARK: - Search.EnrichmentAuditObserver

extension Search {
    /// GoF Observer (1994 p. 293) for enrichment-pass per-entry events.
    /// Pre-existing logging only emitted a one-line summary per pass
    /// (`[enrichment/constraints] affected=N skipped=N (Nms)`), which
    /// hid the per-URI / per-framework breakdown of what actually got
    /// updated. This protocol lets the composition root attach a JSONL
    /// writer (or any other sink) that records each lookup entry the
    /// pass attempted and how many rows it touched.
    ///
    /// 2026-05-27: added after a 9.5-hour Claw mini apple-docs reindex
    /// finished with no per-pass visibility into which apple-constraints
    /// lookup entries had matched rows. Without the audit log we
    /// couldn't tell mid-run or post-run whether the pass actually
    /// affected the rows it was supposed to.
    ///
    /// Implementations must be `Sendable` (the observer crosses
    /// actor boundaries from the indexer pass into the writer).
    public protocol EnrichmentAuditObserver: Sendable {
        /// Called when an enrichment pass starts running against a
        /// per-source DB. Fires once per pass per save.
        func recordPassStart(passIdentifier: String, dbPath: String)

        /// Called once per attempted lookup entry. For
        /// `applyAppleStaticConstraints` this fires per `apple-constraints.json`
        /// entry (61k+ entries on the production table). For
        /// `propagateConstraintsFromParents` it fires per child row
        /// whose constraints were inherited from a parent.
        ///
        /// `rowsAffected` is the count returned by `sqlite3_changes()`
        /// after the UPDATE — 0 for "no row matched", 1 for "single
        /// exact-match update", N for "N rows matched the prefix LIKE
        /// pattern". `matchType` is `"exact"` / `"prefix"` /
        /// `"hierarchy"` to disambiguate the source.
        func recordEntry(
            passIdentifier: String,
            docURI: String,
            value: String,
            matchType: String,
            rowsAffected: Int
        )

        /// Called when an enrichment pass completes. Fires once per
        /// pass per save (after `recordPassStart`).
        func recordPassEnd(
            passIdentifier: String,
            totalRowsAffected: Int,
            totalRowsSkipped: Int,
            durationMs: Int
        )
    }
}

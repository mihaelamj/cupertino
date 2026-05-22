import Foundation
import SearchModels

// MARK: - Search.Schema

extension Search {
    /// Namespace anchor for the search-index database schema constants
    /// (DDL SQL strings + current schema version). Lifted from the
    /// `Search` target into its own foundation-only SPM target by epic
    /// #893's child #898 sub-PR A so the schema constants live in one
    /// place rather than being interleaved with the executor methods on
    /// `Search.Index`.
    ///
    /// The executor methods (`createTables()` + the per-version
    /// `migrateToVersion*()` family) stay in the `Search` target because
    /// they need access to the `Search.Index` actor's internal `database`
    /// stored property; extensions in a different module cannot reach
    /// internal members. Sub-PR E (the full `SearchSQLite` extraction)
    /// moves those executor methods alongside the rest of the SQLite-using
    /// code into a sibling concrete target.
    public enum Schema {}
}

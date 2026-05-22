import Foundation
import SearchModels

// MARK: - Search.Schema.currentVersion

public extension Search.Schema {
    /// Current `search.db` schema version. Used by `Search.Index.checkAndMigrateSchema`
    /// to decide whether the open database file matches the binary's
    /// expected layout. A mismatch raises a typed error per the #673
    /// schema-mismatch UX so users get a clear "rebuild required" path.
    ///
    /// `Search.Index.schemaVersion` is re-exported (as a `public static let`
    /// initialised from this constant) so existing call sites that
    /// reference `Search.Index.schemaVersion` (test fixtures + doctor
    /// diagnostics across `Packages/Tests/`) keep compiling unchanged.
    /// New code should reference `Search.Schema.currentVersion` directly.
    ///
    /// ## Version history
    ///
    /// See the lengthy comment block on `Search.Index` in
    /// `Search/Search.Index.swift` for the per-version release-history
    /// log. Each bump corresponds to a `migrateToVersionN` method in
    /// `Search.Index.Migrations.swift` plus a CHANGELOG entry.
    static let currentVersion: Int32 = 18
}

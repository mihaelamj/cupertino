import Foundation

// MARK: - Shared.Models.DatabaseDescriptor

/// Declarative descriptor for one local SQLite database managed by
/// cupertino's CLI. First cut of the #248 refactor, filed under the
/// #919 declarative source + DB pluggability epic.
///
/// **Scope of this first cut:** captures the identity bits the CLI's
/// `Distribution.InstalledVersion.classify` and
/// `Distribution.SetupService` need to make per-DB decisions
/// DB-count-agnostic (`id`, `filename`, `displayName`). The fuller
/// proposal in #248 also covers download URLs, schema-version readers,
/// row counters, and indexer hooks; those land in follow-up PRs once
/// `SetupCommand`, `DoctorCommand`, and `SaveCommand` get rewired one
/// at a time.
///
/// Lives under `Shared.Models` (foundation-only Models tier) so any
/// producer or composition root can hold the descriptor without
/// dragging the concrete DB targets in. The flat name avoids collision
/// with `Shared.Constants.Database` (the table-name constants
/// namespace that already exists in this target).
extension Shared.Models {
    public struct DatabaseDescriptor: Sendable, Hashable, Identifiable {
        // MARK: - Canonical descriptors for the three databases cupertino ships today
        //
        // Single source of truth used by production code AND tests. Pre-#248,
        // both sides duplicated the literals; a rename to `id` / `filename` /
        // `displayName` in production silently left tests green while live
        // callers got nil from `Outcome.path(forDatabaseId:)`. Centralising
        // here makes that drift structurally impossible.

        public static let search: DatabaseDescriptor = .init(
            id: "search",
            filename: Shared.Constants.FileName.searchDatabase,
            displayName: "Documentation"
        )

        public static let samples: DatabaseDescriptor = .init(
            id: "samples",
            filename: Shared.Constants.FileName.samplesDatabase,
            displayName: "Sample code"
        )

        public static let packages: DatabaseDescriptor = .init(
            id: "packages",
            filename: Shared.Constants.FileName.packagesIndexDatabase,
            displayName: "Packages"
        )

        /// Stable identifier the CLI uses to route per-DB commands
        /// (`cupertino setup`, `cupertino doctor`,
        /// `cupertino save --<db>`). Matches the historical short
        /// name: `"search"`, `"samples"`, `"packages"`.
        public let id: String

        /// On-disk filename under the cupertino base directory.
        /// Matches `Shared.Constants.FileName.*`.
        public let filename: String

        /// Human-readable display name for diagnostic output
        /// (`Documentation`, `Sample code`, `Packages`).
        public let displayName: String

        public init(id: String, filename: String, displayName: String) {
            self.id = id
            self.filename = filename
            self.displayName = displayName
        }
    }
}

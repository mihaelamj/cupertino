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

        // MARK: - Per-source descriptors (post-2026-05-25, per-source DB split epic)

        //
        // Step 1 of `docs/design/per-source-db-split.md`: introduce 5 new
        // descriptors for the DBs that split out of search.db. Names settled
        // 2026-05-25 (see `cupertino-per-source-db-names-agreed` memory).
        // Step 1 is purely additive: no source provider's destinationDB
        // points at these yet. Sources flip one at a time in step 4. After
        // all 5 flip, `.search` is removed; tests until then keep using
        // `.search` so the suite stays green.

        /// Apple Developer Documentation. Receives the apple-docs rows that
        /// live in search.db today (~379k rows; ~1.2 GB at v1.2.0).
        public static let appleDocumentation: DatabaseDescriptor = .init(
            id: "apple-documentation",
            filename: Shared.Constants.FileName.appleDocumentationDatabase,
            displayName: "Apple Developer Documentation"
        )

        /// Human Interface Guidelines. Initialism preserved per
        /// `cupertino-per-source-db-names-agreed` (industry-standard acronym
        /// vs. spelled-out form: HIG wins on discoverability + brevity).
        public static let hig: DatabaseDescriptor = .init(
            id: "hig",
            filename: Shared.Constants.FileName.higDatabase,
            displayName: "Human Interface Guidelines"
        )

        /// Apple Archive legacy programming guides.
        public static let appleArchive: DatabaseDescriptor = .init(
            id: "apple-archive",
            filename: Shared.Constants.FileName.appleArchiveDatabase,
            displayName: "Apple Archive"
        )

        /// Swift Evolution proposals.
        public static let swiftEvolution: DatabaseDescriptor = .init(
            id: "swift-evolution",
            filename: Shared.Constants.FileName.swiftEvolutionDatabase,
            displayName: "Swift Evolution"
        )

        /// Swift documentation. Co-locates swift-org + swift-book rows via
        /// the SwiftOrgStrategy URL-prefix view-source pattern (see
        /// `docs/design/corpus-structure.md` §3.5.5). One indexer, one DB,
        /// two source-id tags distinguished by URL prefix at index time.
        public static let swiftDocumentation: DatabaseDescriptor = .init(
            id: "swift-documentation",
            filename: Shared.Constants.FileName.swiftDocumentationDatabase,
            displayName: "Swift Documentation"
        )

        /// Apple sample code (rename of `.samples`; step 6 file-rename
        /// migration flips user bundles). Lives in parallel with `.samples`
        /// until step 6 lands, then `.samples` is removed.
        public static let appleSampleCode: DatabaseDescriptor = .init(
            id: "apple-sample-code",
            filename: Shared.Constants.FileName.appleSampleCodeDatabase,
            displayName: "Apple Sample Code"
        )

        /// Swift packages (rename of `.packages`; step 6 file-rename
        /// migration flips user bundles). Lives in parallel with `.packages`
        /// until step 6 lands, then `.packages` is removed.
        public static let swiftPackages: DatabaseDescriptor = .init(
            id: "swift-packages",
            filename: Shared.Constants.FileName.swiftPackagesDatabase,
            displayName: "Swift Packages"
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

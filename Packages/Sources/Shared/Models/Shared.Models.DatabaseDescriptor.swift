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
        // MARK: - Legacy descriptors (pre per-source DB split)

        //
        // The three descriptors cupertino's bundle shipped before the per-source
        // DB split epic (2026-05-25). Single source of truth used by production
        // code AND tests. Pre-#248, both sides duplicated the literals; a rename
        // to `id` / `filename` / `displayName` in production silently left tests
        // green while live callers got nil from `Outcome.path(forDatabaseId:)`.
        // Centralising here makes that drift structurally impossible.
        //
        // These three live in parallel with the per-source descriptors below
        // until step 4 of `docs/design/per-source-db-split.md` flips every
        // source's `destinationDB` to its own per-source descriptor. After
        // step 6 (the on-disk migration shim) lands, `.search` is removed;
        // `.samples` and `.packages` get removed in the same pass once the
        // `.appleSampleCode` / `.swiftPackages` renames are wired through
        // `cupertino setup`, `cupertino doctor`, and the bundle manifest.

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
        // Step 1 of `docs/design/per-source-db-split.md`: introduce 7 new
        // descriptors. 5 of them split out of `.search` (apple-documentation,
        // hig, apple-archive, swift-evolution, swift-documentation); the other
        // 2 (.appleSampleCode, .swiftPackages) are renames-in-waiting for
        // `.samples` and `.packages` whose on-disk filename flips in step 6's
        // migration shim. Names settled 2026-05-25 (see
        // `cupertino-per-source-db-names-agreed` memory).
        //
        // Step 1 is purely additive: no source provider's destinationDB
        // points at these yet. Sources flip one at a time in step 4. After
        // all 5 search-bound flips land, `.search` is removed. `.samples`
        // and `.packages` are removed alongside step 6 (the on-disk file
        // rename + bundle migration).
        //
        // **Identifier discipline (important for step 4 readers):** the
        // descriptor's `id` (e.g. `apple-documentation`) is intentionally
        // NOT the same as the source's `Shared.Constants.SourcePrefix.*`
        // value (e.g. `apple-docs`). DB ids and source ids are separate
        // naming spaces. The binding from one to the other is via
        // `SourceProvider.destinationDB`, never via string matching.
        // Diverging pairs (step 4 must route via the descriptor reference,
        // not the source-id literal):
        //
        //   - SourcePrefix.appleDocs       ("apple-docs")        → .appleDocumentation ("apple-documentation")
        //   - SourcePrefix.swiftOrg        ("swift-org")
        //     + SourcePrefix.swiftBook     ("swift-book")        → .swiftDocumentation ("swift-documentation")  (co-located view-source)
        //   - SourcePrefix.packages        ("packages")          → .swiftPackages      ("swift-packages")
        //   - SourcePrefix.samples         ("samples")
        //     + SourcePrefix.appleSampleCode ("apple-sample-code")
        //     + literal                    "sample-code"          → .appleSampleCode    ("apple-sample-code")
        //
        // Source-ids `hig`, `apple-archive`, `swift-evolution` happen to
        // match their descriptors verbatim, but that's a coincidence of the
        // current naming, not a contract.
        //
        // **Important non-SourcePrefix tag:** sample-code rows are written
        // by `SampleCodeStrategy` with a hardcoded `source = "sample-code"`
        // literal (see `SampleCodeStrategy.source` in
        // `SampleCodeSource/Search.Strategies.SampleCode.swift`). This
        // literal does NOT match `SourcePrefix.samples` ("samples") OR
        // `SourcePrefix.appleSampleCode` ("apple-sample-code"); those
        // constants are CLI-query aliases used by `PlatformFilterScope` +
        // `CompositeToolProvider`, NOT row-emission tags. A step-4 / step-6
        // dispatcher walking search.db rows by `source IN (SourcePrefix.*)`
        // will miss sample-code rows entirely. Use the literal value or
        // route via descriptor reference instead.
        //
        // swift-book DOES have a matching SourcePrefix constant
        // (`SourcePrefix.swiftBook = "swift-book"`), but the emission path
        // is via `extractFrameworkFromPath` returning the literal "swift-book"
        // from the file's directory components, not via the constant itself.
        // Downstream code in SwiftOrgStrategy matches the result against
        // `SourcePrefix.swiftBook` for type-safe branching.
        //
        // **Producer-graph reality (step 4 / step 6 planners):** today,
        // SampleCodeSource has `destinationDB = .search` (sample-code rows
        // live in search.db), and the `.samples` descriptor is fed by a
        // separate `Sample.Index.Builder` pipeline that is NOT yet wrapped
        // in the SourceProvider abstraction. So step 6's migration shim has
        // two distinct samples-related tasks: (a) extract sample-code rows
        // from search.db into apple-sample-code.db, AND (b) rename the
        // sample-files-index DB from samples.db to apple-sample-code.db
        // (or merge it with the extracted rows). This is intentionally
        // unspecified in this comment; the per-source-db-split.md step 6
        // section owns the resolution. PackagesSource currently routes at
        // `.packages` not `.swiftPackages`; that flip lands in step 4.

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

        /// Swift documentation. Co-locates swift-org + swift-book rows in
        /// one DB. Write-time mechanism (post-#1029 view-source pattern, see
        /// `docs/design/corpus-structure.md` §3.5.5): `SwiftOrgStrategy`
        /// derives each row's source-id from the file-system path of the
        /// crawled doc. Specifically it calls
        /// `Search.StrategyHelpers.extractFrameworkFromPath`, which returns
        /// the first path component under the strategy's base directory.
        /// Today's corpus shape (cupertino-docs swift-org/ tree) places
        /// every doc under either `swift-org/` or `swift-book/`, so the
        /// helper returns one of those two literal strings, and rows are
        /// tagged accordingly. If a future corpus snapshot adds a third
        /// subdirectory (e.g. `swift-org/migration-guide/`), the helper
        /// will return that name and emit rows tagged with it. The fallback
        /// `?? Shared.Constants.SourcePrefix.swiftOrg` covers only the case
        /// where the helper returns nil (file directly in the base
        /// directory with no subdirectory). `SwiftBookViewSourceStrategy`
        /// reports `wasSkipped: true` so the per-source breakdown log
        /// doesn't imply a failed indexing attempt for swift-book. Net
        /// effect: two registered SourceProviders, one effective indexer
        /// writing all rows, one DB. Distinguished at read time by the
        /// `source` column.
        public static let swiftDocumentation: DatabaseDescriptor = .init(
            id: "swift-documentation",
            filename: Shared.Constants.FileName.swiftDocumentationDatabase,
            displayName: "Swift Documentation"
        )

        /// Apple sample code per-file rich schema (rename of `.samples`;
        /// step 6 file-rename migration flips user bundles). Carries
        /// `Sample.Index.Builder`'s schema (file_symbols + project rows,
        /// NOT docs_metadata + docs_fts). Lives in parallel with
        /// `.samples` until step 6 lands, then `.samples` is removed.
        /// **Distinct from `.appleSampleCodeSearch`**: the two
        /// descriptors target different SQLite files with different
        /// schemas so neither schema collides with the other.
        public static let appleSampleCode: DatabaseDescriptor = .init(
            id: "apple-sample-code",
            filename: Shared.Constants.FileName.appleSampleCodeDatabase,
            displayName: "Apple Sample Code"
        )

        /// Apple sample code search-style FTS rows. `SampleCodeSource`'s
        /// `destinationDB` points here post the step-7a refactor: rows
        /// emitted by `SampleCodeStrategy` (docs_metadata + docs_fts
        /// schema) land in `apple-sample-code-search.db`. Pre-step-7a,
        /// these rows lived in the shared `search.db`; the split into
        /// this dedicated file keeps SampleCodeSource's search-side
        /// data alongside the rest of the per-source DBs and avoids
        /// the schema collision with `.appleSampleCode` (per-file rich
        /// data renamed from samples.db).
        public static let appleSampleCodeSearch: DatabaseDescriptor = .init(
            id: "apple-sample-code-search",
            filename: Shared.Constants.FileName.appleSampleCodeSearchDatabase,
            displayName: "Apple Sample Code (Search)"
        )

        /// Swift packages (rename of `.packages`; step 6 file-rename
        /// migration flips user bundles). Lives in parallel with `.packages`
        /// until step 6 lands, then `.packages` is removed.
        public static let swiftPackages: DatabaseDescriptor = .init(
            id: "swift-packages",
            filename: Shared.Constants.FileName.swiftPackagesDatabase,
            displayName: "Swift Packages"
        )

        /// All declared descriptors (legacy 3 + per-source 7). Used by
        /// `ConstantsAuditTests` to iterate the full descriptor surface
        /// without hardcoding the list in test files. Future descriptors
        /// MUST be appended here; CI's audit tests catch a missing
        /// addition automatically.
        public static let allKnown: [DatabaseDescriptor] = [
            .search,
            .samples,
            .packages,
            .appleDocumentation,
            .hig,
            .appleArchive,
            .swiftEvolution,
            .swiftDocumentation,
            .appleSampleCode,
            .appleSampleCodeSearch,
            .swiftPackages,
        ]

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

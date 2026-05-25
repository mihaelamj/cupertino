import Foundation
import SharedConstants

// MARK: - Search.SourceProvider

extension Search {
    /// One per-source bundle: the descriptor, the optional fetch-side
    /// metadata, and factories for the indexing strategy and indexer
    /// concretes. Replaces the pre-#1007 scattered surface where a
    /// new source touched 5 files in 3 SPM targets (SourceDefinition
    /// literal at CLI composition root, FetchType enum case +
    /// switches, SourceIndexer concrete in SearchSQLite, strategy
    /// concrete in `<X>Strategy/`, indexer-dict entry at CLI Save).
    ///
    /// Post-#1007 epic, each source lives in its own SPM target
    /// (e.g. `Packages/Sources/AppleDocsSource/`) exposing a
    /// `SourceProvider` conformer. The composition root iterates a
    /// `Search.SourceRegistry` of these providers to derive the
    /// indexer dict, the strategies list, the source-lookup
    /// definitions, and (where `fetchInfo != nil`) the per-source
    /// fetch dispatch surface.
    ///
    /// Per `mihaela-agents/Rules/swift/gof-di-rules.md` Rule 3 the
    /// protocol lives in this foundation-only `*Models` target; per
    /// Rule 4 the factory methods return concrete types via `any`
    /// rather than closure typealiases.
    public protocol SourceProvider: Sendable {
        /// The descriptor identifying this source in
        /// `Search.SourceLookup` and the production source list.
        var definition: Search.SourceDefinition { get }

        /// Optional fetch-side metadata for `cupertino fetch`. `nil`
        /// for sources that are search-only (e.g. derived sources
        /// populated by another source's indexer). Sources that get
        /// crawled, downloaded, or otherwise materialised return a
        /// non-nil value.
        var fetchInfo: Search.FetchInfo? { get }

        /// Destination database this source's indexer writes to.
        /// **Required, no default**: every conformer must declare its
        /// destination explicitly (no implicit search.db routing).
        /// Composition root logic for the post-#1007 registry-driven
        /// path groups providers by `destinationDB.id` and dispatches
        /// to the right index builder. Until phase 1I wires that
        /// consumer, the field is a structural declaration the
        /// providers carry; the existing search.db routing in
        /// `CLIImpl.Command.Save.Indexers.swift` stays as-is.
        /// Filed as #1015 (origin) and folded into #1014's Phase 1D
        /// scope (the protocol extension lands alongside the
        /// AppleArchiveSource migration; the 3 prior conformers get
        /// retrofitted in the same PR).
        ///
        /// **Forward-looking note on the descriptor name**: today
        /// every search-bound source declares `.search`, but the
        /// `.search` name is a temporary stand-in for "the shared
        /// prose-text FTS database" that holds 6+ sources today. When
        /// the per-source DB split lands (separate epic, post-1I),
        /// each source will declare its own descriptor (e.g.
        /// `.appleDocs`, `.hig`, `.appleArchive`) and `.search` as a
        /// name will become meaningless. Conformers should not rely
        /// on the literal `.search` staying stable across the future
        /// split; the descriptor abstraction is what's stable, not
        /// the specific descriptor instances (``Shared.Models.DatabaseDescriptor``
        /// will gain new instances over time).
        var destinationDB: Shared.Models.DatabaseDescriptor { get }

        /// What this source's DB can answer at read time (searchers +
        /// operations + typed metadata flags). Drives the CLI
        /// dispatcher's fan-out to per-source DBs once step 4 of the
        /// per-source DB split epic lands. A default extension on
        /// `SourceProvider` returns `Search.Capabilities.empty`, so
        /// adding this property is not a breaking change for external
        /// conformers; every in-tree source overrides with its
        /// declared matrix matching its YAML manifest at
        /// `docs/sources/<sourceId>/manifest.yaml`.
        var capabilities: Search.Capabilities { get }

        /// Construct this source's indexing strategy. The composition
        /// root calls this once at index-time and passes the result
        /// to `Search.IndexBuilder`.
        ///
        /// - Parameter env: shared dependencies (logger, paths,
        ///   markdown strategy, etc.) the strategy may need.
        func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy

        /// Construct this source's indexer concrete. The composition
        /// root calls this once at indexer-dict-assembly time and
        /// registers the result under `definition.id`.
        func makeIndexer() -> any Search.SourceIndexer
    }
}

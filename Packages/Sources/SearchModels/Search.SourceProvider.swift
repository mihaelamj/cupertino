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

        /// Legacy source-id literals this provider should claim during
        /// the per-source DB split migration. Most sources don't need
        /// this; the migrator resolves rows by `docs_metadata.source`
        /// matching `definition.id` directly. But some sources emit
        /// rows tagged with a DIFFERENT literal than their definition.id
        /// (e.g. `SampleCodeStrategy.source = "sample-code"` while
        /// `SampleCodeSource.definition.id = "samples"`); without this
        /// declaration, the migrator would surface those rows as
        /// `unknownSourceIDs` and abort. Declaring the legacy literals
        /// here lets the migrator route them to this provider's
        /// `destinationDB` post-migration.
        ///
        /// Default `[]` (no aliases) makes this additive for external
        /// conformers. SampleCodeSource is the only in-tree source
        /// declaring an alias today: `["sample-code"]`.
        var legacySourceIDAliases: Set<String> { get }

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

        /// Which CLI/MCP search-dispatch runner this source uses at
        /// query time. Pre-#1042 Cluster 8, both
        /// `CLIImpl.Command.Search.run` and
        /// `SearchToolProvider.CompositeToolProvider.handleSearch`
        /// hardcoded an 8-arm switch over source-ids; adding a new
        /// source required editing both switches. Post-fix the
        /// dispatcher consults this property on each registered
        /// provider and routes to the matching runner. The default
        /// extension returns `.docs` (the most common case: 5 of 8
        /// shipped sources). Sources whose dispatch differs override
        /// in their concrete (`HIGSource`, `SampleCodeSource`,
        /// `PackagesSource`).
        ///
        /// New sources whose dispatch fits one of the existing 4
        /// routes (docs / hig / samples / packages) declare the
        /// matching enum case. Sources whose dispatch is genuinely
        /// novel return `.unified` and the dispatcher falls back to
        /// the fan-out runner — the same behaviour as the pre-#1042
        /// `default:` arm.
        var searchRoute: Search.SearchRoute { get }

        /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch
        /// strategy. Pre-fix `CLIImpl.Command.Fetch.run` had a 10-arm
        /// `switch source` enumerating every shipped source-id, each
        /// arm calling into a bespoke `run<X>Crawl/Fetch` method
        /// (~200-500 LOC each, heavy CLI-flag state coupling). Adding
        /// a new source required THREE edits in Fetch.swift alone:
        /// new case arm, new run-method, update of the default-arm
        /// error-message string listing valid sources.
        ///
        /// Post-fix each shipped `<X>Source` target supplies a
        /// `Search.SourceFetchStrategy` concrete (`<X>FetchStrategy`)
        /// that owns the per-source crawl/fetch logic. The dispatch
        /// in `CLIImpl.Command.Fetch.run` becomes a single line:
        /// `try await registry.entry(for: source).provider.makeFetchStrategy()?.run(env:)`.
        ///
        /// Sources without a fetch capability (today: `swift-book`,
        /// a view-source whose pages are co-crawled by `swift-org`
        /// via URL-prefix tagging) return nil; the default extension
        /// below returns nil. The CLI distinguishes "no strategy"
        /// from "unknown source-id" so the user gets a useful error.
        func makeFetchStrategy() -> (any Search.SourceFetchStrategy)?

        /// 2026-05-26 audit #1055: per-source read strategy. Pre-fix
        /// `Services.ReadService.readFrom` had a 3-arm bucket dispatch
        /// over `Source` (`.docs / .samples / .packages`). Adding a
        /// source with a new backend required a new arm. Post-fix the
        /// provider returns its own `Search.SourceReadStrategy` and
        /// `Services.ReadService` iterates the registry. The default
        /// extension below returns nil; per-source targets override
        /// (6 docs-tier sources return `Search.DocsReadStrategy`,
        /// `SampleCodeSource` returns `SamplesReadStrategy`,
        /// `PackagesSource` returns `PackagesReadStrategy`).
        func makeReadStrategy() -> (any Search.SourceReadStrategy)?
    }

    /// Which dispatcher runner a source uses for `cupertino search` /
    /// MCP `tools/call search`. See `Search.SourceProvider.searchRoute`.
    ///
    /// 2026-05-26 audit #1055 layer-2 follow-up: was a closed enum.
    /// A new source needing a novel dispatch had to add a new enum
    /// case AND a matching arm in BOTH the CLI Search dispatcher and
    /// the MCP `CompositeToolProvider.handleSearch` dispatcher. Now a
    /// `RawRepresentable` struct (same shape as
    /// `Search.FetchInfo.DefaultOutputDirKey` post-Cluster-9-sub-1):
    /// callers compare via `==` against static-let route constants
    /// and `default:` falls through to the unified fan-out. Adding
    /// a new route is a `static let` declaration; existing
    /// dispatchers stay backward-compatible.
    public struct SearchRoute: RawRepresentable, Sendable, Equatable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Docs DB (apple-docs / apple-archive / swift-evolution /
        /// swift-org / swift-book). Default. Named `"docs"` — not
        /// a source-id; it's the bucket-tier label for "any source
        /// whose data lives in the search.db family".
        public static let docs = SearchRoute(rawValue: Shared.Constants.SearchRouteName.docs)
        /// HIG-specific handler. Shares the name of the source-id;
        /// the routes-equal-source-ids invariant lets the dispatcher
        /// fall through to `.unified` for any unrecognised route.
        public static let hig = SearchRoute(rawValue: Shared.Constants.SourcePrefix.hig)
        /// Samples (apple-sample-code.db) — separate handler from docs.
        public static let samples = SearchRoute(rawValue: Shared.Constants.SourcePrefix.samples)
        /// Packages (packages.db) — different DB from docs.
        public static let packages = SearchRoute(rawValue: Shared.Constants.SourcePrefix.packages)
        /// Fall-back to the unified fan-out runner. Same as the
        /// pre-#1042 `default:` arm.
        public static let unified = SearchRoute(rawValue: Shared.Constants.SearchRouteName.unified)

        /// Canonical set of routes the shipped runners recognise.
        /// Surfaces in `Issue1042PluggabilityContractTests` to pin
        /// the seam without enforcing a closed-set count.
        public static let allKnownCases: [SearchRoute] = [.docs, .hig, .samples, .packages, .unified]
    }
}

extension Search.SourceProvider {
    /// Default route is `.docs` — the most common case. Sources whose
    /// dispatch differs (HIGSource, SampleCodeSource, PackagesSource)
    /// override.
    public var searchRoute: Search.SearchRoute { .docs }

    /// Default: no fetch capability. Sources whose data ships via
    /// `cupertino fetch` (apple-docs / hig / apple-archive /
    /// swift-evolution / swift-org / samples / packages) override
    /// to return their bespoke strategy concrete. Sources without
    /// a fetch step (today: `swift-book`, the view-source) inherit
    /// nil — the CLI reports "Source 'X' has no fetch capability"
    /// for those.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? { nil }
}

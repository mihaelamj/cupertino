import EnrichmentModels
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

        /// 2026-05-27: per-source enrichment passes. The composition
        /// root appends these to the generic enrichment runner after
        /// the standard passes (synonyms, constraints, hierarchy).
        /// Returns `[]` for sources without per-source enrichment.
        /// Today only `HIGSource` overrides to return its
        /// `HIGPlatformInferencePass` for topic-aware platform
        /// narrowing on HIG rows.
        ///
        /// Returning the pass instances directly (rather than a
        /// strategy or factory) lets the composition root construct
        /// them with the per-DB `searchIndex` + audit observer +
        /// dbPath without the CLI having to know which source-specific
        /// passes exist. Adding a new source-specific pass becomes a
        /// 2-file PR: the pass concrete in its source target + this
        /// override.
        func makeSourceSpecificEnrichmentPasses(
            searchIndex: any Search.IndexWriter,
            audit: (any Search.EnrichmentAuditObserver)?,
            dbPath: String
        ) -> [any EnrichmentPass]

        /// 2026-05-28 (Principle 7, per-source-DB resources): how this
        /// source's per-source SQLite DB enumerates its slice of the
        /// MCP `resources/list` page. Replaces the pre-2026-05-28
        /// `makeURIResourceStrategy()` filesystem-probing seam, which
        /// returned empty post-#1036 because the legacy monolithic
        /// `search.db` is no longer built. The composition-root lookup
        /// concrete reads the same per-source DBs the MCP search/read
        /// tools use; no filesystem is consulted.
        ///
        /// `.none` for sources that don't expose MCP-resource URIs
        /// (samples, packages); `.allDocuments` for small docs corpora
        /// (hig, swift-org, swift-book, swift-evolution, apple-archive);
        /// `.frameworkRoots` for apple-docs (too large to list per-page).
        ///
        /// Declared as a protocol requirement (not just a default
        /// extension) to defeat the Swift static-dispatch trap that
        /// bit `makeReadStrategy` during the #1055 layer-2 work — if
        /// it were extension-only, per-source overrides wouldn't win
        /// when called through `any Search.SourceProvider`.
        var resourceListMode: Search.ResourceListMode { get }

        /// Does this source's indexing strategy require a real
        /// on-disk corpus directory? Post-#1082 only alternate-input
        /// sources whose strategy ignores the directory entirely
        /// (today: `SampleCodeSource`, which reads
        /// `env.sampleCatalogProvider`) override to `false`; the CLI
        /// resolver supplies a `/dev/null` sentinel for them.
        ///
        /// View-sources that share another source's directory
        /// (today: `SwiftBookSource` over swift-org) take a different
        /// path: they declare `corpusDirectoryAlias` and inherit the
        /// parent source's resolved directory + override via
        /// `makeDocsIndexingDirectoryByKey`. They keep
        /// `requiresCorpusDirectory == true` because their strategy
        /// DOES read a directory — just not their own.
        var requiresCorpusDirectory: Bool { get }

        /// 2026-05-26 audit #1055 layer-2 part 3: is this source's
        /// `destinationDB` in the search.db FTS family?
        /// `CLIImpl.Command.Search.SmartReport.docsSources` filters
        /// by this property. Pre-fix the SmartReport had a hardcoded
        /// `excluding: [.appleSampleCode, .packages]` set — any new
        /// source with a non-FTS backend (its own bespoke index) had
        /// to be appended to that set. Now `Samples` and `Packages`
        /// override to `false`; every other source (default `true`)
        /// joins the docs-tier fan-out automatically.
        var isSearchTier: Bool { get }

        /// #1082 follow-up: when non-nil, this provider is a
        /// view-source whose corpus lives under another source's
        /// directory. The string is the `definition.id` of the
        /// "parent" source whose `corpusDirectory` this provider
        /// shares. Consumers use this to:
        ///
        /// - **Fetch dispatch** (`allFetchableSources`): skip aliased
        ///   providers — `fetch --source <parent>` already covers
        ///   their content. Spawning a separate leg would race on the
        ///   parent's session metadata and double-fetch identical
        ///   URLs.
        ///
        /// - **Doctor inventory** (`checkDocumentationDirectories`):
        ///   skip aliased providers — listing the same physical
        ///   directory twice (once for each source-id) double-counts
        ///   files and misleads users.
        ///
        /// - **Directory override propagation**
        ///   (`makeDocsIndexingDirectoryByKey`): when the parent
        ///   source has a CLI override (e.g. `--swift-org-dir
        ///   /custom`), the aliased provider inherits it. Pre-#1082
        ///   follow-up the override only propagated to the literal
        ///   sourceID-keyed entry, so swift-book silently fell back
        ///   to the default path while swift-org used the override.
        ///
        /// - **Save selection expansion** (`Save.Indexers`): `save
        ///   --source <parent>` ALSO rebuilds the aliased providers'
        ///   DBs (they read the same corpus that just got refreshed;
        ///   leaving them stale would surprise the user).
        ///
        /// Default `nil`: most providers are not view-sources.
        /// SwiftBookSource overrides to `"swift-org"` — its pages
        /// live under the swift-org corpus tree, emitted by its own
        /// strategy via `.swiftBookOnly` URL-prefix filtering.
        ///
        /// Distinct from `legacySourceIDAliases` (which is a set of
        /// CANONICALISED alias source-ids the per-source DB-split
        /// migrator should claim for this provider). Aliases there
        /// run "in the past"; `corpusDirectoryAlias` runs "right now,
        /// in parallel".
        var corpusDirectoryAlias: String? { get }
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
    public var searchRoute: Search.SearchRoute {
        .docs
    }

    /// Default: no fetch capability. Sources whose data ships via
    /// `cupertino fetch` (apple-docs / hig / apple-archive /
    /// swift-evolution / swift-org / samples / packages) override
    /// to return their bespoke strategy concrete. View-sources that
    /// share another source's corpus (today: `SwiftBookSource`)
    /// inherit nil — `cupertino fetch --source <parent>` covers
    /// their content via shared URL-prefix crawling; spawning a
    /// separate leg would double-fetch.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        nil
    }

    /// Default: this source's `destinationDB` lives in the search.db
    /// FTS family. The 2 non-FTS sources (`SampleCodeSource` reading
    /// `apple-sample-code.db` catalog tables, `PackagesSource` reading
    /// `packages.db` BM25+chunk schema) override to `false`.
    public var isSearchTier: Bool {
        true
    }

    /// Default: this source needs a real on-disk corpus directory.
    /// Alternate-input sources whose strategy doesn't read the
    /// directory at all (today: `SampleCodeSource`, which consumes
    /// `env.sampleCatalogProvider` instead) override to `false`; the
    /// CLI resolver supplies a placeholder URL so the strategy still
    /// runs in the dispatch fan-out. View-sources that share another
    /// source's directory (today: `SwiftBookSource`) declare
    /// `corpusDirectoryAlias` instead — the resolver routes them to
    /// the parent source's directory via the override-propagation
    /// path, not the placeholder.
    public var requiresCorpusDirectory: Bool {
        true
    }

    /// Default: not a view-source. Providers that share another
    /// source's on-disk corpus directory (today: `SwiftBookSource`
    /// → `"swift-org"`) override.
    public var corpusDirectoryAlias: String? {
        nil
    }

    /// Default: no per-source enrichment passes. Sources with
    /// source-specific enrichment (today: `HIGSource` →
    /// `HIGPlatformInferencePass`) override.
    public func makeSourceSpecificEnrichmentPasses(
        searchIndex _: any Search.IndexWriter,
        audit _: (any Search.EnrichmentAuditObserver)?,
        dbPath _: String
    ) -> [any EnrichmentPass] {
        []
    }
}

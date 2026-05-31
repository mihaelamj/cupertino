import EnrichmentModels
import Foundation
import SearchModels
import SharedConstants

// MARK: - HIGSource

/// `Search.SourceProvider` conformer for the `hig` source. Second
/// per-source target of the #1007 epic; mirrors the AppleDocsSource
/// pattern landed by #1008. Adding `HIGSource()` to the composition
/// root is the one-line wiring; phase 1I dissolves the older
/// `makeProductionSourceLookup()` factory + `FetchType.hig` switch
/// arms once 1B-1H all land.
///
/// Conformance assembles 4 per-source artefacts:
/// - `definition`: `Search.SourceDefinition` static literal in
///   `HIGSource.Definition.swift` (lifted from
///   `CLI/CLIImpl.SourceLookup.swift`).
/// - `fetchInfo`: `Search.FetchInfo` static literal in
///   `HIGSource.FetchInfo.swift` (lifted from
///   `CLI/SupportingTypes.swift`'s pre-#1007 `FetchType.hig` switch
///   arms).
/// - `makeStrategy(env:)`: constructs `Search.HIGStrategy` (the
///   indexing strategy concrete declared in
///   `Search.Strategies.HIG.swift`, also in this target).
/// - `makeIndexer()`: constructs `Search.HIGIndexer` (the indexer
///   concrete also in this target).
public struct HIGSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition {
        Self.definition
    }

    public var fetchInfo: Search.FetchInfo? {
        Self.fetchInfo
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor {
        .hig
    }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text],
            operations: [.readByURI],
            metadata: [
                .hasMinPlatformVersion: true,
                .hasDeprecationAttrs: true,
                .hasAvailabilityAttrs: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.HIGStrategy(
            higDirectory: env.sourceDirectory,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.HIGIndexer()
    }

    /// #1042 Cluster 8: HIG uses its own search runner (`runHIGSearch`
    /// in `CLIImpl.Command.Search` / `handleSearchHIG` in
    /// `CompositeToolProvider`); not the default `.docs` route.
    public var searchRoute: Search.SearchRoute {
        .hig
    }

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    /// Lifts `CLIImpl.Command.Fetch.runHIGCrawl` into this target so
    /// the CLI's dispatch becomes registry-driven.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        HIGFetchStrategy()
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.dbURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }

    /// 2026-05-27 (#1073): HIG-specific topic-aware platform
    /// inference. Pre-fix every HIG row was stamped with the
    /// earliest version of every Apple platform as a baseline
    /// default, so `--min-ios 16` returned watchOS- and visionOS-only
    /// HIG pages. This pass NULLs the non-applicable
    /// `min_<platform>` columns for URIs that declare an explicit
    /// platform target (designing-for-watchos, spatial-layout,
    /// mac-catalyst, carplay, etc.). Per the post-#1073 pluggability
    /// architecture HIG owns this pass, not the CLI.
    public func makeSourceSpecificEnrichmentPasses(
        searchIndex: any Search.IndexWriter,
        audit: (any Search.EnrichmentAuditObserver)?,
        dbPath: String
    ) -> [any EnrichmentPass] {
        [
            Enrichment.HIGPlatformInferencePass(
                searchIndex: searchIndex,
                audit: audit,
                dbPath: dbPath
            ),
        ]
    }
}

import CoreSampleCodeModels
import Foundation
import SearchModels
import SharedConstants

// MARK: - SampleCodeSource

/// `Search.SourceProvider` conformer for the `samples` source. Third
/// per-source target of the #1007 epic; first to require a per-source
/// runtime dep beyond the shared `IndexEnvironment` fields. Adding
/// `SampleCodeSource(fetcherFactory:)` to the composition root is the
/// one-line wiring; the `env.sampleCatalogProvider` field carries the
/// catalog dep at strategy-construction time, and the injected
/// `fetcherFactory` (a `Sample.Core.GitHubFetcherFactory` seam, #536
/// lift 3) carries the GitHub-fetch concrete without this
/// foundation-only target importing the `CoreSampleCode` producer.
///
/// Conformance assembles 4 per-source artefacts:
/// - `definition`: `Search.SourceDefinition` static literal in
///   `SampleCodeSource.Definition.swift` (lifted from
///   `CLI/CLIImpl.SourceLookup.swift`).
/// - `fetchInfo`: `Search.FetchInfo` static literal in
///   `SampleCodeSource.FetchInfo.swift` (lifted from
///   `CLI/SupportingTypes.swift`'s pre-#1007 `FetchType.samples`
///   switch arms).
/// - `makeStrategy(env:)`: constructs `Search.SampleCodeStrategy`,
///   preconditioned on `env.sampleCatalogProvider` being non-nil
///   (fail-loud-at-the-door per `docs/PRINCIPLES.md`).
/// - `makeIndexer()`: constructs `Search.SampleCodeIndexer`.
public struct SampleCodeSource: Search.SourceProvider {
    private let fetcherFactory: any Sample.Core.GitHubFetcherFactory

    public init(fetcherFactory: any Sample.Core.GitHubFetcherFactory) {
        self.fetcherFactory = fetcherFactory
    }

    public var definition: Search.SourceDefinition {
        Self.definition
    }

    public var fetchInfo: Search.FetchInfo? {
        Self.fetchInfo
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor {
        .appleSampleCode
    }

    /// SampleCodeStrategy emits rows tagged `source = "sample-code"`
    /// (a literal at `Search.Strategies.SampleCode.swift`, distinct
    /// from `definition.id = "samples"`). Without this alias, the
    /// step-6 migrator would surface those legacy rows as
    /// `unknownSourceIDs(["sample-code"])` and abort. The alias lets
    /// the migrator route `"sample-code"`-tagged rows to
    /// SampleCodeSource → `.appleSampleCode` correctly.
    public var legacySourceIDAliases: Set<String> {
        ["sample-code"]
    }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text, .sampleFiles],
            operations: [.readByURI, .listSamples],
            metadata: [
                .hasMinPlatformVersion: true,
                .hasSampleCode: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        guard let sampleCatalogProvider = env.sampleCatalogProvider else {
            preconditionFailure(
                "SampleCodeSource.makeStrategy: env.sampleCatalogProvider is required for source 'samples' but was nil. " +
                    "The composition root must supply a Search.SampleCatalogProvider in IndexEnvironment before " +
                    "constructing the SampleCodeStrategy via SampleCodeSource."
            )
        }
        return Search.SampleCodeStrategy(
            sampleCatalogProvider: sampleCatalogProvider,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.SampleCodeIndexer()
    }

    /// #1042 Cluster 8: samples use their own search runner
    /// (`runSampleSearch` / `handleSearchSamples`); not the default
    /// `.docs` route.
    public var searchRoute: Search.SearchRoute {
        .samples
    }

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        SampleCodeFetchStrategy(fetcherFactory: fetcherFactory)
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Returns nil
    /// when the identifier doesn't match a sample project / file so
    /// `Services.ReadService`'s auto-source flow can try other
    /// sources.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        SamplesReadStrategy()
    }

    /// 2026-05-26 audit #1055 layer-2 part 3: samples live in
    /// `apple-sample-code.db` with the catalog schema, NOT in the
    /// search.db FTS family. `SmartReport.docsSources()` filters
    /// non-search-tier providers out of the unified docs fan-out.
    public var isSearchTier: Bool {
        false
    }

    /// 2026-05-26 post-#1056: samples use
    /// `env.sampleCatalogProvider` for indexing instead of a corpus
    /// directory. The strategy runs in the dispatch but doesn't read
    /// from the directory parameter.
    public var requiresCorpusDirectory: Bool {
        false
    }
}

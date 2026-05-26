import Foundation
import SearchModels
import SharedConstants

// MARK: - SampleCodeSource

/// `Search.SourceProvider` conformer for the `samples` source. Third
/// per-source target of the #1007 epic; first to require a per-source
/// runtime dep beyond the shared `IndexEnvironment` fields. Adding
/// `SampleCodeSource()` to the composition root is the one-line
/// wiring; the `env.sampleCatalogProvider` field carries the catalog
/// dep at strategy-construction time.
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
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .appleSampleCode }

    /// SampleCodeStrategy emits rows tagged `source = "sample-code"`
    /// (a literal at `Search.Strategies.SampleCode.swift`, distinct
    /// from `definition.id = "samples"`). Without this alias, the
    /// step-6 migrator would surface those legacy rows as
    /// `unknownSourceIDs(["sample-code"])` and abort. The alias lets
    /// the migrator route `"sample-code"`-tagged rows to
    /// SampleCodeSource → `.appleSampleCode` correctly.
    public var legacySourceIDAliases: Set<String> { ["sample-code"] }

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
    public var searchRoute: Search.SearchRoute { .samples }

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        SampleCodeFetchStrategy()
    }
}

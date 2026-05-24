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

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .search }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.HIGStrategy(
            higDirectory: env.sourceDirectory,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.HIGIndexer()
    }
}

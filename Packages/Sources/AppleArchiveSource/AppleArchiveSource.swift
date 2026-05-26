import Foundation
import SearchModels
import SharedConstants

// MARK: - AppleArchiveSource

/// `Search.SourceProvider` conformer for the `apple-archive` source.
/// Fourth per-source target of the #1007 epic. Mirrors the HIGSource
/// shape (no extra IndexEnvironment fields needed) but carries
/// `ASTIndexer` as a dep (load-bearing for `Search.AppleArchiveIndexer`'s
/// conditional Swift-parse path).
///
/// Conformance assembles 4 per-source artefacts:
/// - `definition`: `Search.SourceDefinition` static literal in
///   `AppleArchiveSource.Definition.swift` (lifted from
///   `CLI/CLIImpl.SourceLookup.swift`).
/// - `fetchInfo`: `Search.FetchInfo` static literal in
///   `AppleArchiveSource.FetchInfo.swift` (lifted from the pre-#1007
///   `FetchType.archive` switch arms).
/// - `makeStrategy(env:)`: constructs `Search.AppleArchiveStrategy`
///   using `env.sourceDirectory` + `env.logger`.
/// - `makeIndexer()`: constructs `Search.AppleArchiveIndexer`.
public struct AppleArchiveSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .appleArchive }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text],
            operations: [.readByURI, .listFrameworks],
            metadata: [
                .hasMinPlatformVersion: true,
                .hasFrameworkColumn: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.AppleArchiveStrategy(
            archiveDirectory: env.sourceDirectory,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.AppleArchiveIndexer()
    }

    /// #1045 Gap 3: every apple-archive row classifies as `.archive`.
    public func docKind(structuredKind _: String?, uriPath _: String) -> Search.DocKind { .archive }
}

import Foundation
import SearchModels
import SharedConstants

// MARK: - AppleDocsSource

/// `Search.SourceProvider` conformer for the apple-docs source.
/// Lives in its own SPM target (`Packages/Sources/AppleDocsSource/`)
/// per the #1007 epic: a new source = a new per-source target + one
/// `.register(<X>Source())` line at the composition root, zero edits
/// to existing CLI / SearchSQLite / SearchModels code.
///
/// Conformance assembles 4 per-source artefacts:
/// - `definition`: `Search.SourceDefinition` static literal in
///   `AppleDocsSource.Definition.swift` (lifted from
///   `CLI/CLIImpl.SourceLookup.swift`).
/// - `fetchInfo`: `Search.FetchInfo` static literal in
///   `AppleDocsSource.FetchInfo.swift` (lifted from
///   `CLI/SupportingTypes.swift`'s pre-#1007 `FetchType.docs` case).
/// - `makeStrategy(env:)`: constructs `Search.AppleDocsStrategy`
///   (the indexing strategy concrete declared in
///   `Search.Strategies.AppleDocs.swift`, also in this target).
/// - `makeIndexer()`: constructs `Search.AppleDocsIndexer` (the
///   indexer concrete also in this target).
public struct AppleDocsSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .appleDocumentation }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text, .symbols, .propertyWrappers, .concurrency, .conformances, .generics],
            operations: [.readByURI, .listFrameworks, .resolveRefs],
            metadata: [
                .hasMinPlatformVersion: true,
                .hasGenerics: true,
                .hasDeprecationAttrs: true,
                .hasAvailabilityAttrs: true,
                .hasFrameworkColumn: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.AppleDocsStrategy(
            docsDirectory: env.sourceDirectory,
            markdownStrategy: env.markdownStrategy,
            logger: env.logger,
            importLogSink: env.importLogSink
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.AppleDocsIndexer()
    }
}

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

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    /// `WebCrawlFetchStrategy` is shared with `SwiftOrgSource` +
    /// `SwiftBookSource` — each constructs its own instance with its
    /// own seed URL + allowedPrefixes.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        WebCrawlFetchStrategy(
            defaultCrawlBaseURL: Self.fetchInfo.crawlBaseURLs.first ?? "",
            defaultAllowedPrefixes: nil,
            candidateSessionDirectories: []
        )
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.docsDBURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }

    /// 2026-05-26 audit Cluster 12 follow-up: per-source MCP-resource
    /// URI strategy for the `apple-docs://` scheme. Carries the lifted
    /// URI parser + framework-root filter + JSON-vs-md probe sequence
    /// that pre-fix lived in `MCP.Support.DocsResourceProvider`.
    public func makeURIResourceStrategy() -> (any Search.URIResourceStrategy)? {
        AppleDocsURIResourceStrategy()
    }
}

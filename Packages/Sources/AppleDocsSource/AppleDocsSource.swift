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
    /// #536 lift 4: the web-crawl engine (`WebCrawlFetchStrategy` +
    /// `Crawler.AppleDocs` + `Ingest`) moved out of this target into the
    /// macOS-only `Crawler` producer. This provider depends only on the
    /// `Search.WebCrawlStrategyFactory` seam; the composition root injects
    /// the live factory.
    private let webCrawlStrategyFactory: any Search.WebCrawlStrategyFactory

    public init(webCrawlStrategyFactory: any Search.WebCrawlStrategyFactory) {
        self.webCrawlStrategyFactory = webCrawlStrategyFactory
    }

    public var definition: Search.SourceDefinition {
        Self.definition
    }

    public var fetchInfo: Search.FetchInfo? {
        Self.fetchInfo
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor {
        .appleDocumentation
    }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text, .symbols, .propertyWrappers, .concurrency, .conformances, .generics],
            operations: [.readByURI, .listFrameworks, .listDocuments, .listChildren, .resolveRefs],
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
    /// The shared `WebCrawlFetchStrategy` is produced by the injected
    /// `Search.WebCrawlStrategyFactory` (#536 lift 4); swift-org +
    /// swift-book get their own instances with their own seed URL +
    /// allowedPrefixes the same way.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        webCrawlStrategyFactory.makeStrategy(
            defaultCrawlBaseURL: Self.fetchInfo.crawlBaseURLs.first ?? "",
            defaultAllowedPrefixes: nil,
            candidateSessionDirectories: []
        )
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.dbURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }

    /// Apple-docs' corpus is ~350k pages, so resources/list enumerates
    /// one entry per framework root (`apple-docs://<framework>`, ~398
    /// readable rows) instead of every sub-page. (Principle 7: the
    /// roots come straight from the per-source DB.)
    public var resourceListMode: Search.ResourceListMode {
        .frameworkRoots
    }
}

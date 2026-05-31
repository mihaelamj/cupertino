import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftOrgSource

/// `Search.SourceProvider` conformer for the `swift-org` source.
/// Sixth per-source target of the #1007 epic. Mirrors AppleArchiveSource.
///
/// #536 lift 4: the shared web-crawl engine moved into the `Crawler`
/// producer; this provider no longer imports `AppleDocsSource`. It
/// depends only on the `Search.WebCrawlStrategyFactory` seam, injected
/// by the composition root.
public struct SwiftOrgSource: Search.SourceProvider {
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

    /// Post #1038: swift-org gets its own dedicated DB
    /// (`swift-org.db`) rather than the pre-#1038 view-source
    /// co-location in `swift-documentation.db` with swift-book.
    /// Per-page emission filtering lives in
    /// `Search.SwiftOrgStrategy.indexItems` which calls the shared
    /// `Search.StrategyHelpers.crawlSwiftDocumentation` helper with
    /// `scope: .swiftOrgOnly`.
    public var destinationDB: Shared.Models.DatabaseDescriptor {
        .swiftOrg
    }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text, .symbols, .generics],
            operations: [.readByURI],
            metadata: [
                .hasGenerics: true,
                .hasAvailabilityAttrs: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.SwiftOrgStrategy(
            swiftOrgDirectory: env.sourceDirectory,
            markdownStrategy: env.markdownStrategy,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.SwiftOrgIndexer()
    }

    /// #1093: swift-org's fetch crawls ONLY swift.org. Pre-fix the
    /// allowedPrefixes also included `docs.swift.org/swift-book/`
    /// so swift-book pages were dragged in via the same pass —
    /// combined crawl was slow and the two sources couldn't be
    /// refreshed independently. Post-fix swift-book has its own
    /// fetch leg (`SwiftBookSource.makeFetchStrategy`) seeded
    /// directly at `docs.swift.org/swift-book/`; `--source swift-org`
    /// no longer traverses the book.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        webCrawlStrategyFactory.makeStrategy(
            defaultCrawlBaseURL: Self.fetchInfo.crawlBaseURLs.first ?? Shared.Constants.BaseURL.swiftOrg,
            defaultAllowedPrefixes: [Shared.Constants.BaseURL.swiftOrg],
            candidateSessionDirectories: []
        )
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.dbURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }
}

import AppleDocsSource
import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftOrgSource

/// `Search.SourceProvider` conformer for the `swift-org` source.
/// Sixth per-source target of the #1007 epic. Mirrors AppleArchiveSource.
public struct SwiftOrgSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    /// Post #1038: swift-org gets its own dedicated DB
    /// (`swift-org.db`) rather than the pre-#1038 view-source
    /// co-location in `swift-documentation.db` with swift-book.
    /// Per-page emission filtering lives in
    /// `Search.SwiftOrgStrategy.indexItems` which calls the shared
    /// `Search.StrategyHelpers.crawlSwiftDocumentation` helper with
    /// `scope: .swiftOrgOnly`.
    public var destinationDB: Shared.Models.DatabaseDescriptor { .swiftOrg }

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

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    /// Constructs `AppleDocsSource.WebCrawlFetchStrategy` with
    /// swift-org's canonical seed + the multi-host prefix allowlist
    /// (covers both `www.swift.org` and `docs.swift.org` so the
    /// view-source `swift-book` pages get crawled in the same pass).
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        WebCrawlFetchStrategy(
            defaultCrawlBaseURL: Self.fetchInfo.crawlBaseURLs.first ?? Shared.Constants.BaseURL.swiftOrg,
            defaultAllowedPrefixes: [
                Shared.Constants.BaseURL.swiftOrg,
                Shared.Constants.BaseURL.swiftBook,
            ],
            candidateSessionDirectories: []
        )
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.docsDBURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }
}

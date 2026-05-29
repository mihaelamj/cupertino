import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftBookSource

/// `Search.SourceProvider` conformer for the `swift-book` source.
/// Post #1038 ("diff db for each source" follow-up to #1037), the
/// Swift Book has its own DB (`swift-book.db`) and its own active
/// strategy (`Search.SwiftBookStrategy`) rather than the pre-#1038
/// view-source pattern (where SwiftOrgStrategy emitted both sub-sources
/// into `swift-documentation.db` and SwiftBookSource was a no-op).
///
/// Pluggability is preserved: SwiftBookSource imports only Foundation
/// + SearchModels + SharedConstants + SearchStrategyHelpers (the
/// neutral shared-helper target), per
/// `mihaela-agents/Rules/swift/per-package-import-contract.md`. No
/// cross-source-target imports. The shared web-crawl strategy reaches
/// it through the `Search.WebCrawlStrategyFactory` seam, injected by the
/// composition root (#536 lift 4).
///
/// Conformance facets:
/// - `definition`: lifted from `CLI/CLIImpl.SourceLookup.swift`
/// - `fetchInfo`: `nil` (no dedicated fetch; SwiftOrgStrategy's single
///   crawl over `docs.swift.org` produces both sub-sources' files;
///   SwiftBookSource just walks the same on-disk corpus directory).
/// - `destinationDB`: `.swiftBook` (filename `swift-book.db`).
/// - `makeStrategy(env:)`: returns `Search.SwiftBookStrategy`, which
///   delegates to `Search.StrategyHelpers.crawlSwiftDocumentation(
///   scope: .swiftBookOnly)`. The shared helper does the file walk +
///   per-page decoding + index emission; the scope filter discards
///   swift-org-tagged pages (those land in `swift-org.db` via
///   `SwiftOrgSource`'s `.swiftOrgOnly` invocation).
/// - `makeIndexer()`: returns `Search.SwiftBookIndexer()`.
public struct SwiftBookSource: Search.SourceProvider {
    private let webCrawlStrategyFactory: any Search.WebCrawlStrategyFactory

    public init(webCrawlStrategyFactory: any Search.WebCrawlStrategyFactory) {
        self.webCrawlStrategyFactory = webCrawlStrategyFactory
    }

    public var definition: Search.SourceDefinition {
        Self.definition
    }

    /// #1093: swift-book is independently fetchable. Pre-#1093 it
    /// was a view-source over swift-org's crawl
    /// (`corpusDirectoryAlias = .swiftOrg`), which meant a fetch of
    /// either source dragged in the other. Post-fix swift-book has
    /// its own fetchInfo with `defaultOutputDirKey = .swiftBook`,
    /// its own seed URL (`docs.swift.org/swift-book/`), and its own
    /// corpus dir. The `corpusDirectoryAlias` property override is
    /// dropped (default `nil` from the protocol extension).
    public var fetchInfo: Search.FetchInfo? {
        Self.fetchInfo
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor {
        .swiftBook
    }

    /// Swift Book read-side capabilities. The Book is universal text +
    /// tutorial-grade code samples; the searcher + metadata matrix is
    /// a subset of SwiftOrgSource's (no generics-search because the
    /// Book's code fences aren't type-graph-extractable like Swift.org's
    /// API references).
    public var capabilities: Search.Capabilities {
        // #1154: swift-book.db carries `doc_symbols` (SwiftBookIndexer runs
        // ASTIndexer.Extractor over the book's code blocks), so it joins the
        // AST symbol + generic-constraint fan-out alongside apple-docs and
        // swift-org. Mirrors swift-org's docs-tier Swift-code searcher set.
        .init(
            searchers: [.text, .symbols, .generics],
            operations: [.readByURI],
            metadata: [
                .hasAvailabilityAttrs: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.SwiftBookStrategy(
            swiftOrgDirectory: env.sourceDirectory,
            markdownStrategy: env.markdownStrategy,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.SwiftBookIndexer()
    }

    /// #1093: swift-book has its own independent fetch leg seeded at
    /// `docs.swift.org/swift-book/`. Crawls only the book pages
    /// (~50), not swift.org's full content tree. Output dir is
    /// `cupertino-fresh/swift-book/` (separate from swift-org's
    /// dir). Allowed prefixes restrict the crawler to docs.swift.org
    /// only — no traversal into www.swift.org.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        webCrawlStrategyFactory.makeStrategy(
            defaultCrawlBaseURL: Shared.Constants.BaseURL.swiftBook,
            defaultAllowedPrefixes: [Shared.Constants.BaseURL.swiftBook],
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

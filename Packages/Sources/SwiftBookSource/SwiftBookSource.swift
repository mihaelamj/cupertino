import AppleDocsSource
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
/// cross-source-target imports.
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
    public init() {}

    public var definition: Search.SourceDefinition {
        Self.definition
    }

    /// #1082: swift-book is a view-source over the swift-org crawl —
    /// the strategy walks swift-org's corpus tree and filters by
    /// URL-prefix to emit only swift-book-tagged pages. Pre-#1082
    /// `fetchInfo` was nil and `requiresCorpusDirectory: false`,
    /// which routed the strategy to a `/dev/null` placeholder and
    /// left `swift-book.db` empty. Post-fix the FetchInfo declares
    /// `defaultOutputDirKey = .swiftOrg` (shared with SwiftOrgSource)
    /// so the resolver routes the strategy to the real corpus tree.
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
        .init(
            searchers: [.text],
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

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    /// SwiftBook is a view-source — its pages live under the swift-org
    /// crawl. `cupertino fetch --source swift-book` piggy-backs on
    /// swift-org's crawl (matches pre-fix runStandardCrawl behavior
    /// where swift-book aliased to swift-org's seed URL). The strategy
    /// constructed here seeds the crawler with swift-org's URL +
    /// allowedPrefixes; the SwiftBookStrategy's URL-prefix tagging
    /// during indexing routes the resulting pages into swift-book.db.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        WebCrawlFetchStrategy(
            defaultCrawlBaseURL: Shared.Constants.BaseURL.swiftOrg,
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

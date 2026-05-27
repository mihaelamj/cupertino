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

    /// `fetchInfo` stays nil: swift-book has no fetch leg of its own.
    /// `cupertino fetch --source swift-org` covers swift-book's pages
    /// via shared URL-prefix crawling. The corpus directory is routed
    /// via `corpusDirectoryAlias` (below), which the CLI resolver
    /// uses to inherit swift-org's directory + any `--swift-org-dir`
    /// override.
    public var fetchInfo: Search.FetchInfo? {
        nil
    }

    /// #1082: swift-book is a view-source over swift-org's corpus
    /// tree. The resolver routes the SwiftBookStrategy to swift-org's
    /// directory (inheriting any `--swift-org-dir` CLI override) by
    /// reading this property. Pre-#1082 the strategy walked a
    /// `/dev/null` placeholder and `swift-book.db` ended up empty.
    public var corpusDirectoryAlias: String? {
        Shared.Constants.SourcePrefix.swiftOrg
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

    // #1082 follow-up: no independent fetch strategy. SwiftBook is a
    // view-source over swift-org's corpus (`corpusDirectoryAlias =
    // "swift-org"`); `cupertino fetch --source swift-org` covers
    // its pages via shared URL-prefix crawling. Spawning a separate
    // swift-book fetch leg would race on swift-org's session
    // metadata and double-fetch identical URLs. Inherits the
    // default `nil` from the protocol extension.

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.docsDBURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }
}

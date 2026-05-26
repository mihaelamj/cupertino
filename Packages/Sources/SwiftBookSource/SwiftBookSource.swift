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

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { nil }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .swiftBook }

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

    /// #1045 Gap 3: every swift-book row is part of the Swift book.
    public func docKind(structuredKind _: String?, uriPath _: String) -> Search.DocKind { .swiftBook }
}

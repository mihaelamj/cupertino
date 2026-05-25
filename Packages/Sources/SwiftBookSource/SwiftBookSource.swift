import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftBookSource

/// `Search.SourceProvider` conformer for the `swift-book` source.
/// Seventh per-source target of the #1007 epic; first **view-source**:
/// no dedicated strategy or fetch endpoint, because the actual
/// crawl + page emission lives in `Search.SwiftOrgStrategy` (the
/// strategy tags individual pages with `source = swift-book` or
/// `source = swift-org` based on the URL prefix). SwiftBookSource
/// represents the queryable source identity, contributes the
/// SourceDefinition (for `cupertino search` ranking and the source
/// catalog), and supplies the indexer concrete (used by
/// `Search.IndexBuilder` at `extractCode` time when a page resolves
/// to `swift-book`).
///
/// Conformance facets:
/// - `definition`: lifted from `CLI/CLIImpl.SourceLookup.swift`
/// - `fetchInfo`: **`nil`** (no dedicated fetch; SwiftOrgStrategy's
///   crawl over `docs.swift.org` covers the swift-book corpus)
/// - `destinationDB`: `.swiftDocumentation` (post step 4 of
///   per-source-db-split.md; co-located with swift-org via view-source)
/// - `makeStrategy(env:)`: returns a private no-op
///   `SwiftBookViewSourceStrategy` that emits zero items and an
///   empty `IndexStats`. The real strategy emission is owned by
///   `SwiftOrgSource.makeStrategy(env:)`.
/// - `makeIndexer()`: returns `Search.SwiftBookIndexer()`.
///
/// The view-source pattern is a first-class shape in `Search.SourceProvider`:
/// a source may not own its own crawl/emit pipeline, but the protocol
/// still requires it to declare its destination DB + definition +
/// indexer.
public struct SwiftBookSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { nil }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .swiftDocumentation }

    /// Empty capabilities (view-source). swift-book rows live in
    /// swift-documentation.db; queries against that DB go through
    /// SwiftOrgSource's capabilities, not SwiftBookSource's. The
    /// dispatcher's groupBy(destinationDB) sees the swift-org
    /// provider's full capability matrix; SwiftBookSource registers
    /// for SourceLookup parity but contributes no capability bits.
    public var capabilities: Search.Capabilities { .empty }

    public func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        SwiftBookViewSourceStrategy()
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.SwiftBookIndexer()
    }
}

// MARK: - View-source no-op strategy

/// Private no-op `Search.SourceIndexingStrategy` for the swift-book
/// view-source. The actual page emission for swift-book content runs
/// inside `Search.SwiftOrgStrategy`, which tags pages whose URLs sit
/// under `docs.swift.org/swift-book/` with `source = swift-book`. The
/// composition root still needs `SwiftBookSource.makeStrategy(env:)`
/// to return something `Search.SourceIndexingStrategy`-shaped so the
/// strategies-list iteration in the registry-driven path stays
/// uniform; this conformer satisfies that with zero side effects.
private struct SwiftBookViewSourceStrategy: Search.SourceIndexingStrategy {
    let source = Shared.Constants.SourcePrefix.swiftBook

    func indexItems(
        into _: any Search.Database & Search.IndexWriter,
        progress _: (any Search.IndexingProgressReporting)?
    ) async throws -> Search.IndexStats {
        // Report wasSkipped so IndexBuilder's per-source breakdown log
        // emits `[swift-book] skipped (view-source; ...)` instead of
        // the misleading `[swift-book] indexed: 0, skipped: 0` (the
        // #671 anti-pattern of implying a failed indexing attempt
        // when nothing was attempted). Real swift-book rows are
        // emitted by Search.SwiftOrgStrategy via URL-prefix tagging.
        Search.IndexStats(
            source: source,
            indexed: 0,
            skipped: 0,
            wasSkipped: true,
            skipReason: "view-source; rows emitted by Search.SwiftOrgStrategy"
        )
    }
}

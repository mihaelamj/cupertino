import Foundation
import SearchModels
import SharedConstants

// MARK: - PackagesSource

/// `Search.SourceProvider` conformer for the `packages` source.
/// Eighth (final) per-source target of the #1007 epic, and the
/// first source whose `destinationDB` is **not** `.search`.
///
/// PackagesSource validates the destinationDB protocol extension
/// landed in #1014: the field's discriminator value lets the
/// composition root route each provider to the right index builder.
/// Today PackagesSource declares `.packages`; phase 1I (the next
/// epic step) wires that consumer logic.
///
/// **No live `Search.SourceIndexingStrategy` or `Search.SourceIndexer`**
/// for this source: #789 removed the search.db `packages` table
/// along with `Search.SwiftPackagesStrategy` and the in-search.db
/// `PackagesIndexer`. Today the `cupertino fetch --packages` flow
/// and the packages.db indexer both run through
/// `Indexer.PackagesService`, a bespoke pipeline that bypasses
/// `SourceProvider` entirely. PackagesSource contributes:
/// - `definition`: lifted from `CLIImpl.SourceLookup.swift`. Lets
///   queries discover the source and apply ranking weights.
/// - `fetchInfo`: non-nil. Lets `cupertino fetch` discover the
///   source. The fetch dispatcher delegates the actual download to
///   the dedicated packages pipeline; the FetchInfo here is
///   metadata only.
/// - `destinationDB`: `.packages` (load-bearing).
/// - `makeStrategy(env:)`: no-op `PackagesViewSourceStrategy`
///   (matches the view-source pattern established by
///   `SwiftBookSource`, generalized here for non-search.db sources).
/// - `makeIndexer()`: no-op `PackagesViewSourceIndexer` (no search.db
///   indexer exists; the bespoke packages.db indexer is invoked by
///   the dedicated `Indexer.PackagesService`).
public struct PackagesSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .packages }

    public func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        PackagesViewSourceStrategy()
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        PackagesViewSourceIndexer()
    }
}

// MARK: - View-source no-op concretes

/// Private no-op `Search.SourceIndexingStrategy` for the packages
/// view-source. The actual fetch + indexing for the `packages`
/// source runs in `Indexer.PackagesService` against packages.db,
/// outside the `SourceProvider` pipeline. This conformer exists so
/// the strategies-list iteration in the registry-driven path
/// (post-#1007 phase 1I) stays uniform across all sources.
private struct PackagesViewSourceStrategy: Search.SourceIndexingStrategy {
    let source = Shared.Constants.SourcePrefix.packages

    func indexItems(
        into _: any Search.Database & Search.IndexWriter,
        progress _: (any Search.IndexingProgressReporting)?
    ) async throws -> Search.IndexStats {
        Search.IndexStats(source: source, indexed: 0, skipped: 0)
    }
}

/// Private no-op `Search.SourceIndexer` for the packages view-source.
/// #789 removed the search.db `packages` table + its indexer; today
/// packages indexing happens in packages.db via the dedicated
/// `Indexer.PackagesService`. This conformer exists only so the
/// indexer-dict iteration in the registry-driven path stays
/// uniform; production code routes packages source-ids to the
/// packages.db pipeline based on `destinationDB == .packages`.
private struct PackagesViewSourceIndexer: Search.SourceIndexer {
    let sourceID = Shared.Constants.SourcePrefix.packages
    let displayName = "Swift Packages"
}

import AppleArchiveSource
import AppleDocsSource
import Foundation
import HIGSource
import PackagesSource
import SampleCodeSource
import SearchModels
import SwiftBookSource
import SwiftEvolutionSource
import SwiftOrgSource

// MARK: - CLIImpl.makeProductionSourceRegistry

/// Composition-root factory that returns the post-#1007
/// `Search.SourceRegistry` populated with the production source
/// providers. Each `<X>Source` per-source SPM target exposes a
/// `Search.SourceProvider` conformer; this factory registers them
/// in the printable order the CLI surfaces use.
///
/// **Post-#1025 (Phase 1I.a of epic #1007)**: this factory is now the
/// canonical source-of-truth for the production source list. The
/// older `makeProductionSourceLookup()` was deleted in #1025; today
/// `Search.SourceLookup` is constructed from
/// `makeProductionSourceRegistry().allEnabled.map(\.definition)`. The
/// protocol's `destinationDB` requirement (introduced in #1014) is
/// the discriminator the composition root uses to dispatch each
/// provider to its destination DB: the indexer dict at the search.db
/// composition site filters by `destinationDB == .search` (1I.b /
/// #1027); the strategies-list assembly does the same (1I.c.1 /
/// #1029). The remaining 1I.c.2 work dissolves the `FetchType`
/// enum + Fetch CLI command and uses the same destinationDB
/// discriminator for write-DB dispatch.
///
/// **Adding a new source post-#1007:** one new `<X>Source` target +
/// one `.register(<X>Source())` append below. Zero edits to
/// `SearchSQLite`, `CLI/SupportingTypes`, or `SearchModels` (per
/// #1007's #1008 acceptance criteria).
extension CLIImpl {
    /// Canonical source-of-truth for the production source list
    /// (post-#1025; the older `makeProductionSourceLookup` literal
    /// list was deleted in Phase 1I.a). Callers that need a
    /// `Search.SourceLookup` derive it from
    /// `Search.SourceLookup(definitions: makeProductionSourceRegistry().allEnabled.map(\.definition))`.
    static func makeProductionSourceRegistry() -> Search.SourceRegistry {
        var registry = Search.SourceRegistry()
        registry.register(AppleDocsSource())
        registry.register(HIGSource())
        registry.register(SampleCodeSource())
        registry.register(AppleArchiveSource())
        registry.register(SwiftEvolutionSource())
        registry.register(SwiftOrgSource())
        registry.register(SwiftBookSource())
        registry.register(PackagesSource())
        // #1007 Phase 1A-1I.c.1 complete: registry carries all 8 sources;
        // sourceLookup derived from the registry (1I.a, #1025); indexer
        // dict derived from the registry filtered by `destinationDB ==
        // .search` (1I.b, #1027); strategies-list derived from the
        // same registry+filter (1I.c.1, #1029). Phase 1I.c.2
        // (final-of-final) dissolves the `FetchType` enum + Fetch CLI
        // command at
        // `CLI/SupportingTypes.swift`; wires the destinationDB-aware
        // composition root that groups providers by destination DB.
        return registry
    }
}

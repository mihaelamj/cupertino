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
/// provider to its destination DB. Post-step-4 of
/// per-source-db-split.md, the indexer dict + strategies list at the
/// search.db composition site filter by `destinationDB != .packages`
/// (transitional: all 7 search-style sources still co-locate in
/// search.db until step 5 wires `Dictionary(grouping: by: \.destinationDB)`).
/// Pre-step-4 the filter was `destinationDB == .search` (1I.b / #1027
/// + 1I.c.1 / #1029).
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
        // #1007 epic complete; per-source-db-split.md steps 1-4 layered
        // on top: registry carries all 8 sources; sourceLookup derived
        // from the registry (#1025); indexer dict + strategies list
        // post-step-4 filter by `destinationDB != .packages` (transitional;
        // the original #1027 / #1029 filter was `== .search`).
        // Step 5 replaces the transitional filter with
        // `Dictionary(grouping: by: \.destinationDB)`.
        return registry
    }
}

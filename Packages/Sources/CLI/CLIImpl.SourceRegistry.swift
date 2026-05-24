import AppleDocsSource
import Foundation
import HIGSource
import SampleCodeSource
import SearchModels

// MARK: - CLIImpl.makeProductionSourceRegistry

/// Composition-root factory that returns the post-#1007
/// `Search.SourceRegistry` populated with the production source
/// providers. Each `<X>Source` per-source SPM target exposes a
/// `Search.SourceProvider` conformer; this factory registers them
/// in the printable order the CLI surfaces use.
///
/// **Parallel path** during the #1007 epic transition: this factory
/// runs alongside the older `makeProductionSourceLookup()` (which
/// holds 8 inline `SourceDefinition` literals) until phases 1B-1H
/// migrate the remaining sources into per-source targets and phase
/// 1I dissolves the older factory. As of #1012, AppleDocs / HIG /
/// SampleCode are migrated; the registry surface stays valid for
/// the eventual full set.
///
/// **Adding a new source post-#1007:** one new `<X>Source` target +
/// one `.register(<X>Source())` append below. Zero edits to
/// `SearchSQLite`, `CLI/CLIImpl.SourceLookup`, `CLI/SupportingTypes`,
/// or `SearchModels` (per #1007's #1008 acceptance criteria).
extension CLIImpl {
    static func makeProductionSourceRegistry() -> Search.SourceRegistry {
        var registry = Search.SourceRegistry()
        registry.register(AppleDocsSource())
        registry.register(HIGSource())
        registry.register(SampleCodeSource())
        // #1007 Phase 1D-1H: 5 more sources migrate one PR at a time.
        // Each migration appends one `.register(<X>Source())` line above
        // and removes the corresponding entry from the older
        // `makeProductionSourceLookup()` literal list.
        return registry
    }
}

import CupertinoComposition
import Foundation
import SearchModels
import SharedConstants

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
        // 2026-05-26 audit: single canonical declaration lives in
        // `CupertinoComposition.makeProductionSourceRegistry()`. Adding
        // a new source = one `.register(<X>Source())` line in
        // `Cupertino.CompositionRoot.swift`; CLI, MCP, Doctor,
        // SaveSiblingGate, ReadService, and the SearchToolProvider
        // test fixture all consume the same registry through this
        // single factory. The legacy per-source target imports moved
        // out of this file; CLI no longer imports the per-source
        // targets directly because the composition root does.
        CupertinoComposition.makeProductionSourceRegistry()
    }

    /// Set of database descriptors the production `cupertino-docs` bundle
    /// ships at the current binary's version. Derived from the production
    /// source registry's `allEnabled` providers — each source declares its
    /// own `destinationDB`, and the bundle must ship one zip-extractable
    /// SQLite file per declared destination.
    ///
    /// **Pluggability anchor**: adding a new source (one new
    /// `<X>Source.swift` + one `.register(<X>Source())` line above)
    /// automatically extends this list. The `cupertino setup` post-extract
    /// hard-fail check then verifies the new source's DB landed in the
    /// extracted bundle without any further CLI-side edits.
    ///
    /// **Bundle-release coupling**: the ReleaseTool that builds
    /// `cupertino-databases-vX.Y.Z.zip` must include every descriptor in
    /// this list in the zip. Adding a new source therefore couples
    /// (a) the cupertino source-tree PR (1 source file + 1 register line)
    /// with (b) the ReleaseTool's bundle-build manifest update. The CLI
    /// side stays pluggable on its own; the bundle side is a sibling
    /// concern owned by ReleaseTool.
    public static func bundleRequiredDescriptors() -> [Shared.Models.DatabaseDescriptor] {
        makeProductionSourceRegistry().allEnabled.map(\.destinationDB)
    }

    // MARK: - #1045 composition-root helpers

    //
    // Each helper below is named + pure: given a `Search.SourceRegistry`
    // (or a `Shared.Paths` for path-aware helpers), return the dict the
    // production CLI command should pass to its consumer. The CLI
    // command paths invoke these helpers; the behavioural test suite
    // (`Issue1045BehavioralWiringTests`) invokes them too. A separate
    // grep-based regression test (`Issue1045ProductionCallSiteTests`)
    // pins the production CLI files to actually call each helper, so
    // a refactor that drops the call breaks tests immediately.

    /// #1045 Gap 1: build the per-source `rankWeight` dict the CLI
    /// passes to `Search.SmartQuery.init(sourceWeightsOverride:)`.
    /// Pre-fix this assembly was inline in `CLIImpl.Command.Search.run`;
    /// extracted to make the production wiring testable without
    /// invoking the full command shell.
    public static func makeSmartQuerySourceWeights(
        registry: Search.SourceRegistry
    ) -> [String: Double] {
        Dictionary(
            uniqueKeysWithValues: registry.allEnabled.map { provider in
                (provider.definition.id, provider.definition.properties.rankWeight)
            }
        )
    }

    /// #1045 Gap 2: build the source-id list the CLI passes to every
    /// formatter's `availableSources:` parameter (used to render the
    /// always-present "All sources you can search" block in
    /// `Services.Formatter.Footer.Search`).
    public static func makeFormatterAvailableSources(
        registry: Search.SourceRegistry
    ) -> [String] {
        registry.allEnabled.map(\.definition.id)
    }

    /// #1045 Gap 4: build the per-source directory dict the CLI passes
    /// to `Indexer.DocsService.Request.directoryByKey` and that
    /// `Search.DocsIndexing.Input.directoryByKey` carries through to
    /// `CLIImpl.Command.Save.Indexers.resolveSourceDirectory(for:input:)`.
    /// Each provider's `fetchInfo?.defaultOutputDirKey.rawValue`
    /// resolves against `Shared.Paths.directory(named:)`.
    ///
    /// `overrides` is the CLI-flag override layer — when the user
    /// passes `--docs-dir /custom`, the composition root supplies
    /// `["apple-docs": URL(.../custom)]` and the helper threads that
    /// non-nil entry through instead of the registry default. Closes
    /// the latent regression where Gap-4's dict path bypassed the
    /// CLI's typed-field overrides: pre-fix the dict ALWAYS won, so
    /// `--docs-dir /custom` was silently ignored. Post-fix overrides
    /// win, registry defaults backstop, view-sources inherit their
    /// parent via `corpusDirectoryAlias` (#1082 follow-up), and any
    /// provider without a `fetchInfo` + without an alias falls
    /// through to nil.
    public static func makeDocsIndexingDirectoryByKey(
        registry: Search.SourceRegistry,
        paths: Shared.Paths,
        overrides: [String: URL?] = [:]
    ) -> [String: URL?] {
        // First pass: resolve each non-view-source provider's
        // directory (override → fetchInfo dir → nil). Aliased
        // providers are deferred so they can inherit the resolved
        // parent value in the second pass.
        var resolved: [String: URL?] = [:]
        for provider in registry.allEnabled where provider.corpusDirectoryAlias == nil {
            let sourceID = provider.definition.id
            if let overrideEntry = overrides[sourceID], let url = overrideEntry {
                // #1046 (+ #779): resolve symlinks at construction.
                resolved[sourceID] = url.resolvingSymlinksInPath()
                continue
            }
            resolved[sourceID] = provider.fetchInfo.flatMap { fi in
                paths.directory(named: fi.defaultOutputDirKey.rawValue).resolvingSymlinksInPath()
            }
        }
        // Second pass: view-sources inherit the resolved parent
        // entry (so `--swift-org-dir /custom` propagates to swift-book
        // automatically). The explicit per-provider override still
        // wins over the inherited parent value — a user who passes
        // BOTH `--swift-org-dir A` and `--swift-book-dir B` gets the
        // explicit B (rare but well-defined).
        for provider in registry.allEnabled where provider.corpusDirectoryAlias != nil {
            let sourceID = provider.definition.id
            if let overrideEntry = overrides[sourceID], let url = overrideEntry {
                resolved[sourceID] = url.resolvingSymlinksInPath()
                continue
            }
            if let aliasParent = provider.corpusDirectoryAlias,
               let parentEntry = resolved[aliasParent] {
                resolved[sourceID] = parentEntry
                continue
            }
            // Aliased provider whose parent isn't in the registry
            // (shouldn't happen in production; defensive). Fall back
            // to the same fetchInfo / nil shape the non-aliased
            // branch uses.
            resolved[sourceID] = provider.fetchInfo.flatMap { fi in
                paths.directory(named: fi.defaultOutputDirKey.rawValue).resolvingSymlinksInPath()
            }
        }
        return resolved
    }

    /// #1045 Gap 3: build the source-id → DocKind rawValue dict
    /// (string-typed; SearchSQLite resolves to `DocKind` via
    /// `init(rawValue:)`). Each provider's `defaultDocKindRawValue` on
    /// its `Search.SourceDefinition` populates the dict; sources with
    /// nil rawValue (e.g. apple-docs's bespoke classifier path) are
    /// absent.
    ///
    /// Today this helper is consumed by `Search.SourceLookup`
    /// (via `SourceLookup.docKindRawValuesByID`) which the Search.Index
    /// actor holds; the helper exists for symmetry with the other
    /// Gap helpers + so the grep test can pin the CLI's construction
    /// pattern.
    public static func makeDocKindRawValuesByID(
        registry: Search.SourceRegistry
    ) -> [String: String] {
        var result: [String: String] = [:]
        for provider in registry.allEnabled {
            if let rawValue = provider.definition.defaultDocKindRawValue {
                result[provider.definition.id] = rawValue
            }
        }
        return result
    }

    /// 2026-05-26 audit Finding 14.3: build the source-id →
    /// destinationDB dict that `Services.ReadService.resolveSource`
    /// consumes to classify a CLI `--source <id>` value into one of
    /// 3 backend buckets (.docs / .samples / .packages). Pre-fix
    /// `resolveSource` had a hardcoded 9-arm switch enumerating every
    /// shipped source-id; post-fix the dict is registry-derived so a
    /// new source flows through automatically.
    public static func makeDestinationsByID(
        registry: Search.SourceRegistry
    ) -> [String: Shared.Models.DatabaseDescriptor] {
        Dictionary(
            uniqueKeysWithValues: registry.allEnabled.map { provider in
                (provider.definition.id, provider.destinationDB)
            }
        )
    }
}

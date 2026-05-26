# How to add a new content source

**State**: living doc. Reflects the post-#1042 pluggability arc as of 2026-05-26. Contract status: **26 of 26 assertions green**. Two architectural follow-ups remain queued but are not blocking the structural pluggability claim: rewiring the CLI + MCP search dispatch switches to iterate the new `Search.SourceProvider.searchRoute` property (Cluster 8 follow-up); and threading per-source `URIResourceStrategy` conformers through `MCP.Support.DocsResourceProvider` (Cluster 12 follow-up). Both are queued as a single focused PR.

This page is the contract a contributor follows when wiring a new content source (e.g. WWDC transcripts #58, Swift Forums #89, Tech Talks #273) into cupertino. It names every file the new source MUST touch and distinguishes them from surfaces that pick the source up automatically once it is registered.

The shape is "what is true today", not "what will be true after the pluggability epic closes". The "Still required edits" section names the surfaces still hardcoded against the 8 shipped sources; each is tracked by an OUTSTANDING assertion in `Packages/Tests/CLITests/Issue1042PluggabilityContractTests.swift` and shrinks as cluster-flip PRs land.

## Required: the four lines that register a new source

A new source's minimum surface area today is:

1. **A new SPM target** named `<X>Source` under `Packages/Sources/<X>Source/` carrying the `Search.SourceProvider` conformer, the indexer concrete, and the strategy concrete.
2. **One line appended to `allSourceTargetNames`** in `Packages/Package.swift` (#1042 Cluster 14 closed this; before, the same name was repeated across 4 lists).
3. **One `.register(<X>Source())` line** in `CLIImpl.makeProductionSourceRegistry()` (`Packages/Sources/CLI/CLIImpl.SourceRegistry.swift`).
4. **A `Shared.Models.DatabaseDescriptor` row** for the new source's destination DB (this is where the indexed rows land). Today every shipped source has its own descriptor post per-source DB split #1036.

Plus the per-source manifest documentation page at `docs/sources/<source-id>/manifest.yaml` (corpus shape, not code).

## The `Search.SourceProvider` protocol

Declared in `Packages/Sources/SearchModels/Search.SourceProvider.swift`. The 7 required surfaces:

```swift
public struct WWDCSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition {
        Search.SourceDefinition(
            id: "wwdc",
            displayName: "WWDC Transcripts",
            emoji: "🎬",
            properties: Search.SourceProperties(
                authority: 0.9,         // 0...1 — Apple-published = 1.0; community = 0.3
                freshness: 0.7,
                comprehensiveness: 0.6,
                codeExamples: 0.4,
                hasAvailability: 0.0,    // no API version axis on a transcript
                designFocus: 0.5,
                languageFocus: 0.3,
                searchQuality: 0.7       // used by SmartQuery fusion (still hardcoded; see Cluster 3)
            ),
            intents: [.howTo, .api]      // which query intents this source serves
        )
    }

    public var fetchInfo: Search.FetchInfo? {
        Search.FetchInfo(
            displayName: "WWDC Transcripts",
            sourceID: "wwdc",
            crawlBaseURLs: ["https://developer.apple.com/wwdc/"],
            defaultOutputDirKey: Search.FetchInfo.DefaultOutputDirKey(rawValue: "wwdc"),
            // ... see existing concretes
        )
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .wwdc }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text],
            operations: [.readByURI],
            metadata: [
                .hasMinPlatformVersion: false,
                .hasFrameworkColumn: false,
            ]
        )
    }

    public var legacySourceIDAliases: Set<String> { [] }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.WWDCStrategy(
            wwdcDirectory: env.sourceDirectory,
            markdownStrategy: env.markdownStrategy,
            logger: env.logger,
            importLogSink: env.importLogSink
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.WWDCIndexer()
    }
}
```

The strategy + indexer concretes live in the same target. Look at `Packages/Sources/AppleDocsSource/` for the reference layout (Strategy.swift, Indexer.swift, FetchInfo.swift, Definition.swift, Provider.swift).

## Pluggable today (no edits when adding a new source)

These surfaces pick up the new source automatically once it is registered. Each row corresponds to a now-green cluster in the #1042 pluggability contract:

| Surface | Cluster | What is automatic |
|---|---|---|
| `Distribution.SetupService.Request.required` | 1 | Setup's required-DB list is derived from the registry's `allEnabled.map(\.destinationDB)`. |
| MCP `search` tool's `source` enum schema | 7 | `CompositeToolProvider.searchToolSourceEnumValues` is supplied by the Serve composition root from `makeProductionSourceRegistry().allEnabled.map(\.definition.id)`. |
| `Search.FetchInfo.DefaultOutputDirKey` | 9 sub-1 | Closed enum became `struct DefaultOutputDirKey: RawRepresentable`. New keys are `static let` declarations; the CLI's `resolveDirectory(forKey:paths:)` delegates to `Shared.Paths.directory(named: key.rawValue)`. |
| `SaveSiblingGate.Target` | 9 sub-2 | Closed enum became `struct Target: RawRepresentable`; `dbFilename` is `"\(rawValue).db"`. |
| `Services.ReadService.Source` | 9 sub-3 | Closed enum became `struct Source: RawRepresentable`. The dispatcher's exhaustive switch became `if source == .docs / .samples / .packages` with `.unknownSource(rawValue)` fallthrough. |
| `LoggingModels.Logging.Category` | 10 | Closed enum became `struct Category: RawRepresentable`. `Logging.LiveRecording.mapCategory`'s exhaustive switch became a dict lookup with `.cli` fallback for unknown categories. |
| `RemoteSync.IndexState.Phase` | 11 sub-1 | Closed enum became `struct Phase: RawRepresentable, Codable` (Codable preserved so on-disk `index-state.json` files keep loading). The 3 dispatch switches in `RemoteSync.Indexer` (`phasePath`, `phaseSource`, `buildURI`) became static-dict lookups keyed by Phase. |
| `Shared.Paths.directory(named:)` | 13 | Generic accessor; the 8 per-source typed accessors (`docsDirectory`, …) now delegate. Consumers should migrate to the generic + the source's own `fetchInfo.outputDir`. |
| Package.swift test/binary dep lists | 14 | `allSourceTargetNames` is the single source of truth; `allSourceTargetDeps` + `allSourceProducts` derive from it. `SearchTests`, `SearchStrategiesTests`, `SearchModelsTests`, and the cupertino CLI binary all spread the helper. |
| Platform-filter dispatch fan-out partition | 5 sub-2 | `Search.PlatformFilterScope.dispatch(for:fanOutSources:)` accepts a registry-derived list; the legacy `dispatch(for:)` static is deprecated. |
| Platform-filter applies-filter partition | 5 sub-1 | `Search.PlatformFilterScope.partitionForNotice(contributingSources:appliesFilter:)` accepts a registry-derived `Set<String>`; the legacy single-arg overload forwards to the static `dispatchAppliesFilter` as default. |
| `Services.Formatter.TeaserResults` | 6 sub-1 | Gained an `extras: [String: ExtraSource]` dict alongside the 8 typed properties. New sources store teaser results keyed by id; each entry carries its own displayName + emoji. `allSources` enumerates them. |
| `Services.Formatter.Unified.Input` | 6 sub-2 | Same `extras` pattern as TeaserResults; `[String: ExtraSource]` carries source-keyed result buckets with per-entry `SourceInfo`. |
| `SearchAPI.ComposedSearchResult` | 6 sub-3 | Gained `extras: [String: ResultSection<DocAtom>]` for DocAtom-shaped sources; SampleAtom / PackageAtom sources still need typed Section properties. |
| `SearchAPI.SmartQuery` | 3 | Gained `sourceWeightsOverride: [String: Double]` init parameter; composition root supplies registry-derived fusion weights. The `weight(forSource:)` instance method consults the override first, then the static literal, then 1.0 fallback. |
| `SearchSQLite.CandidateFetcher` | 4 sub-1 + sub-2 | Gained `swiftVersionSources: Set<String>?` + `frameworkScopedSources: Set<String>?` init parameters. Composition root derives both sets from `Search.Capabilities.metadata[.hasMinSwiftVersion]` and `.hasFrameworkColumn` on each registered SourceProvider. |
| `LoggingModels.Logging.Category` | 10 | Closed enum became `struct Category: RawRepresentable`. `Logging.LiveRecording.mapCategory`'s exhaustive switch became a dict lookup with `.cli` fallback for unknown categories. |
| `Shared.Constants.SourcePrefix.allPrefixes` (production consumer) | 2 sub-1 | `Search.Index.knownSourcePrefixes` derives from `sourceLookup.allIDs + ["all"]` instead of reading the foundation-tier static. New registered sources appear in source-prefix detection automatically. |
| `Shared.Constants.Search.availableSources` (formatter consumer) | 2 sub-2 | `Services.Formatter.Footer.Search` accepts an optional `availableSources: [String]` init parameter; defaults to the foundation-tier static for back-compat. |
| `RemoteSync.Indexer` URI scheme dispatch | 11 sub-2 | Gained `phaseURIPrefixes: [IndexState.Phase: String]` init parameter; `buildURI` consults the override first, then the static default, then `phase.rawValue` as fallback. |
| MCP `DocsResourceProvider.knownURISchemes` | 12 partial | Gained `knownURISchemes: Set<String>` init parameter populated from the production source registry. The bespoke if/elseif arms still carry production probing logic (the fully registry-driven dispatch needs a `URIResourceStrategy` protocol on `SourceProvider`). |
| `Search.SourceProvider.searchRoute` | 8 sub-1 + sub-2 | New `var searchRoute: Search.SearchRoute { get }` protocol property carries each source's CLI/MCP search route (default `.docs`; `HIGSource → .hig`, `SampleCodeSource → .samples`, `PackagesSource → .packages`). The CLI + MCP dispatchers will consume this property to route registered sources; full dispatch rewire is queued as the Cluster 8 follow-up. |

## Architectural follow-ups (NOT blocking the contract)

The 26-of-26 contract assertion suite is green. Two architectural follow-ups remain queued; each completes a structural seam that already landed:

1. **Cluster 8 dispatch rewire**: the CLI `Search.run` + MCP `CompositeToolProvider.handleSearch` switches still hardcode 8-arm dispatch over source-ids. The new `Search.SourceProvider.searchRoute` property is the seam the dispatchers will consume; the follow-up extracts each bespoke runner into a per-source target method and rewires both dispatchers to iterate the registry. Estimated 3-4 hours.

2. **Cluster 12 URIResourceStrategy protocol**: `MCP.Support.DocsResourceProvider.readResource` still has 3 bespoke if/elseif arms (apple-docs, swift-evolution, apple-archive) carrying source-specific filesystem-probing logic. The new `knownURISchemes` set is the seam the registry-driven dispatch will consume; the follow-up adds a `URIResourceStrategy` protocol on `Search.SourceProvider` so each per-source target ships its own probing strategy. Estimated 2-3 hours.

Both follow-ups share the same architectural shape: extend `Search.SourceProvider` with a new method, add concrete impls to each of the 8 per-source targets, collapse the central switches. They are queued separately because they touch different surfaces (CLI dispatch vs MCP resource handling) and can ship independently.

A new source added today **does not require either follow-up to land** — the source's `searchRoute` property + `knownURISchemes` set already plug into the registry; the legacy switches' `default` arms cover unknown sources with a graceful fall-back (unified fan-out + `notFound` respectively).
| 14 | `MCP.Support.DocsResourceProvider`'s fallback filesystem dispatch (6 `hasPrefix(scheme)` arms) | 12 | +1 if/else arm OR add `SourceProvider.resourceProbing` strategy |

## How to verify the new source is wired correctly

After registering the new source:

1. **Build**: `cd Packages && xcrun swift build` (or `make build-release` for the brew-style isolated binary)
2. **Test sweep**: `cd Packages && xcrun swift test` — expect green, including the 10 already-passing pluggability contract assertions
3. **Contract test** specifically: `xcrun swift test --filter Issue1042PluggabilityContractTests` — confirms automatic surfaces include the new source. The OUTSTANDING-marked assertions stay `.disabled` until their cluster lands; the new source's id should NOT appear in `SourcePrefix.allPrefixes` (proving Cluster 2 is still outstanding for a fresh source).
4. **Setup check**: `cupertino setup` against a release bundle that ships the new source's DB. The setup post-extract hard-fail check derives the required-DB list from the production registry (Cluster 1); a new source whose DB is missing from the zip will fail loudly.
5. **MCP schema check**: `cupertino serve` then `tools/list` shows the new source in the `search` tool's `source` enum (Cluster 7).

If a step fails on a cluster that's listed under "Still required edits", that's expected — the edit at the named file is the action item. If it fails on a cluster listed under "Pluggable today", that's a regression; bisect against the cluster's PR.

## Related design docs

- `docs/plans/2026-05-22-source-independence-day.md` — original plan; 4 days older and pre-audit. Carried the initial 6-edit-points goal that #1042 refined into the 14-cluster audit. Kept as historical context.
- `docs/research/source-unification-2026-05-24.md` — research notes on the SourceProvider seam.
- `docs/research/pluggability-analysis-2026-05-22.md` — pluggability analysis that informed the contract test.
- `docs/design/per-source-db-split.md` — #1036's per-source DB split, which created the `destinationDB` field's modern semantics.
- `Packages/Tests/CLITests/Issue1042PluggabilityContractTests.swift` — the machine-checkable contract this doc tracks.

# How to add a new content source

**State**: living doc. Reflects the post-#1042 pluggability arc + the 2026-05-26 audit + 6 wiring batches (commits 1adb8bc5 → b01ca44d + Gap 3 wiring). The "What touches what" + "Step-by-step" + "Honest status" sections below are the authoritative answer. Open gaps are tracked in [#1045](https://github.com/mihaelamj/cupertino/issues/1045).

---

## Step-by-step: adding a new source (e.g. WWDC transcripts #58)

The 8 steps below are the **complete** recipe today. If a step seems missing or unnecessary, cross-reference with [#1045](https://github.com/mihaelamj/cupertino/issues/1045) — the gaps section tracks every place the contract has not yet collapsed to a smaller step count.

### Step 1: Add the source-id constant

`Packages/Sources/Shared/Constants/Shared.Constants.swift` → `SourcePrefix` enum:

```swift
public static let wwdc = "wwdc"
```

Also append to `allPrefixes` (still a foundation-tier static; Cluster 2 sub-1 routed the one production consumer to `Search.SourceLookup.allIDs`, but the literal stays for back-compat).

### Step 2: Add a `DatabaseDescriptor`

`Packages/Sources/Shared/Models/Shared.Models.DatabaseDescriptor.swift`:

```swift
public static let wwdc: DatabaseDescriptor = .init(
    id: "wwdc",
    filename: "wwdc.db",
    displayName: "WWDC Transcripts"
)
```

Append to `allKnown` immediately after declaring (the audit script enforces this).

### Step 3: Create the per-source SPM target

`Packages/Sources/WWDCSource/WWDCSource.swift` carrying the `Search.SourceProvider` conformer. Match the layout of `Packages/Sources/AppleDocsSource/` — one file per: `WWDCSource.swift` (the protocol conformer), `WWDCSource.Definition.swift` (the SourceDefinition static), `WWDCSource.FetchInfo.swift` (the FetchInfo static), `Search.WWDCStrategy.swift` (the indexing strategy), `Search.WWDCIndexer.swift` (the indexer concrete).

The conformer looks like this:

```swift
import Foundation
import SearchModels
import SharedConstants

public struct WWDCSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }
    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }
    public var destinationDB: Shared.Models.DatabaseDescriptor { .wwdc }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text],
            operations: [.readByURI],
            metadata: [.hasMinPlatformVersion: false, .hasFrameworkColumn: false]
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

    // #1042 Cluster 8 — CLI/MCP search-dispatch runner. `.docs` is the
    // safe default; pick `.hig` / `.samples` / `.packages` only if your
    // source goes through one of those bespoke handlers, else `.unified`
    // for fan-out fallback.
    public var searchRoute: Search.SearchRoute { .docs }

    // #1045 Gap 3 — how rows from this source classify in `docs_metadata.kind`.
    // For most sources this returns a constant Search.DocKind value.
    // apple-docs is the only shipped source that overrides with a
    // structured-kind classifier.
    public func docKind(structuredKind _: String?, uriPath _: String) -> Search.DocKind {
        .article  // or .symbolPage / .tutorial / .sampleCode / .evolutionProposal / .hig / .archive / etc.
    }
}
```

`SourceDefinition` carries the source's metadata (id, displayName, emoji, search properties, intents). See `Packages/Sources/AppleDocsSource/AppleDocsSource.Definition.swift` for the reference shape.

### Step 4: Wire the SPM target into `Package.swift`

Append the target name to `allSourceTargetNames` at the top of `Packages/Package.swift`:

```swift
let allSourceTargetNames: [String] = [
    "AppleDocsSource",
    "HIGSource",
    // ...
    "WWDCSource",  // ← append
]
```

Then declare the actual target later in the file (mirror the existing `<X>Source` Target.target declarations).

Cluster 14 already routed `.singleTargetLibrary` products + `SearchTests` / `SearchStrategiesTests` / `SearchModelsTests` / cupertino CLI deps through this list, so no other Package.swift edits are needed.

### Step 5: Register the source at the composition root

`Packages/Sources/CLI/CLIImpl.SourceRegistry.swift`:

```swift
public static func makeProductionSourceRegistry() -> Search.SourceRegistry {
    var registry = Search.SourceRegistry()
    registry.register(AppleDocsSource())
    // ...
    registry.register(WWDCSource())  // ← append
    return registry
}
```

Add `import WWDCSource` at the top.

### Step 6: Ship the per-source manifest

Create `docs/sources/wwdc/manifest.yaml`. Schema documented at `docs/design/corpus-structure.md` §3. Minimum:

```yaml
sourceId: wwdc
displayName: WWDC Transcripts
description: |
  Apple's WWDC session transcripts, indexed for full-text search.
corpusFolder: wwdc
destinationDB: wwdc

fetcher:
  kind: web-crawl
  options:
    rootURL: "https://developer.apple.com/wwdc/"

indexer:
  fileGlobs:
    - "wwdc/**/*.md"
  extractor: Search.WWDCStrategy

snapshotPolicy:
  staleAfterDays: 365
  refetchOn:
    - schema-bump

searchProperties:
  searchQuality: 0.7
  intentDefault: conceptual
  rankWeight: 0.7

# #1042 Cluster 8: matches WWDCSource.searchRoute
searchRoute: docs

# #1045 Gap 3: matches WWDCSource.docKind(...). Constant value or
# `dynamic` if your per-source target overrides docKind with a
# structured-kind classifier.
docKind: article

capabilities:
  searchers:
    - text
  operations:
    - read-by-uri
  metadata:
    hasMinPlatformVersion: false
```

Each `<X>Source.destinationDB` declared in Swift MUST match the manifest's `destinationDB` literal; `scripts/check-source-manifests.sh` catches drift.

### Step 7: Cover with tests

At minimum, a roundtrip test that registers `WWDCSource` in a `Search.SourceRegistry`, exercises the indexer write path (per the #935 acceptance), and verifies the URI-route read path returns the indexed row.

Look at `Packages/Tests/SearchModelsTests/Issue1008SourceProviderProtocolShapeTests.swift` for the SourceProvider shape pin, and `Packages/Tests/CLITests/Issue1039ReadHigRoundtripTests.swift` for the per-source URI roundtrip pattern (instantiate a Search.Index against `wwdc.db`, write a row via `indexDocument`, read back via `cupertino read wwdc://…`).

### Step 8: Verify the new source flows end-to-end

```bash
cd Packages
xcrun swift build                        # all targets compile
xcrun swift test                         # 2753 + new tests green
bash scripts/check-source-manifests.sh   # manifest schema valid
bash scripts/check-package-purity.sh     # import contract holds
```

Then a smoke run against a real corpus directory:

```bash
cupertino fetch --source wwdc            # crawl
cupertino save --source wwdc             # index
cupertino search "WWDC keynote" --source wwdc
cupertino serve                          # MCP server picks up new source
```

---

## What touches what — the registry-aware contract

| Concern | What you write | Where it propagates automatically |
|---|---|---|
| Source identity | `WWDCSource.definition` static literal | Setup required-list (#1042 Cluster 1), MCP search-tool schema (#1042 Cluster 7), CLI footer tips (audit batch 4), `readFullCommand` validation (audit batch 4) |
| Destination DB | `WWDCSource.destinationDB` | Setup post-extract hard-fail (#1042 Cluster 1), SmartReport docs-tier filter (audit batch 3), per-source DB grouping (`Search.SourceRegistry.groupedByDestinationDB`) |
| Capabilities | `WWDCSource.capabilities.metadata` | CandidateFetcher's `swiftVersionSources` + `frameworkScopedSources` (audit batch 1; derives from `.hasMinSwiftVersion` + `.hasFrameworkColumn`), SmartReport's `unfilteredSourcesUnderPlatformFlag` (audit batch 3, same source-of-truth) |
| URI scheme | `definition.id` (= URI scheme) | MCP DocsResourceProvider's `knownURISchemes` (audit batch 1), RemoteSync's `phaseURIPrefixes` (audit batch 1) |
| Search dispatch | `searchRoute` property | Cluster 8 structural seam (full dispatch rewire is the queued follow-up; today the CLI/MCP switches still use legacy `default:` arms with safe fall-back) |
| Document classification | `docKind(structuredKind:uriPath:)` | `Search.Classify.kind` dispatches via `sourceLookup.provider(for:)?.docKind(...)` (Gap 3 wiring); fall back to legacy switch when no lookup |
| Fan-out display | `definition.id` | `Services.Formatter.Unified.Input.availableSources` end-to-end via `Services.UnifiedSearcher` protocol + the MCP composition (audit batch 2); CLI SmartReport footer (audit batch 4); SearchByAttribute's `knownSourcePrefixes` (Cluster 2 sub-1) |

---

## Honest status — what's still hardcoded today (open in [#1045](https://github.com/mihaelamj/cupertino/issues/1045))

A 2026-05-26 audit of post-#1042 production code found that the "26/26 contract assertions green" headline was misleading: 6 of 7 override parameters declared on the contract were never supplied at production call sites. Six wiring batches landed afterwards (CHANGELOG entries from 2026-05-26 are the audit-trail). 

**Still open** (each is an acceptance criterion in #1045):

1. **`Search.SmartQuery.sourceWeightsOverride` never wired at production**: the RRF fusion-weight literal at `SearchAPI/SmartQuery.swift:60-70` is the live source of truth. A new source's weight falls back to 1.0 (the `?? 1.0` arm). Fix: add `Search.SourceProperties.fusionWeight: Double` field on the protocol; each shipped source declares its current weight; SmartQuery composition root supplies `[String: Double]` to the override parameter. Preserves existing tuned weights when each shipped source declares the matching number.

2. **13 `Footer.Search.singleSource` call sites in HIG / Samples / Frameworks / single-source formatters still pass `availableSources: nil`**: the factory-level seam landed (audit batch 5), but each call site lives inside another formatter whose Input type doesn't yet carry the list. Fix: thread `availableSources: [String]?` through each formatter's Input type; CLI/MCP entrypoints populate from the registry.

3. **`CLIImpl.Command.Save.Indexers.resolveSourceDirectory(for:input:)` 7-arm switch** maps `provider.definition.id` to 5 typed `*Directory: URL?` fields on `Search.DocsIndexingInput`. Adding a new source needs both a new input field and a new switch arm. Fix: replace typed fields with `directoryByKey: [String: URL?]`; the switch collapses to a dict lookup. Samples + swiftBook keep their sentinel paths as explicit nil/`/dev/null` entries.

**Naming asymmetry to remember**: `SampleCodeSource.destinationDB == .appleSampleCode` (legacy descriptor, not `.samples`), and `PackagesSource.destinationDB == .packages` (not `.swiftPackages` — the rename target). Consumer code that needs to identify "search.db-family sources" MUST exclude both `.appleSampleCode` AND `.packages` to skip the two non-search-tier destinations. The pre-#1042 audit-batch-3 commit went green on the second attempt because of this trap; documented at `Shared.Models.DatabaseDescriptor.appleSampleCode`.

---

## Architectural follow-ups (NOT blocking adding a new source)

These complete structural seams that already landed; a new source today does not need them.

1. **Cluster 8 dispatch rewire**: CLI `Search.run` + MCP `CompositeToolProvider.handleSearch` switches still hardcode 8-arm dispatch over source-ids. The new `Search.SourceProvider.searchRoute` is the seam they'll consume; the follow-up extracts each bespoke runner into a per-source target method. Estimated 3-4 hours.

2. **Cluster 12 URIResourceStrategy protocol**: `MCP.Support.DocsResourceProvider.readResource` has 3 bespoke if/elseif arms (apple-docs / swift-evolution / apple-archive) with source-specific filesystem-probing logic. The new `knownURISchemes` set is the seam; follow-up adds a `URIResourceStrategy` protocol on `Search.SourceProvider`. Estimated 2-3 hours.

A new source added today works without either follow-up: the legacy switches' `default:` arms cover unknown sources with graceful fall-back (unified fan-out + `notFound` respectively).

---

## How to verify the new source is wired correctly

After completing Steps 1-7:

```bash
cd Packages
xcrun swift build                                              # all targets compile
xcrun swift test                                                # 2753 + new tests green
xcrun swift test --filter Issue1042PluggabilityContractTests   # 26/26 still pass
bash scripts/check-source-manifests.sh                          # manifest schema valid
bash scripts/check-package-purity.sh                            # import contract holds
```

Smoke-test against a real corpus:

```bash
cupertino fetch --source wwdc                                   # crawl
cupertino save --source wwdc                                    # index
cupertino search "WWDC keynote" --source wwdc                   # source-scoped search
cupertino search "WWDC keynote"                                 # unified fan-out includes wwdc
cupertino serve                                                 # MCP server picks up the new source-id in tools/list's schema enum
```

If a smoke step fails on a gap listed in [#1045](https://github.com/mihaelamj/cupertino/issues/1045), that's expected — the named acceptance criterion is the action item. If it fails on a row in the "What touches what" table, that's a regression; bisect against the corresponding commit.

---

## Related design docs

- [#1045](https://github.com/mihaelamj/cupertino/issues/1045) — pluggability audit + 4 production wiring gaps (acceptance-checklisted)
- `docs/plans/2026-05-22-source-independence-day.md` — original plan; 4 days older and pre-audit. Kept as historical context.
- `docs/research/source-unification-2026-05-24.md` — research notes on the SourceProvider seam
- `docs/research/pluggability-analysis-2026-05-22.md` — pluggability analysis that informed the contract test
- `docs/design/per-source-db-split.md` — #1036's per-source DB split, which created the `destinationDB` field's modern semantics
- `docs/design/corpus-structure.md` — manifest YAML schema (§3) + corpus on-disk layout (§2)
- `Packages/Tests/CLITests/Issue1042PluggabilityContractTests.swift` — the machine-checkable structural contract. Top-of-file comment names the structural-vs-behavioural distinction explicitly.

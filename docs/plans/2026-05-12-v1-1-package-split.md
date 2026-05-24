# Cupertino Refactor Plan (v1.2)

Status: **Closed 2026-05-24** by #907 (full closing audit + epic #893 close). Earlier: superseded, 2026-05-22 (v3 refresh). The original 2026-05-12 plan organised package splitting around v1.2.0 ship cadence; that ship landed on 2026-05-20 with a partially-different shape than this plan called for, and the strict-DI / standalone-portability principle layer (`mihaela-agents/Rules/swift/gof-di-rules.md`) consolidated in the intervening period now drives the refactor's end-state more than the modularity-for-compile-speed framing this doc started with. Epic #893 closed 2026-05-24 with all 13 child issues #895-#907 shipped; the v3 refresh at §0a below records the final direction (the strict-DI shape, not the original modularity framing). Closing audit at `docs/audits/epic-893-closing-audit-2026-05-24.md`. The body below (§0-§12) is preserved as historical reference, with per-phase status markers inline.

## 0a. v3 refresh (2026-05-22, current direction)

Companion documents:
- `docs/research/pluggability-analysis-2026-05-22.md`: measured analysis of where cupertino sits against the strict-DI canon + the secret-life reference implementation, and the topology the refactor targets.
- Epic [#893](https://github.com/mihaelamj/cupertino/issues/893): the canonical sequencing record for the producer-backend split (the v3 refactor). 13 child issues #895-#907 enumerate the per-arc PRs.
- `mihaela-agents/Rules/swift/gof-di-rules.md` rules 5 + 8: the principle layer (every package lifts out; producer foundation-only target regime).
- `mihaela-analytics/secret-life/Docs/protocol-seam-audit.md`: the reference implementation (4 protocol seams + 27 importer concretes + a 2026-05-20 lift-out trace).

### What the v3 refresh changes vs the 2026-05-12 plan

The original plan's value proposition was modularity for compile-speed and review surface (no package > 2,500 LOC, no file > 800 LOC). The v3 refresh keeps those wins where they overlap with the strict-DI shape, and **extends** the plan with one new axis: every producer's concrete backend (`SQLite3`, `WebKit`, `FoundationNetworking`) lifts to a sibling SPM target conforming a protocol seam declared in the producer's `*Models` companion. After the refresh, the end-state is mechanically pluggable: `scripts/check-target-portability.sh <Producer>` passes for every producer with only its `*Models` + `SharedConstants` declared, and `grep '^import SQLite3' Packages/Sources/<Target>/` is empty for every non-`*SQLite` target.

The plan's per-phase status as of 2026-05-22:

| Phase | Original scope | Today's status |
|---|---|---|
| **Phase 1** (Shared dissection) | 6 sub-targets: `SharedCore`, `SharedConstants`, `SharedUtils`, `SharedModels`, `SharedConfiguration`, `MCPSharedTools` | **DONE in a different shape per #536.** 4 of the 6 (`SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration`) were absorbed into `SharedConstants` rather than kept as separate sub-targets. Only `SharedConstants` + `MCPSharedTools` exist as distinct targets today. |
| **Phase 2** (Core dissection) | 8 sub-targets: `CoreProtocols`, `CoreHTMLParser`, `CoreJSONParser`, `CorePackageIndexing`, `CoreSampleCode`, `CoreArchive`, `CoreSpecializedCrawlers`, `CoreCrawler` | **PARTIAL: 4 of 8 done.** `CoreProtocols`, `CoreJSONParser`, `CorePackageIndexing`, `CoreSampleCode` exist. `CoreHTMLParser` (extract `Core/HTMLParser/`), `CoreArchive`, `CoreSpecializedCrawlers`, and the `CoreCrawler` rename are not done. Carried forward; see the "Phase 2 carry-over" sub-section at the end of §0a for sequencing. |
| **Phase 3** (Search dissection) | 8 sub-targets: `SearchSchema`, `SearchUtilities`, `SearchIntent`, `SearchRanking`, `SearchIndexCore`, `SearchStrategies`, `SearchQuery`, `SearchAPI` | **DONE in the v3 Option D shape (Closed 2026-05-24 by #907).** 10 Search-side targets shipped: `SearchAPI` (orchestrator, post-#900 rename of `Search`), `SearchSQLite` (sole SQLite3-importing concrete), `SearchSchema`, `SearchStrategyHelpers`, 6 `<X>Strategy` targets. The original 8 sub-target names mapped as: `SearchSchema` shipped as-named (#898 sub-PR A); `SearchUtilities`/`SearchIntent`/`SearchRanking` (sub-PRs B/C/D) shipped as zero, material folded into `SearchModels` (QueryIntent + detectQueryIntent + SourceProperties + SourceDefinition) and `SearchSQLite` (BM25 + ranking path + query parsing); `SearchIndexCore` shipped as `SearchSQLite` (#898 sub-PR E); `SearchStrategies` shipped split into 6 per-strategy targets + `SearchStrategyHelpers` (#899); `SearchQuery` deferred (sub-PR A of #900 not executed; `Search.Database` protocol seam already operates through `SearchModels`); `SearchAPI` shipped as the rename target (#900 sub-PR B in PR #997). Lift-out evidence in `docs/handoff/search-arc-liftout-2026-05-24.md`. |
| **Phase 4** (Cleanup) | 8 small PRs (force-unwrap fixes, EmptyParams dedupe, etc.) | **PARTIAL.** Track per-PR; not the v3 refresh's focus. |
| **Phase 5** (SampleIndex dissection) | 4 sub-targets: `SampleIndexSchema`, `SampleIndexCore`, `SampleIndexQuery`, `SampleIndexAPI` | **DONE in the v3 Option D shape (Closed 2026-05-24 by #907).** Mirror of the Search arc at smaller scale. End-state: `SampleIndex` (orchestration) + `SampleIndexModels` (protocol seam) + `SampleIndexSQLite` (sole SQLite3-importing concrete). The original 4-target split was condensed: schema constants live in `SampleIndexSQLite/Sample.Index.Database.swift` (no separate `SampleIndexSchema`), query/core/api collapsed into the single `SampleIndex` orchestration target. #902 shipped. |
| **(new) Phase 7** (welded-backend producers) | not in original plan | **0 done.** Five additional producers carry welded backends the original plan did not address: `Crawler/WebKit`, `Core/WebKit`, `CoreJSONParser/WebKit`, `CoreSampleCode/WebKit`, `Availability/FoundationNetworking`. Each gets a `*WebKit` / `*FoundationNetworking` sibling concrete + a protocol seam in the producer's `*Models`. Detail: epic #893 children #903-#905; analysis doc §7.4-§7.6. |

### v3 end-state target topology

After the v3 refresh lands, cupertino has roughly 35-42 producer SPM targets (vs 30 today, post-#908). The shape is:

- **Foundation tier** (allowed to every producer): `SharedConstants`, `LoggingModels`, `Resources`, `Diagnostics`, `ASTIndexer`, `MCPCore`, `MCPSharedTools`. Source of truth: `scripts/check-target-foundation-only.sh` `FOUNDATION_TIER` array.
- **`*Models` protocol seams** (foundation-only, allowed to every producer): 12 today (`CoreProtocols`, `CrawlerModels`, `CorePackageIndexingModels`, `SearchModels`, `SampleIndexModels`, `ServicesModels`, `IndexerModels`, `DistributionModels`, `CleanupModels`, `CoreSampleCodeModels`, `RemoteSyncModels`, `EnrichmentModels`); v3 extends each `*Models` with write-side protocols where its producer has welded backends today.
- **Per-strategy concrete targets** (the secret-life pattern, one concrete per SPM target): 7 source-indexing strategies inside Search → 7 targets, 6 enrichment passes → 6 targets, plus the `*SQLite` and `*WebKit` concrete siblings.
- **Composition root** (`CLI`): grows to wire every new `Live*Factory`. Per `gof-di-rules.md` §6 this is expected, not a problem.

### v3 sequencing (mirror of epic #893's child issues)

1. **#895**: Pre-flight hygiene. Parts A + B shipped via PR #908 (the `EnrichmentModels` allow-list catchup + `docs/package-import-contract.md` refresh). Part C is this very plan refresh, landing as a docs-only PR.
2. **#896**: `SearchModels` write-side protocols + `Search.Index` witness conformances. Zero file moves; zero SQLite migration; protocol fronting only.
3. **#897**: Rewire `Search.IndexBuilder` + 7 strategies to take `any Search.IndexWriter` via init.
4. **#898**: Search target dissection (`SearchSchema`, `SearchUtilities`, `SearchIntent`, `SearchRanking`, `SearchSQLite` extract). 5 sub-PRs; the final one is the SQLite move.
5. **#899**: 7 source-indexing strategies → 7 SPM targets.
6. **#900**: `SearchQuery` extraction + `SearchAPI` rename of the residue.
7. **#901**: Search arc lift-out traces (verification PRs).
8. **#902**: SampleIndex arc (write-side protocols → `SampleIndexSQLite` → lift-out).
9. **#903**: Crawler arc (`HTTPFetching` protocol → `CrawlerWebKit` → lift-out).
10. **#904**: Core / CoreJSONParser / CoreSampleCode WebKit extraction (or shared `WebFetcher` producer-tier concrete behind a `WebFetcherModels` foundation-only seam; decision pinned in #904's PR body).
11. **#905**: Availability arc (`Networking` protocol → `AvailabilityFoundationNetworking` → lift-out).
12. **#906**: Enrichment per-pass split (6 passes → 6 SPM targets).
13. **#907**: Closing: full audit, plan-doc finalisation, epic close.

#909 tracks a separate set of pre-existing audit-script consistency gaps (Logging missing from FORBIDDEN_MODULES, Diagnostics dual classification, MCPClient unaudited, etc.) that surfaced during PR #908's critic-review and are out-of-scope for the strict pluggability arc.

### Phase 2 carry-over

The 4 undone Phase-2 items (`CoreHTMLParser`, `CoreArchive`, `CoreSpecializedCrawlers`, `CoreCrawler` rename) are not strictly required by the v3 producer-backend split. They remain on the plan but get lower priority than the Search / SampleIndex / welded-backend arcs above. Re-evaluate after epic #893 closes.

---

## 0. Why

`Packages/Sources/` currently holds three packages that exceed 3,000 LOC each and concentrate the project's worst single-file gods:

| Package | LOC | Files | Public types | Worst file |
|---|---:|---:|---:|---|
| `Core` | 11,788 | 41 | 95 | `HTMLToMarkdown.swift` (1,070) |
| `Search` | 10,338 | 25 | 68 | `SearchIndexBuilder.swift` (1,343) |
| `Shared` | 3,730 | 13 | 76 | `Constants.swift` (1,549) |

Together they hold ~62 % of production LOC. Three layering oddities sit on top:

1. **`Shared → MCP`** (`Package.swift:96`). `ArgumentExtractor.swift` re-exports `AnyCodable` and drags MCP into every consumer.
2. **`MCPSupport`/`SearchToolProvider → Search`**. Welded to a concrete index, no abstraction.
3. **`Logging → Shared`**. Forces `Shared/Constants.swift` (1,549 LOC) into every translation unit.

No cycles exist. The graph is a valid DAG. The split below preserves that.

---

## 1. Workflow

- All work lands on `develop`. `main` remains the v1.0.x release branch.
- Each numbered task below is one feature branch off `develop` and one PR back into `develop`.
- Branch naming: `refactor/<phase>.<task>-<slug>`. Example: `refactor/1.1-mcp-shared-tools-extract`.
- PR title format: `refactor(<scope>): <summary> (#<refactor-task-number>)`. Scope is the resulting package name when possible.
- Squash-merge into `develop`. Auto-delete the feature branch.
- When the full plan is green on `develop`, open a single PR `develop → main` titled `release(v1.2.0): package split`.
- **Schema is frozen.** No DB column or table changes. `databaseVersion` stays at `1.0.2`. No bundle reindex required.

### Verification recipe (every PR)

Each PR must pass:

```
swiftformat . --config .swiftformat
swiftlint --config .swiftlint.yml
swift build
swift test
swift run cupertino --help
```

The `swift test` step runs the **whole** test matrix, not just the touched package, because every package extraction can ripple through downstream imports. PRs that touch ranking, indexing, or schema additionally run one manual sanity query against a v1.0.2 bundle and paste the result into the PR body.

### Out of scope

- `TUI` package (project convention: views are not touched without explicit request).
- `Resources/Embedded/SwiftPackagesCatalogEmbedded.swift` (generated, 9,717 LOC).
- Database schema and `databaseVersion`. Any task that would require a bundle reindex is deferred.
- New features. This branch contains only file moves, type extractions, and the small targeted cleanups in Phase 4.

---

## 2. Target architecture

End state has ~31 packages (from 23 today). Topological order, foundation first:

```
Foundation:
  MCP            (unchanged)
  SharedCore     (← extracted from Shared: namespace + ToolError only, ~200 LOC)
  SharedConstants (← extracted from Shared, ~1,100 LOC)
  SharedUtils    (← extracted from Shared: JSONCoding + PathResolver + Formatting + FTSQuery + BinaryConfig + SchemaVersion, ~330 LOC)
  SharedModels   (← extracted from Shared/Models.swift, ~500 LOC)
  SharedConfiguration (← extracted from Shared/Configuration.swift, ~244 LOC)
  Logging        (now depends on SharedCore + SharedConstants only)
  Resources      (unchanged)
  Availability   (unchanged)
  Diagnostics    (unchanged)
  MCPSharedTools (← new: ArgumentExtractor + MCP-only constants, ~150 LOC)

Infrastructure:
  ASTIndexer                  (unchanged target, narrower deps)
  CoreProtocols               (← extracted from Core: ContentFetcher/Transformer/CrawlerEngine + GitHubCanonicalizer + ExclusionList + SwiftPackagesCatalog, ~400 LOC)
  CoreHTMLParser              (← extracted: HTMLToMarkdown + XMLTransformer, ~1,300 LOC)
  CoreJSONParser              (← extracted: AppleJSONToMarkdown + MarkdownToStructuredPage + RefResolver + RefResolverFetchers + JSON engine, ~1,500 LOC)
  CorePackageIndexing         (← extracted: Resolver + Fetcher + Extractor + Annotator + Store + FileKind + ManifestCache + DocDownloader, ~2,400 LOC)
  CoreSampleCode              (← extracted: SampleCodeDownloader + GitHubSampleCodeFetcher + Catalog + PriorityPackageGenerator + PriorityPackagesCatalog, ~1,600 LOC)
  CoreArchive                 (← extracted: AppleArchiveCrawler + ArchiveGuideCatalog, ~1,100 LOC)
  CoreSpecializedCrawlers     (← extracted: HIGCrawler + EvolutionCrawler, ~1,000 LOC)
  CoreCrawler                 (renamed Core: Crawler + State + WKWebFetcher + WKWebEngine + TechnologiesIndex, ~1,600 LOC)

  SearchSchema                (← extracted: schema DDL + migrations, ~500 LOC)
  SearchUtilities             (← extracted: Helpers + QueryParsing + CountsAndAliases + DocKind + SourceDefinition + SearchResult + CandidateFetcher, ~1,200 LOC)
  SearchIntent                (← extracted: QueryIntent + detectQueryIntent + SourceProperties, ~300 LOC)
  SearchRanking               (← carved from SearchIndex+Search: BM25 + heuristics + symbol boost, ~300 LOC)
  SearchIndexCore             (← extracted: low-level FTS writes + symbol indexing, ~800 LOC)
  SearchStrategies            (← refactored: 7 source strategies behind SourceIndexingStrategy protocol, ~1,200 LOC)
  SearchQuery                 (← extracted: slimmed search() + searchByAttribute + searchSymbols + searchCodeExamples + searchPackages, ~1,000 LOC)
  SearchAPI                   (renamed Search: SearchIndex actor + SmartQuery + ComposableResult atoms/sections, ~700 LOC)

  Cleanup                     (unchanged)
  SampleIndexSchema           (← extracted from SampleIndex: DDL + migrations, ~250 LOC)
  SampleIndexCore             (← extracted from SampleIndex: CRUD writes, ~400 LOC)
  SampleIndexQuery            (← extracted from SampleIndex: search + filter + availability annotation, ~400 LOC)
  SampleIndexAPI              (renamed SampleIndex: actor lifecycle + public surface, ~150 LOC)

Operations / MCP / Apps:
  Services, Indexer, Ingest, Distribution, MCPClient, MCPSupport,
  SearchToolProvider, RemoteSync, CLI, TUI, MockAIAgent, ReleaseTool
                              (deps updated to point at the new package layout)
```

**Invariants enforced after the refactor:**

- No `Shared → MCP` edge.
- No file > 800 LOC in non-generated production sources, except the rewritten `SearchQuery.swift`'s `search(...)` which targets ≤ 500 LOC after carving.
- No package > 2,500 LOC, except generated `Resources` (untouched).
- No public type that has < 2 external callers (audited at the end of Phase 4).

---

## 3. Phase 1: Shared dissection (6 PRs)

> **Status: DONE in a different shape per #536 (2026-05-14).** Original plan called for 6 sub-targets; #536 absorbed `SharedCore` / `SharedUtils` / `SharedModels` / `SharedConfiguration` into `SharedConstants` instead. Only `SharedConstants` + `MCPSharedTools` exist as distinct targets today. The per-PR detail below is preserved as the historical record; do not re-execute. See §0a above for current direction.

`Shared` is the dependency hub: 15+ packages import it. Splitting it first means every downstream extraction in Phases 2 and 3 imports a smaller, more targeted surface. Each PR keeps the public API source-compatible by re-exporting moved types from the originating module, then a final pass removes the re-exports.

### 1.1 — Extract `MCPSharedTools`

**Why first**: kills Violation #1 (`Shared → MCP`).

**Scope discovery before cut**. The full audit of `Constants.Search` (404 LOC, lines 602-1005 of `Shared/Constants.swift`) revealed two cross-references that constrain the split:

- `tipPlatformFilters` (line 960) and `tipSemanticSearch` (line 989) are used by `Services` formatters and are themselves *string-interpolated* over the `schemaParam*` and `tool*` identity names. Moving those identities into `MCPSharedTools` would break the interpolations or force `Services` to take a new MCP-adjacent dep.

The cut therefore moves only **MCP-protocol output strings**, not the search-domain identities:

**Files / slices moved**:
- `Packages/Sources/Shared/ArgumentExtractor.swift` → `Packages/Sources/MCPSharedTools/ArgumentExtractor.swift`
- New `Packages/Sources/MCPSharedTools/MCPCopy.swift` containing only:
  - Tool **descriptions** (10 long help strings: `toolSearchDescription`, `toolListFrameworksDescription`, `toolReadDocumentDescription`, `toolListSamplesDescription`, `toolReadSampleDescription`, `toolReadSampleFileDescription`, `toolSearchSymbolsDescription`, `toolSearchPropertyWrappersDescription`, `toolSearchConcurrencyDescription`, `toolSearchConformancesDescription`). Lines 692-834.
  - Resource template URIs: `templateAppleDocs`, `templateSwiftEvolution`. Lines 653-659.
  - Resource descriptions: `appleDocsDescriptionPrefix`, `swiftEvolutionDescription`, `appleDocsTemplateName`, `appleDocsTemplateDescription`, `swiftEvolutionTemplateDescription`. Lines 661-677.
  - `mimeTypeMarkdown`. Line 682.

**Stays in `Shared.Constants.Search`** (and follows the package to `SharedConstants` in 1.3):
- URI schemes (`appleDocsScheme`, `appleArchiveScheme`, `swiftEvolutionScheme`, `higScheme`)
- Tool/command **names** (`toolSearch`, `toolListFrameworks`, `toolReadDocument`, `toolListSamples`, `toolReadSample`, `toolReadSampleFile`, `toolSearchSymbols`, `toolSearchPropertyWrappers`, `toolSearchConcurrency`, `toolSearchConformances`)
- All `schemaParam*` and `schemaTypeObject` (used by the tips above, and read by ArgumentExtractor's defaults via `Shared.Constants.Search.*`)
- `formatValueJSON`, `formatValueMarkdown`
- Swift Evolution `sePrefix` / `stPrefix`
- All tips, messages, `availableSources`, `otherSources(excluding:)`, `formatScore`

**Package.swift changes**:
- Add `MCPSharedTools` target with provisional deps `["MCP", "Shared"]` (tightens to `["MCP", "SharedCore"]` in 1.6).
- Add `MCPSharedTools` product.
- Remove `MCP` from `Shared` target deps. This is the line that kills Violation #1.
- Add `MCPSharedToolsTests` target depending on `["MCPSharedTools", "Shared", "TestSupport"]`.

**Public surface**:
- `public struct MCPSharedTools.ArgumentExtractor` (identical API to today's `Shared.ArgumentExtractor`).
- `public enum MCPSharedTools.MCPCopy` namespace holding the moved sub-set above.
- Nothing removed from `Shared`'s public API beyond what moved. The shared identities and tips keep their paths.

**Tests**: new `Packages/Tests/MCPSharedToolsTests/ArgumentExtractorTests.swift` covers `require*`, `optional*`, defaults, and `limit` clamping. `ArgumentExtractor` had no dedicated test file in `SharedTests`; this PR adds one.

**Import sweep**: ~25 call sites, not the ~125 implied by the original block-level split. Affected packages:
- `MCPSupport/DocsResourceProvider.swift`: `mimeTypeMarkdown` (8 refs) and any resource template / description refs → `MCPSharedTools.MCPCopy.*`.
- `SearchToolProvider/CompositeToolProvider.swift` and adjacent: tool description refs → `MCPSharedTools.MCPCopy.*`; `ArgumentExtractor` import path updates.
- `MockAIAgent`: zero changes (only uses `appleDocsScheme`, which stays).
- `Services` and `CLI`: zero changes (their refs are to identity constants and tips, all of which stay).

**Risk**: medium. The MCP-side import sweep is mechanical but touches the tool-registration call sites that matter for `cupertino mcp serve`. Verification must include a live MCP smoke test, not just `swift build`.

**Verification**: standard recipe (`swiftformat`, `swiftlint`, `swift build`, `swift test`, `swift run cupertino --help`) plus `rg "Shared\.Constants\.Search\.(toolSearchDescription|tool.*Description|templateAppleDocs|templateSwiftEvolution|appleDocsTemplateName|appleDocsDescriptionPrefix|swiftEvolutionDescription|appleDocsTemplateDescription|swiftEvolutionTemplateDescription|mimeTypeMarkdown)\b"` expected to return zero hits.

### 1.2 — In-file split of `Shared/Models.swift`

**Why before package split**: `Models.swift` at 1,218 LOC is unreviewable. Split into per-domain files within the same target first; the package extraction in 1.5 is then a folder move, not a code surgery.

**File map** (all inside `Packages/Sources/Shared/`):
- `Models.swift` (deleted)
- New `Models/Page.swift` ← `StructuredDocumentationPage`, `DocumentationPage`, `Kind`, `Source`, `Declaration`, `Section`, `Section.Item`, `CodeExample`
- New `Models/Crawl.swift` ← `CrawlMetadata`, `CrawlStatistics`, `FrameworkStats`, `PageMetadata`, `CrawlSessionState`, `QueuedURL`
- New `Models/SwiftPackage.swift` ← `PackageReference`, `PackagePriority`, `DocumentationSite`, `PackageDownloadProgress`, `PackageDownloadStatistics` (named `SwiftPackage` so the filename does not collide with the SwiftPM manifest `Package.swift`)
- New `Models/Sample.swift` ← `CleanupProgress`, `CleanupStatistics`, `CleanupResult`
- New `Models/URLUtilities.swift` ← `URLUtilities` (the 170-LOC enum, including the `filename(_:)` from #283)
- New `Models/HashUtilities.swift` ← `HashUtilities`

**Public API impact**: none. All types remain `Shared.*`.

**Risk**: low (mechanical).

**Verification**: standard recipe. Diff the public API output of `swift package generate-documentation` or just `swift symbolgraph-extract` if available; expect zero deltas.

### 1.3 — Extract `SharedConstants`

**Why**: `Constants.swift` is 1,374 LOC after 1.1 stripped out the MCP text. Foundation-layer-appropriate constants only.

**Files moved** (revised vs the original plan after a dependency-direction audit during implementation):
- `Packages/Sources/Shared/Constants.swift` → `Packages/Sources/SharedConstants/Constants.swift`
- `Packages/Sources/Shared/Shared.swift` → `Packages/Sources/SharedConstants/Shared.swift` (the `public enum Shared` namespace itself; `Constants` is declared as `extension Shared`, so the namespace owner has to live in the same target as the extension to avoid a cycle)
- `Packages/Sources/Shared/BinaryConfig.swift` → `Packages/Sources/SharedConstants/BinaryConfig.swift` (carried because `Constants.Directory.defaultBaseDirectory` calls `Shared.BinaryConfig.shared` at runtime; co-locating is the only way to keep `SharedConstants` self-contained)

**Files added**:
- `Packages/Sources/Shared/Exports.swift` — single line `@_exported import SharedConstants` so callers that `import Shared` continue to see `Shared.Constants.*` and the `Shared` namespace itself with no source change. Removed in task 1.6 alongside the `Shared` → `SharedCore` rename.

**Package.swift changes**:
- Add `SharedConstants` target with no internal deps.
- Add `SharedConstants` product.
- `Shared` target gains `SharedConstants` as a dep so the re-export resolves.

**Public API impact**: none. Every `Shared.Constants.X`, `Shared.BinaryConfig.X`, and `Shared` namespace reference resolves through the `@_exported import` re-export.

**Risk**: low. Re-export is transparent; the only catch is that `swift test` needs a clean rebuild after this PR lands because cached test object files reference symbols at the old module path. CI usually does this; locally run `xcrun swift package clean && xcrun swift test` once after merge.

**Plan §1.4 follow-up**: `BinaryConfig.swift` is removed from the list of files moving to `SharedUtils`, since it has already moved here. `SharedUtils` (1.4) now contains only `JSONCoding.swift`, `PathResolver.swift`, `Formatting.swift`, `FTSQuery.swift`, `SchemaVersion.swift`.

### 1.4 — Extract `SharedUtils`

**Files moved** (BinaryConfig.swift removed from this list; moved to `SharedConstants` in 1.3 because of the runtime call from `Constants.Directory.defaultBaseDirectory`):
- `Packages/Sources/Shared/JSONCoding.swift` → `Packages/Sources/SharedUtils/JSONCoding.swift`
- `Packages/Sources/Shared/PathResolver.swift` → `Packages/Sources/SharedUtils/PathResolver.swift`
- `Packages/Sources/Shared/Formatting.swift` → `Packages/Sources/SharedUtils/Formatting.swift`
- `Packages/Sources/Shared/FTSQuery.swift` → `Packages/Sources/SharedUtils/FTSQuery.swift`
- `Packages/Sources/Shared/SchemaVersion.swift` → `Packages/Sources/SharedUtils/SchemaVersion.swift`

**Also carried during 1.4** (not in the original plan): the `URL` extensions (`expandingTildeInPath`, `knownGood`) move from `Shared/CupertinoShared.swift` to a new `SharedUtils/URLExtensions.swift`, because `PathResolver` reaches into `URL.expandingTildeInPath` and the alternative is a `SharedUtils → Shared` dep that cycles with `Shared → SharedUtils`. `Shared/CupertinoShared.swift` retains its `@_exported` of Foundation and CryptoKit and a pointer comment to the new location.

**Files added**:
- `Packages/Sources/SharedUtils/URLExtensions.swift` (the moved `URL` extension)
- One-line addition in `Packages/Sources/Shared/Exports.swift`: `@_exported import SharedUtils` so callers that `import Shared` see the moved types with no source change.

**Package.swift**: add `SharedUtils` target + product, depends on `SharedConstants` only. `Shared` target deps gain `"SharedUtils"`.

**Risk**: low. Source-compatible via the re-export.

### 1.5 — Extract `SharedModels`

Builds on 1.2.

**Files moved**: the `Packages/Sources/Shared/Models/` folder created in 1.2 → `Packages/Sources/SharedModels/`.

**Package.swift**: add `SharedModels` target + product, deps `["SharedConstants", "SharedUtils"]` (URLUtilities uses `Constants.Pattern`).

**Import updates**: every consumer of `StructuredDocumentationPage`, `CrawlMetadata`, `URLUtilities`, etc. switches from `import Shared` to `import SharedModels` (or adds it alongside).

**Risk**: high — `StructuredDocumentationPage` has 97 callers across the repo. The change is mechanical (`import` line additions) but touches many files. PR is read by inspection of the diff stats not the diff content.

### 1.6 — Extract `SharedConfiguration` and shrink `Shared` to `SharedCore`

**Files moved**:
- `Packages/Sources/Shared/Configuration.swift` → `Packages/Sources/SharedConfiguration/Configuration.swift`

**File renames in remaining Shared**:
- `Packages/Sources/Shared/CupertinoShared.swift` → `Packages/Sources/SharedCore/CupertinoShared.swift`
- `Packages/Sources/Shared/Shared.swift` → `Packages/Sources/SharedCore/Shared.swift`
- `Packages/Sources/Shared/ToolError.swift` → `Packages/Sources/SharedCore/ToolError.swift`

**Package.swift**:
- Rename `Shared` target → `SharedCore`.
- Add `SharedConfiguration` target deps `["SharedCore", "SharedConstants"]`.
- Remove re-exports from `Shared` (the legacy umbrella). Add migration alias `enum Shared { /* typealiases */ }` for one release if needed; remove in Phase 4.8.
- Update `MCPSharedTools` from `["MCP", "Shared"]` to `["MCP", "SharedCore"]`.

**Import sweep**: every `import Shared` becomes some combination of `import SharedCore`, `import SharedConstants`, `import SharedUtils`, `import SharedModels`, `import SharedConfiguration`. This is the largest mechanical diff in Phase 1.

**Risk**: high. End-of-phase smoke test runs the full app: `cupertino --help`, `cupertino doctor`, one `cupertino search` query against a v1.0.2 bundle. Pasted into PR body.

---

## 4. Phase 2: Core dissection (8 PRs)

> **Status: PARTIAL (4 of 8 done).** `CoreProtocols`, `CoreJSONParser`, `CorePackageIndexing`, `CoreSampleCode` exist as distinct SPM targets. The remaining 4 (`CoreHTMLParser`, `CoreArchive`, `CoreSpecializedCrawlers`, the `CoreCrawler` rename) are carried forward at lower priority than the v3 producer-backend arc; re-evaluate after epic #893 closes. See §0a above.

`Core` is split by source-kind boundaries already implicit in the file layout. Each extraction is followed by an import sweep across `Search`, `Indexer`, `Ingest`, `CLI`.

Throughout this phase, `Core` continues to exist as an umbrella that re-exports each extracted submodule until 2.8 renames the residue to `CoreCrawler`. That keeps Phase 1 import-sweep work from compounding here.

### 2.1 — Extract `CoreProtocols`

**Files moved**:
- `CrawlerProtocols/ContentFetcher.swift`
- `CrawlerProtocols/ContentTransformer.swift`
- `CrawlerProtocols/CrawlerEngine.swift`
- `GitHubCanonicalizer.swift`
- `ExclusionList.swift`
- `SwiftPackagesCatalog.swift`

**Target deps**: `["SharedCore", "SharedConstants", "SharedUtils", "SharedModels", "Logging"]`.

**Risk**: low. The three protocols are imported widely but small.

### 2.2 — Extract `CoreHTMLParser`

**Files moved**:
- `Transformers/HTMLToMarkdown.swift` (1,070)
- `Transformers/XMLTransformer.swift` (232)

**Target deps**: `["CoreProtocols", "SharedModels", "SharedConstants"]`.

**Risk**: medium. `HTMLToMarkdown` is a hot path. Verification adds a regression sweep: run the existing `CoreTests` HTML→MD fixture set, confirm byte-identical output.

### 2.3 — Extract `CoreJSONParser`

**Files moved**:
- `Transformers/AppleJSONToMarkdown.swift` (779)
- `Transformers/MarkdownToStructuredPage.swift` (763)
- `Transformers/RefResolver.swift` (406)
- `Transformers/RefResolverFetchers.swift` (131)
- `JSONCrawler/JSONContentFetcher.swift` (56)
- `JSONCrawler/AppleJSONCrawlerEngine.swift` (108)

**Target deps**: `["CoreProtocols", "SharedModels", "SharedConstants"]`.

**Risk**: medium. JSON parser drives the indexed corpus.

### 2.4 — Extract `CorePackageIndexing`

**Files moved**:
- `PackageDependencyResolver.swift` (502)
- `PackageFetcher.swift` (563)
- `PackageArchiveExtractor.swift` (305)
- `PackageAvailabilityAnnotator.swift` (149)
- `PackageDocumentationDownloader.swift` (160)
- `ResolvedPackagesStore.swift` (143)
- `PackageFileKind.swift` (134)
- `ManifestCache.swift` (105)

**Target deps**: `["CoreProtocols", "SharedModels", "SharedConstants", "SharedUtils", "Logging"]`.

**Risk**: high. Concurrency boundary. Verification includes running the full `swift run cupertino fetch packages --limit 5` against a temp directory and diffing the resolved set against a baseline run.

### 2.5 — Extract `CoreSampleCode`

**Files moved**:
- `SampleCodeDownloader.swift` (910)
- `GitHubSampleCodeFetcher.swift` (308)
- `SampleCodeCatalog.swift` (214)
- `PriorityPackageGenerator.swift` (281)
- `PriorityPackagesCatalog.swift` (376)

**Target deps**: `["CoreProtocols", "Resources", "SharedModels", "SharedConstants", "Logging"]`.

**Risk**: medium. `PriorityPackagesCatalog` calls into `Resources` for embedded JSON.

### 2.6 — Extract `CoreArchive`

**Files moved**:
- `AppleArchiveCrawler.swift` (736)
- `ArchiveGuideCatalog.swift` (371)

**Target deps**: `["CoreProtocols", "CoreHTMLParser", "Resources", "SharedModels", "SharedConstants", "Logging"]`.

### 2.7 — Extract `CoreSpecializedCrawlers`

**Files moved**:
- `HIGCrawler.swift` (680)
- `SwiftEvolutionCrawler.swift` (332)

**Target deps**: `["CoreProtocols", "CoreHTMLParser", "SharedModels", "SharedConstants", "Logging"]`.

### 2.8 — Rename residue to `CoreCrawler`

**Files remaining in old Core**:
- `Crawler.swift` (695)
- `CrawlerState.swift` (336)
- `WKWebCrawler/WKWebContentFetcher.swift` (161)
- `WKWebCrawler/WKWebCrawlerEngine.swift` (134)
- `WKWebCrawler/WKWebCrawler.swift` (12)
- `TechnologiesIndexFetcher.swift` (91)
- `CupertinoCore.swift` (36) → updates `print(...)` to `UnifiedLogger` here (folds in Phase 4.6)
- `Core.swift` (6) → namespace remains under the new name

**Target rename**: `Core` → `CoreCrawler`. Product renamed. All downstream imports updated.

**Risk**: high. This is the last and noisiest sweep of Phase 2. After this PR there is no `Core` symbol or `import Core` anywhere in the repo.

---

## 5. Phase 3: Search dissection (8 PRs)

> **Status: 0 done; SUPERSEDED by Option D shape under epic #893 (children #896-#901).** The original 8-target split (`SearchSchema` / `SearchUtilities` / `SearchIntent` / `SearchRanking` / `SearchIndexCore` / `SearchStrategies` / `SearchQuery` / `SearchAPI`) is partially adopted by Option D, but Option D additionally extracts a `SearchSQLite` concrete that owns the only `import SQLite3` site and lifts the 7 source-indexing strategies into 7 separate SPM targets (mirror of secret-life's one-concrete-per-target shape). End-state: ~15 sub-targets for the Search-side surface, not 8. The original task definitions §5.1-§5.8 below are useful boundary references; the v3 sequencing replaces them. See `docs/research/pluggability-analysis-2026-05-22.md` §6.2 + §7.2.

Phase 3 is the hardest. Unlike Phase 2, several files require **code refactoring**, not just relocation. Specifically:

- 3.4 carves ranking logic out of the 1,097-LOC `search(...)` function.
- 3.6 refactors `SearchIndexBuilder`'s 7 hardcoded strategies into a `SourceIndexingStrategy` protocol with concrete impls per source.

These two PRs each get a dedicated design note in `docs/refactor-notes-3.4.md` and `docs/refactor-notes-3.6.md`, written before the branch is cut. The design note is reviewed first.

### 3.1 — Extract `SearchSchema`

**Files moved**:
- `SearchIndex+Schema.swift` (239)
- `SearchIndex+Migrations.swift` (279)

**Target deps**: `["SharedConstants", "SharedUtils"]`.

**Risk**: low. Schema constants now live in one place.

### 3.2 — Extract `SearchUtilities`

**Files moved**:
- `SearchIndex+Helpers.swift` (185)
- `SearchIndex+QueryParsing.swift` (102)
- `SearchIndex+CountsAndAliases.swift` (314)
- `DocKind.swift` (107)
- `SourceDefinition.swift` (350)
- `SearchResult.swift` (360)
- `CandidateFetcher.swift` (216)

**Target deps**: `["SharedModels", "SharedConstants", "SharedUtils"]`.

### 3.3 — Extract `SearchIntent`

**Files split out of `ComposableResult.swift`**:
- The `QueryIntent` enum, `detectQueryIntent(_:)` function, and `SourceProperties` struct (≈300 LOC) → `Packages/Sources/SearchIntent/`.

**`ComposableResult.swift`** is rewritten in place to import the new module; result-atom + section + builder code stays.

**Target deps**: `["SearchUtilities"]`.

**Risk**: medium. This is the first code-shape change in Phase 3.

### 3.4 — Extract `SearchRanking`

**Refactor target**: `SearchIndex+Search.swift` (1,097 LOC). The 600 LOC of ranking heuristics inside `search(...)` are pulled into named functions in a new `SearchRanking` package:

- `rankMultipliers(kind:source:intent:) -> (kindMultiplier: Double, sourceMultiplier: Double, combinedBoost: Double)`
- `applyTitleHeuristics(query:title:) -> Double`
- `boostSymbolMatches(results:symbolURIs:) -> [Result]`
- `forceIncludeFrameworkRoot(query:results:) -> [Result]`
- `filterByPlatformAvailability(results:minIOS:macOS:tvOS:watchOS:visionOS:) -> [Result]`

`search(...)` becomes the orchestrator: build SQL → execute → call ranking functions → return.

**Design note**: `docs/refactor-notes-3.4.md` (written before the branch is cut). Includes the exact slice points in the current 1,097-LOC function and the call site signatures.

**Target deps**: `["SearchIntent", "SearchUtilities", "SharedModels"]`.

**Risk**: high. Ranking output must be byte-identical to today. Verification: run the entire `SearchTests` matrix and compare rank values per query, plus a fixed list of 20 manual queries against a v1.0.2 bundle and diff result ordering.

### 3.5 — Extract `SearchIndexCore`

**Files moved**:
- `SearchIndex+IndexingDocs.swift` (697)
- `SearchIndex+Indexing.swift` (378)

**Target deps**: `["SearchSchema", "SearchUtilities", "ASTIndexer", "SharedModels", "SharedConstants"]`.

**Risk**: medium. Wide-API surface: this module exposes the low-level FTS writers.

### 3.6 — Extract `SearchStrategies`

**Refactor target**: `SearchIndexBuilder.swift` (1,343 LOC). The seven inlined strategies (`indexAppleDocs`, `indexEvolutionProposals`, `indexSwiftOrgDocs`, `indexArchiveDocs`, `indexHIGDocs`, `indexSampleCodeCatalog`, `indexPackagesCatalog`) become seven concrete types conforming to:

```swift
protocol SourceIndexingStrategy: Sendable {
    var source: String { get }
    func indexItems(into index: Search.Index, progress: ProgressCallback?) async throws -> IndexStats
}
```

A `StrategyRegistry` maps source string to strategy instance. `SearchIndexBuilder` shrinks to ~250 LOC of orchestration: build registry, iterate active sources, call `indexItems` on each.

**Design note**: `docs/refactor-notes-3.6.md`. Includes the strategy interface, the per-source breakdown, the shared utility helpers extracted into a `StrategyHelpers` namespace (title extraction, framework extraction, YAML front-matter, #284 defenses).

**Target deps**: `["SearchIndexCore", "SearchSchema", "SearchUtilities", "CoreCrawler", "CoreJSONParser", "CoreArchive", "CoreSpecializedCrawlers", "CoreSampleCode", "CorePackageIndexing", "SharedModels", "SharedConstants", "Resources"]`.

**Risk**: highest in the entire refactor. The strategy refactor changes hot-path code. Verification: full reindex from a fresh checkout against a known docs corpus, diff `SELECT COUNT(*) FROM docs_fts GROUP BY source` against a baseline. Numbers must match exactly.

### 3.7 — Extract `SearchQuery`

**Files moved**:
- `SearchIndex+Search.swift` (now ~500 LOC after 3.4 carved out ranking)
- `SearchIndex+SearchByAttribute.swift` (500)
- `SearchIndex+SemanticSearch.swift` (413)
- `SearchIndex+CodeExamples.swift` (186)
- `SearchIndex+ContentAndPackages.swift` (238)
- `PackageQuery.swift` (722)
- `PackageIndex.swift` (615)
- `PackageIndexer.swift` (250)

**Target deps**: `["SearchSchema", "SearchUtilities", "SearchRanking", "SearchIntent", "SharedModels", "SharedConstants"]`.

**Risk**: medium. Surface area is wide, but each file is independently relocatable.

### 3.8 — Rename residue to `SearchAPI`

**Files remaining**:
- `SearchIndex.swift` (99) — actor lifecycle
- `SmartQuery.swift` (231) — multi-source dispatcher
- `ComposableResult.swift` (now ~570 LOC after 3.3) — atoms + sections + builder
- `Search.swift` (6) — namespace
- `SourceIndexer.swift` (540) — `SourceItem` + `SourceIndexer` protocol + `IndexerRegistry`

**Target rename**: `Search` → `SearchAPI`. Product renamed. All downstream imports updated.

**Risk**: highest after 3.6. Last big sweep.

---

## 6. Phase 4: Cleanup (8 PRs)

(Phase ordering note: Cleanup runs after the three big dissections so the cleanup work touches the new package layout, not the old one. Phase 5 splits `SampleIndex`, which is structurally independent and could in principle run earlier, but is slotted here to keep the train predictable.)


Each is one small PR off `develop`. Order is interchangeable; group by reviewer convenience.

### 4.1 — Fix the force-unwrap in `Availability/AvailabilityFetcher.swift:572`

Replace `URL(string: …)!` with a throwing init guarded by `ToolError.invalidURL`. Update the call site.

### 4.2 — Replace `fatalError("URL.knownGood: …")` in `SharedCore/CupertinoShared.swift:83`

Convert to a throwing initializer. Update the (small) caller list. The two `fatalError`s in `Core/PriorityPackagesCatalog.swift` are legitimately "should be impossible" (embedded resource missing) — keep them but add a comment with the issue number that justifies the choice.

### 4.3 — Dedupe `EmptyParams`

Single canonical definition in `MCP/EmptyParams.swift`. Delete the copy in `MCPClient` and `MockAIAgent`.

### 4.4 — Remove unused `import CryptoKit` in `SharedModels/Page.swift`

Plus a grep sweep for other unused imports surfaced during the refactor.

### 4.5 — Wrap the 19-parameter `indexDocument(...)` in `IndexDocumentParams`

In `SearchIndexCore`. The new signature is `func indexDocument(_ params: IndexDocumentParams) async throws`. `IndexDocumentParams` is a `Sendable struct` with named fields.

### 4.6 — Replace `print(…)` in `CoreCrawler/CupertinoCore.swift:31, 34, 35` with `UnifiedLogger`

Folded into 2.8 if convenient.

### 4.7 — Add `SQL.countRows(in:)` helper

In `SharedUtils/SQL.swift`. Replace the 40+ inline `SELECT COUNT(*) FROM ...` strings across `SampleIndexDatabase`, `SearchIndex+*`, `PackageIndex`.

### 4.8 — Documentation and dead-folder cleanup

- Delete `Apps/.gitkeep` and the empty `Apps/` directory.
- Update `CLAUDE.md` to remove the "app targets in `Apps/`" claim. Note: actual executables live under `Packages/Sources/CLI`, `Packages/Sources/TUI`, etc.
- Update `docs/ARCHITECTURE.md` to reflect the new package layout.
- Remove the legacy `Shared` umbrella migration alias added in 1.6.
- Audit `public` types added/moved during the refactor; demote any with < 2 external callers to `internal` (per the invariant in §2).

---

## 7. Phase 5: SampleIndex dissection (4 PRs)

> **Status: 0 done; SUPERSEDED by Option D shape under epic #893 (child #902).** Original 4-target split mirrors what the v3 refresh does to SampleIndex, but Option D additionally extracts a `SampleIndexSQLite` concrete. SampleIndex today is only 5 files (1 SQLite-importing), so the v3 sub-target count is smaller (~3-4 total) than the Search arc. Read-side protocol `Sample.Index.Reader` already exists in `SampleIndexModels`. The original task definitions §7.1-§7.4 are boundary references; v3 sequencing under epic #893 supersedes.

`SampleIndex` is a structurally self-contained god: `SampleIndexDatabase.swift` is 1,164 LOC with 18 public funcs covering schema, CRUD, query, and availability annotation. Same split pattern as `Search`.

`SampleIndex` depends only on `["Shared", "Logging", "ASTIndexer"]` today and has only one downstream consumer in this round (`Services`), so the sweep is small.

### 5.1 — Extract `SampleIndexSchema`

**Files / slices moved**:
- The `createTable`, `migrate*`, table DDL strings, and version constants from `SampleIndexDatabase.swift` → `Packages/Sources/SampleIndexSchema/Schema.swift`.

**Target deps**: `["SharedConstants", "SharedUtils"]`.

**Risk**: low.

### 5.2 — Extract `SampleIndexCore`

**Files / slices moved**:
- `insertDocument`, `updateDocument`, `deleteDocument`, batch-insert and transactional CRUD from `SampleIndexDatabase.swift` → `Packages/Sources/SampleIndexCore/Writes.swift`.

**Target deps**: `["SampleIndexSchema", "SharedModels", "SharedConstants", "SharedUtils", "Logging"]`.

**Risk**: low.

### 5.3 — Extract `SampleIndexQuery`

**Files / slices moved**:
- `searchByAvailability`, `searchByKind`, `annotateAvailability`, and the read-side query methods → `Packages/Sources/SampleIndexQuery/`.
- `SampleIndexBuilder.swift` (700 LOC) — likely belongs here if its responsibilities are catalog ingestion + index orchestration. Confirmed during the design-note step.

**Target deps**: `["SampleIndexCore", "SampleIndexSchema", "ASTIndexer", "SharedModels", "SharedConstants"]`.

**Risk**: medium. `annotateAvailability` couples to ASTIndexer for `@available` extraction.

### 5.4 — Rename residue to `SampleIndexAPI`

**Files remaining**:
- Actor lifecycle, public-surface entry points, and any thin orchestration left after 5.1–5.3.

**Target rename**: `SampleIndex` → `SampleIndexAPI`. Update `Services` and any other consumer.

**Risk**: medium. Last sweep of Phase 5.

---

## 8. Phase 6: Integration

Once Phases 1–5 are merged into `develop` and green:

1. Rebase `develop` on the latest `main` (v1.0.3 will have shipped by then).
2. Run the full verification recipe on the rebased tip.
3. Open PR `develop → main` titled `release(v1.2.0): package split`.
4. CHANGELOG entry under `## [1.1.0] — <date>`: summarize phases, list new/removed/renamed packages, note schema unchanged.
5. After merge, tag `v1.2.0`. No bundle reindex required (schema unchanged, `databaseVersion` unchanged at `1.0.2`).

---

## 9. Risk register

| Risk | Phase | Mitigation |
|---|---|---|
| `StructuredDocumentationPage` import sweep breaks downstream targets | 1.5 | Keep `Shared` umbrella with `typealias` re-exports through 1.5; remove in 1.6. |
| Ranking output drift after `SearchRanking` carve | 3.4 | Byte-identical comparison of top-50 results for 20 fixed queries against a v1.0.2 bundle. |
| Strategy refactor breaks `indexAppleDocsFromMetadata` resume path | 3.6 | Full reindex test from clean DB, plus interrupted-resume scenario. |
| Last-mile sweep in 2.8 / 3.8 collides with concurrent v1.0.3 work on `main` | All | Rebase `develop` on `main` after each v1.0.x tag; resolve in the sweep PR, not piecemeal. |
| Generated `Resources/Embedded/SwiftPackagesCatalogEmbedded.swift` regenerated during refactor | All | Coordinate with the v1.0.3 reindex process. Do not touch `Resources/` in this branch. |
| Public-API demotion in 4.8 breaks an undeclared consumer | 4.8 | Run `swift build` against every downstream after each demotion. |

---

## 10. Decisions log

Decisions taken before the plan was committed:

| # | Decision | Recorded |
|---|---|---|
| 1 | Plan doc lands via PR (`refactor/0.0-add-plan → develop`), not a direct commit. Establishes the workflow for every subsequent task. | §1 |
| 2 | Package naming uses `Core*`/`Search*`/`Shared*`/`SampleIndex*` prefixes. Preserves discoverability in a flat `Packages/Sources/`. | §2 |
| 3 | `SampleIndex` is folded into this refactor as Phase 5 (4 PRs). Not deferred to v1.2. | §7 |
| 4 | One GitHub issue is opened per task in this plan, under a `v1.1` milestone. PR titles reference both the issue number and the plan section. | §11 |

Open follow-ups (decide before the relevant PR is cut, not blocking the plan):

- Phase 4 fold-in: keep 4.1–4.7 as a clean Phase 4 series (current default), or attach individual cleanups to the package PR that touches the same file?
- 5.3 scope: `SampleIndexBuilder.swift` location (in `SampleIndexQuery` vs its own subpackage) is confirmed in the 5.3 design note before the branch is cut.

---

## 11a. Phase 7 (new in v3 refresh): welded-backend producers

> **Status: 0 done.** Added to the plan in v3 refresh (2026-05-22). Original plan did not address the welded-backend dimension; v3 makes it explicit. Detail under epic #893 children #903-#905.

5 producers carry a welded backend (`WebKit` or `FoundationNetworking`) that the original plan did not separate from the producer:

| Producer | Welded backend | v3 child | Treatment |
|---|---|---|---|
| `Crawler` | `WebKit` | #903 | Add `CrawlerModels.HTTPFetching` protocol + `CrawlerWebKit` sibling concrete. Future Linux unblock via `CrawlerAsyncHTTPClient`. (Crawler's `import os` is logging-shaped, handled separately via the `LoggingModels` pattern; out of scope here.) |
| `Core` | `WebKit` | #904 | Per inspection during this plan refresh: 4 WebKit-touching producers (`Core` + `CoreJSONParser` + `CoreSampleCode` + `Crawler`) may collapse to a single shared `WebFetcher` producer-tier concrete (its own SPM target, with a foundation-only `WebFetcherModels` protocol seam) if the WebKit surface is uniform; otherwise per-producer `*WebKit` siblings. WebKit cannot live in the foundation tier because the foundation contract demands platform-agnostic deps; the shared option still ends up in the producer tier behind a `*Models` seam. Decision pinned in #904's PR body before any code lands. |
| `CoreJSONParser` | `WebKit` | #904 | Same |
| `CoreSampleCode` | `WebKit` | #904 | Same |
| `Availability` | `FoundationNetworking` | #905 | Add `AvailabilityModels.Networking` protocol (or move to `CoreProtocols`) + `AvailabilityFoundationNetworking` sibling concrete. |

Each step ends with a lift-out trace per the §0a v3 sequencing.

---

## 11b. Phase 8 (new in v3 refresh): per-pass Enrichment split

> **Status: 0 done.** Added to the plan in v3 refresh (2026-05-22). The original plan did not anticipate the postprocessor pipeline (`#837` shipped it after this plan was authored). Detail: epic #893 child #906.

The `Enrichment` producer today is the one cupertino producer NOT yet in `STRICT_PRODUCERS` (its 6 sibling passes import `Search` + `SampleIndex` concretes directly). v3 lifts each pass into its own SPM target conforming `EnrichmentModels.EnrichmentPass`:

| Sub-target | Source file moved | Notes |
|---|---|---|
| `Enrichment.AppleConstraintsPass` (own target) | `Enrichment.AppleConstraintsPass.swift` | search.db side |
| `Enrichment.HierarchyPass` | `Enrichment.HierarchyPass.swift` | search.db side |
| `Enrichment.PackagesAppleConstraintsPass` | `Enrichment.PackagesAppleConstraintsPass.swift` | packages.db side |
| `Enrichment.PackagesAppleImportsPass` | `Enrichment.PackagesAppleImportsPass.swift` | packages.db side |
| `Enrichment.SamplesAppleConstraintsPass` | `Enrichment.SamplesAppleConstraintsPass.swift` | samples.db side |
| `Enrichment.SynonymsPass` | `Enrichment.SynonymsPass.swift` | search.db side |

Each consumes the protocol-fronted Search / SampleIndex writers; `Enrichment` (or the dissolved orchestrator residue) gets opted into `STRICT_PRODUCERS` once the passes split clean.

---

## 11. Tracking

- GitHub milestone: `v1.2.0`.
- One issue per task in the plan (1.1 through 5.4 + 4.1 through 4.8 + the integration PR). Each issue is labelled `refactor` and assigned to the milestone. Phase labels (`phase-1`, `phase-2`, …) group them.
- Issues reference the plan section in the body. PR titles reference both: `refactor(<package>): <summary> (#<issue> / refactor-plan §<task-number>)`.

## 12. PR template

```
refactor(<package>): <summary> (#<issue> / refactor-plan §<task-number>)

## Context

Closes #<issue>.
Refactor plan: docs/plans/2026-05-12-v1-1-package-split.md §<task-number>

## Changes

- <files moved / extracted>
- <Package.swift target additions/removals>
- <import sweep summary: N files updated>

## Verification

- swiftformat: pass
- swiftlint: pass
- swift build: pass
- swift test: pass (N tests, M assertions)
- swift run cupertino --help: pass

<paste any ranking / index sanity output here for risky PRs>

## Out of scope

<anything deferred to a later task in the same phase>
```

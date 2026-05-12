# Cupertino Refactor Plan (v1.1)

Status: **draft, pending review**. Tracks the package split work that lands on `develop` after v1.0.2 ships from `main`.

This document is the single source of truth for refactor sequencing. Every refactor PR links back to a numbered task here.

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
- When the full plan is green on `develop`, open a single PR `develop → main` titled `release(v1.1.0): package split`.
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

`Shared` is the dependency hub: 15+ packages import it. Splitting it first means every downstream extraction in Phases 2 and 3 imports a smaller, more targeted surface. Each PR keeps the public API source-compatible by re-exporting moved types from the originating module, then a final pass removes the re-exports.

### 1.1 — Extract `MCPSharedTools`

**Why first**: kills Violation #1 (`Shared → MCP`).

**Files moved**:
- `Packages/Sources/Shared/ArgumentExtractor.swift` → `Packages/Sources/MCPSharedTools/ArgumentExtractor.swift`
- Sub-enum `Shared.Constants.Search` (the ~280 LOC of MCP tool descriptions, parameter names, URI schemes, messages, tips inside `Constants.swift`) → `Packages/Sources/MCPSharedTools/MCPCopy.swift`

**Package.swift changes**:
- Add `MCPSharedTools` target with deps `["MCP", "SharedCore"]`. (Note: `SharedCore` does not exist yet at this point. Provisional dep is `["MCP", "Shared"]`; updated in 1.6.)
- Add `MCPSharedTools` product.
- Remove `MCP` from `Shared` target deps.

**Import updates**: every consumer of `Constants.Search.*` or `ArgumentExtractor` (`MCPSupport`, `SearchToolProvider`, `CLI`) adds `import MCPSharedTools` and removes the symbol from their `Shared` references.

**Risk**: medium. Many callers. Caller list is small (3 packages).

**Verification**: standard recipe + grep for `Constants.Search` in all sources, expect zero hits outside `MCPSharedTools`.

### 1.2 — In-file split of `Shared/Models.swift`

**Why before package split**: `Models.swift` at 1,218 LOC is unreviewable. Split into per-domain files within the same target first; the package extraction in 1.5 is then a folder move, not a code surgery.

**File map** (all inside `Packages/Sources/Shared/`):
- `Models.swift` (deleted)
- New `Models/Page.swift` ← `StructuredDocumentationPage`, `DocumentationPage`, `Kind`, `Source`, `Declaration`, `Section`, `Section.Item`, `CodeExample`
- New `Models/Crawl.swift` ← `CrawlMetadata`, `CrawlStatistics`, `FrameworkStats`, `PageMetadata`, `CrawlSessionState`, `QueuedURL`
- New `Models/Package.swift` ← `PackageReference`, `DocumentationSite`, `PackageDownloadProgress`, `PackageDownloadStatistics`
- New `Models/Sample.swift` ← `CleanupProgress`, `CleanupStatistics`, `CleanupResult`
- New `Models/URLUtilities.swift` ← `URLUtilities` (the 170-LOC enum, including the `filename(_:)` from #283)
- New `Models/HashUtilities.swift` ← `HashUtilities`

**Public API impact**: none. All types remain `Shared.*`.

**Risk**: low (mechanical).

**Verification**: standard recipe. Diff the public API output of `swift package generate-documentation` or just `swift symbolgraph-extract` if available; expect zero deltas.

### 1.3 — Extract `SharedConstants`

**Why**: `Constants.swift` is 1,270 LOC after 1.1 stripped out the MCP text. Foundation-layer-appropriate constants only.

**Files moved**:
- `Packages/Sources/Shared/Constants.swift` → `Packages/Sources/SharedConstants/Constants.swift`

**Package.swift changes**:
- Add `SharedConstants` target with no internal deps.
- Add `SharedConstants` product.
- `Shared` target depends on `SharedConstants` (transitive re-export so existing callers still see `Shared.Constants.*`).

**Risk**: low. The re-export keeps `Shared.Constants.*` paths working through Phase 1.6.

### 1.4 — Extract `SharedUtils`

**Files moved**:
- `Packages/Sources/Shared/JSONCoding.swift` → `Packages/Sources/SharedUtils/JSONCoding.swift`
- `Packages/Sources/Shared/PathResolver.swift` → `Packages/Sources/SharedUtils/PathResolver.swift`
- `Packages/Sources/Shared/Formatting.swift` → `Packages/Sources/SharedUtils/Formatting.swift`
- `Packages/Sources/Shared/FTSQuery.swift` → `Packages/Sources/SharedUtils/FTSQuery.swift`
- `Packages/Sources/Shared/BinaryConfig.swift` → `Packages/Sources/SharedUtils/BinaryConfig.swift`
- `Packages/Sources/Shared/SchemaVersion.swift` → `Packages/Sources/SharedUtils/SchemaVersion.swift`

**Package.swift**: add `SharedUtils` target + product, depends on `SharedConstants` only (PathResolver uses `Constants.Directory`).

**Risk**: low.

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
3. Open PR `develop → main` titled `release(v1.1.0): package split`.
4. CHANGELOG entry under `## [1.1.0] — <date>`: summarize phases, list new/removed/renamed packages, note schema unchanged.
5. After merge, tag `v1.1.0`. No bundle reindex required (schema unchanged, `databaseVersion` unchanged at `1.0.2`).

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

## 11. Tracking

- GitHub milestone: `v1.1.0`.
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

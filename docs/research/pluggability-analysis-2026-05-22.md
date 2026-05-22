# Cupertino pluggability analysis (2026-05-22)

## Status (2026-05-22)

Open analysis. Not a design doc, not a roadmap commit — a measured snapshot of where cupertino sits against the strict-DI / standalone-portability canon (`mihaela-agents/Rules/swift/gof-di-rules.md`) plus a reconciliation with the pre-existing `docs/plans/2026-05-12-v1-1-package-split.md`. Written in response to the user directive *"I want cupertino codebase to be like this, by following gof-di-rules.md, and be completely pluggable"* (referencing the `mihaela-analytics/secret-life` reference implementation).

Companion to:
- `mihaela-agents/Rules/swift/gof-di-rules.md` (the principle layer)
- `mihaela-agents/Rules/swift/per-package-import-contract.md` (the operational deep-dive)
- `mihaela-agents/Rules/swift/shared-protocols-package.md` (the everliv-style alternative)
- `mihaela-agents/Rules/universal/first-principles-analysis.md` (the analysis-doc discipline this doc follows)
- `mihaela-analytics/secret-life/Docs/protocol-seam-audit.md` (the production reference)
- `mihaela-analytics/secret-life/Docs/package-import-contract.md` (the production contract)
- `docs/plans/2026-05-12-v1-1-package-split.md` (the partially-obsolete pre-existing plan)
- `docs/package-import-contract.md` (cupertino's checked-in contract, currently inaccurate)
- GitHub epic #893 (filed 2026-05-22; producer-backend split)
- GitHub epic #769 (orthogonal: layer separation)

## Measurement discipline

Per `mihaela-agents/Rules/universal/first-principles-analysis.md` § "Measurement discipline", every numeric claim in this doc is tagged with one of: **MEASURED** (deterministic command, value cited), **DERIVED** (arithmetic on other tagged values), **STRUCTURAL** (file/line/symbol existence verified on `main` at writing time), **DOCUMENTED** (quoted from a canonical source file). No softeners ("typically", "roughly", "~"). Round numbers are flagged when they are arithmetic accidents.

All measurements are against `main` at commit `5bda656` (working tree clean except this doc) on machine "Mihaela's Mac Studio" (resolved path `/Volumes/Code/DeveloperExt/public/cupertino`), 2026-05-22.

---

## 1. Why this analysis exists

User directive on 2026-05-22, paraphrased: *"Make cupertino completely pluggable per `gof-di-rules.md`. Use `mihaela-analytics/secret-life` as the reference implementation. No moralizing about scope; I don't care how long it takes. Cupertino is becoming too complicated to handle as is."*

Two things this analysis must answer before any code lands:

1. **What does "completely pluggable" mean for cupertino specifically?** The secret-life pattern is concrete (4 protocol seams + concrete sibling targets + composition-root wiring + a mechanical lift-out trace). Cupertino's shape is different (larger, older, mid-refactor). What does the equivalent end-state look like?
2. **What's the gap?** Where is cupertino already pluggable, where isn't it, and what's blocking the gap from closing?

Implicit third question (raised after deeper recon): **how does this relate to the pre-existing `docs/plans/2026-05-12-v1-1-package-split.md`** which already specs an 8-package Search dissection? That plan predates the current `gof-di-rules.md` shape and was partially superseded by epic `#536`. Is it still in force? If not, what replaces it?

---

## 2. Prerequisites

### 2.1 Why pluggability matters here

The current state of cupertino producers is what `gof-di-rules.md` rule 8 calls the **interim regime**: producers may import any `*Models` foundation-only seam target plus the foundation tier. Epic `#536` got every producer to that level. **Every producer in `STRICT_PRODUCERS` is ✅ against `scripts/check-target-foundation-only.sh`** (with one in-flight exception covered in §4 below). [MEASURED: ran `scripts/check-target-foundation-only.sh` 2026-05-22.]

"Pluggable" goes further than "foundation-only". The interim regime says *the producer doesn't depend on another producer's concrete*. The pluggable end-state says *the producer doesn't depend on its own backend's concrete either* — the SQLite, WebKit, FoundationNetworking, etc. lives in a sibling target that conforms a protocol the producer declares. Mechanically provable by:

```bash
scripts/check-target-portability.sh <Producer>
```

which physically copies the producer + its declared transitive deps to a `/tmp/lift-<producer>-*` directory, synthesises a minimal `Package.swift`, and runs `xcrun swift build`. Green = the producer genuinely lifts out.

The reference implementation (`mihaela-analytics/secret-life`, the importer-side) ran this trace on 2026-05-20 for `UmamiWindowImporter + Importer + Persistence`. Documented at `secret-life/Docs/protocol-seam-audit.md` § "Lift-out checks (mechanical, repeatable)". [DOCUMENTED.]

### 2.2 Cupertino's terminology vs secret-life's terminology

The canon files use two parallel vocabularies depending on which reference codebase wrote the example. Both describe the same shape; treat them as synonymous.

| Concept | secret-life calls it | cupertino calls it |
|---|---|---|
| Foundation-only protocol target | `Persistence`, `Schema`, `Importer`, `Renderer` | `SearchModels`, `SampleIndexModels`, `CrawlerModels`, `EnrichmentModels`, etc. (suffixed `Models`) |
| Concrete-backend sibling target | `PersistenceSQLite` | (doesn't exist yet for Search/SampleIndex/Crawler/Core — that's the gap) |
| Composition root | `cli` (lowercase) | `CLI` (capitalised) |
| Composition-root file convention | `CLIImpl.<Subcommand>.swift` | `CLIImpl.Command.<Subcommand>.swift` |
| Factory Method type | `Database` (the protocol itself) | `Search.DatabaseFactory` / `Sample.Index.DatabaseFactory` (separate Factory protocol) |
| The "TOTAL INDEPENDENCE" property | mechanically provable lift-out of one importer + Importer + Persistence | mechanically provable lift-out of one producer + its `*Models` + `SharedConstants` |

Cupertino's `*Models` suffix and explicit `Factory` types are more verbose than secret-life's flat-named protocols, but the topology is the same.

### 2.3 What the user means by "secret-life"

Mihaela has read `mihaela-analytics/secret-life/Docs/protocol-seam-audit.md`. The reference points she calls out are:
- 4 protocol seams (`Persistence`, `Schema`, `Importer`, `Renderer`).
- 27 importer concretes that all match envelope `Foundation + Importer + Persistence (+ ImporterUtilities + MarkdownTable)`. [STRUCTURAL: verified by `grep '^import ' Packages/Sources/Import/Importers/Umami/*.swift` in secret-life repo.]
- One `PersistenceSQLite` concrete that owns the SQLite handle; the `OpaquePointer` never escapes.
- `cli` is the only target that imports concretes. Every other producer imports only `Foundation` + 1-3 protocol seams.
- A 2026-05-20 trace lifted `UmamiWindowImporter + Importer + Persistence` to `/tmp/lift-umami-*` and built green with a minimal 30-line `Package.swift`.

Cupertino's equivalent today: **partial.** The read side has the protocol fronting (`Search.Database`, `Sample.Index.Reader`) plus Factory Method types. The write side does not. The producers themselves still hold the SQLite / WebKit imports. The full lift-out trace does not run end-to-end because of those welded backends.

---

## 3. Cupertino current state (MEASURED)

### 3.1 Producer count and foundation-only status

Cupertino has **28 producer targets** in the strict regime. [MEASURED: counted entries between `STRICT_PRODUCERS=(` and the closing `)` in `scripts/check-target-foundation-only.sh`, command `awk '/^STRICT_PRODUCERS=\(/,/^\)/' scripts/check-target-foundation-only.sh | grep -vE '^\s*(#|STRICT_PRODUCERS|\))' | grep -vE '^\s*$' | wc -l` → `28`.]

The 28 split into:
- **11 `*Models` foundation-only seam targets**: `CoreProtocols`, `CrawlerModels`, `CorePackageIndexingModels`, `SearchModels`, `SampleIndexModels`, `ServicesModels`, `IndexerModels`, `DistributionModels`, `CleanupModels`, `CoreSampleCodeModels`, `RemoteSyncModels`. [MEASURED: counted explicit `*Models` entries in `STRICT_PRODUCERS` array.]
- **17 producer-or-infrastructure targets**: `Availability`, `Cleanup`, `Core`, `CoreJSONParser`, `CorePackageIndexing`, `CoreSampleCode`, `Crawler`, `Distribution`, `Indexer`, `Ingest`, `Logging`, `MCPSupport`, `RemoteSync`, `SampleIndex`, `Search`, `SearchToolProvider`, `Services`. [MEASURED.]

The total Swift surface of `Packages/Sources/` is **408 files, 71,126 LOC**. [MEASURED: `find Packages/Sources -name '*.swift' | wc -l` → `408`; `find Packages/Sources -name '*.swift' -exec wc -l {} + | tail -1` → `71126`.]

### 3.2 Foundation-only check status

Running `scripts/check-target-foundation-only.sh` against `main` at this writing finds **1 real violation**:

```
Violations:
  Search: Packages/Sources/Search/Search.IndexBuilder.swift:1:import EnrichmentModels
```

[MEASURED 2026-05-22.]

The cause is **structural drift, not a code bug**. `EnrichmentModels` is a foundation-only `*Models` seam target added by epic `#837` (the postprocessor pipeline; see `Packages/Sources/EnrichmentModels/EnrichmentModels.swift` header comment "Foundation-only seam for the cupertino postprocessor pipeline. […] Tracking issue: #837."). [DOCUMENTED.] The seam is legitimate by every rule in the canon. But the script's hardcoded allow-list (`MODELS_TARGETS=(...)`) was never updated to include `EnrichmentModels`, so the script falsely flags Search for importing it. [STRUCTURAL: verified by reading `scripts/check-target-foundation-only.sh` lines covering the `MODELS_TARGETS` array — `EnrichmentModels` absent.]

The fix is a 1-line script change. Same change pattern applies to `docs/package-import-contract.md`, which claims Search is ✅ but doesn't list `EnrichmentModels` in Search's allowed-imports column. Doc currently asserts Search imports `["ASTIndexer", "CorePackageIndexingModels", "CoreProtocols", "Foundation", "LoggingModels", "SQLite3", "SearchModels", "SharedConstants"]`; actual is `["ASTIndexer", "CorePackageIndexingModels", "CoreProtocols", "EnrichmentModels", "Foundation", "LoggingModels", "SQLite3", "SearchModels", "SharedConstants"]`. [STRUCTURAL: read `docs/package-import-contract.md` table row + ran `grep -rh '^import ' Packages/Sources/Search | sort -u`.]

### 3.3 Welded-backend audit (the pluggability gap)

For every producer, the imports outside the allowed list (external primitives counted as "welded backends" when they're network / storage / UI frameworks that abstract a swap-target):

| Producer | Welded backend(s) | Notes |
|---|---|---|
| `Search` | `SQLite3` | The pluggability gap this analysis is about. [MEASURED: `grep -rh '^import SQLite3' Packages/Sources/Search`.] |
| `SampleIndex` | `SQLite3`, `OSLog` | Same as Search shape. `OSLog` is a debug-logging artefact (one file). [MEASURED.] |
| `Crawler` | `WebKit`, `os` | WebKit is the HTTP fetcher concrete. `os` is `os_log`-style logging. [MEASURED.] |
| `Core` | `WebKit` | One file uses WebKit's URL/MIME-type helpers. [MEASURED.] |
| `CoreJSONParser` | `WebKit` | Likely the same MIME helper. [MEASURED; not investigated deeper.] |
| `CoreSampleCode` | `WebKit` | Same shape. [MEASURED.] |
| `Availability` | `FoundationNetworking` | Network HTTP. The producer wraps the network call; not currently behind a protocol. [MEASURED.] |
| `Logging` | `OSLog` | Logging concrete. Already the secret-life shape (Logging is the writer concrete; `LoggingModels` is the protocol). [STRUCTURAL.] |
| All other 19 producers | none | At target shape. [MEASURED — none of the other 19 grep matched `SQLite3 / WebKit / FoundationNetworking / CryptoKit`.] |

So the welded-backend gap is **8 of 28 producers** (29%). [DERIVED: 8/28.] Of those 8, `Logging` is already pluggable by the writer-vs-protocol pattern; the actual gap is **7 producers** — `Search`, `SampleIndex`, `Crawler`, `Core`, `CoreJSONParser`, `CoreSampleCode`, `Availability`.

### 3.4 Read-side vs write-side asymmetry in Search

Search is the largest target by LOC and the focal case for this analysis. **15,549 LOC across 42 files; 19 files import SQLite3 (8,912 LOC); 23 files do not (6,637 LOC).** [MEASURED: `find Packages/Sources/Search -name '*.swift' -exec wc -l {} + | tail -1` → `15549`; partition by `grep -l 'import SQLite3'`.]

The 23 non-SQLite3 files include the strategy framework, the smart-query dispatcher, the candidate fetcher, the source indexer abstraction, the result composition, the import-log sink, the doc-link rewriter, the camelCase splitter, the inheritance-from-markdown parser. [STRUCTURAL: listed via `find Packages/Sources/Search -name '*.swift' -exec grep -L 'import SQLite3' {} \;`.]

**The read side is already pluggable.** `Search.Database` (defined in `SearchModels/Search.Database.swift`) is a foundation-only protocol exposing every read method consumers need (`search`, `searchSymbols`, `searchPropertyWrappers`, `searchConcurrencyPatterns`, `searchConformances`, `searchByGenericConstraint`, `resolveSymbolURIs`, `walkInheritance`, `fetchPlatformMinima`, `getDocumentContent`, `listFrameworks`, `documentCount`, `disconnect`). [STRUCTURAL: read `Packages/Sources/SearchModels/Search.Database.swift` lines 1-147.] The concrete `Search.Index` actor in the Search target conforms via a one-line witness (`extension Search.Index: Search.Database {}` in `Packages/Sources/Search/Search.Index.Database.swift` line 14). [STRUCTURAL.] `Search.DatabaseFactory` (in `SearchModels/Search.DatabaseFactory.swift`) is the GoF Factory Method (1994 p. 107) for opening one. [STRUCTURAL + DOCUMENTED.]

Consumers of `any Search.Database` outside the Search package + outside SearchModels: **6 files across 3 targets**. [MEASURED: `grep -rl "any Search\.Database\|: Search\.Database" Packages/Sources/ | grep -v "/SearchModels/" | grep -v "/Search/"` → 6 files: `CLI/SearchModuleAlias.swift`, `SearchToolProvider/CompositeToolProvider.swift`, `Services/Services.ServiceContainer.swift`, `Services/ReadCommands/Services.DocsSearchService.swift`, `Services/ReadCommands/Services.HIGSearchService.swift`, `Services/ReadCommands/Services.TeaserService.swift`, `Services/ReadCommands/Services.UnifiedSearchService.swift` — 7 actually; recount.]

[CORRECTION 2026-05-22 mid-write: the actual grep returned 8 files including `Services.UnifiedSearchService.swift`. Cited count: 7 consumer files (excluding `Services.ServiceContainer.swift` which is the wiring point, not a consumer). MEASURED.]

`LiveSearchDatabaseFactory` is in `CLI/SearchModuleAlias.swift` (lines 50-54). It constructs `SearchModule.Index(dbPath:, logger:)` and returns `any Search.Database`. [STRUCTURAL.] The Services targets never import `Search` directly for the read flow; they consume `any Search.Database` from `SearchModels`. [STRUCTURAL: `grep -l '^import Search$' Packages/Sources/Services/` returns no matches.]

This is exactly the secret-life pattern for the read side.

**The write side is NOT pluggable.** `Search.IndexBuilder.init(searchIndex: Search.Index, ...)` takes the concrete `Search.Index` actor by name, not as `any <Protocol>`. [STRUCTURAL: `Packages/Sources/Search/Search.IndexBuilder.swift` line 87-88 declares `public init(searchIndex: Search.Index, ...)`.] All 6 strategy implementations (`Search.Strategies.AppleArchive`, `AppleDocs`, `HIG`, `SampleCode`, `SwiftEvolution`, `SwiftOrg`) take `Search.Index` directly. [STRUCTURAL: `grep -l "Search\.Index" Packages/Sources/Search/Strategies/*.swift` → 7 files.]

There is no `Search.IndexWriter` protocol equivalent to `Search.Database`. [STRUCTURAL: `grep -rn 'IndexWriter\|public protocol Writer' Packages/Sources/SearchModels/` → no matches.] The write surface is concrete-only.

So Search's pluggability is **half-done**:

| Surface | Protocol-fronted? | Conformer | Consumers |
|---|---|---|---|
| Read (search queries, symbol lookup, inheritance walks, doc content fetch) | ✅ Yes: `Search.Database` + `Search.DatabaseFactory` in SearchModels | `Search.Index` in Search | 6 files in Services + SearchToolProvider + CLI; none `import Search` |
| Write (FTS5 inserts, AST symbol indexing, schema migrations, framework alias registration) | ❌ No | `Search.Index` in Search (same actor) | All 13 files inside Search (strategies + builder + helpers + candidate fetcher + package-side); plus 18 files in CLI / Enrichment that `import Search` |

### 3.5 SampleIndex is symmetric

`Sample.Index.Reader` exists as the read-side protocol in `SampleIndexModels/Sample.Index.Reader.swift` (lines 17-26 establish the same pattern: *"Read-only seam for the SampleIndex database actor. […] Mirrors the `Search.Database` seam in `SearchModels`"*). [DOCUMENTED.] `Sample.Index.DatabaseFactory` exists in `SampleIndexModels/Sample.Index.DatabaseFactory.swift`. [STRUCTURAL.]

SampleIndex itself is small: **5 files, 1 importing SQLite3** (`Sample.Index.Database.swift`). [MEASURED: `find Packages/Sources/SampleIndex -name '*.swift' | wc -l` → 5; `grep -l 'import SQLite3' Packages/Sources/SampleIndex/*.swift` → 1.] Write surface is concrete-only just like Search.

12 files outside SampleIndex `import SampleIndex` directly — all of them in `CLI/Commands/` (10) or `Enrichment/` (1) or `CLI/SearchModuleAlias.swift` (1). [MEASURED.] The CLI imports are legitimate (composition root); the Enrichment import is for the write side.

### 3.6 SQLite3 footprint across the workspace

**22 Swift files import SQLite3 across `Packages/Sources/`.** [MEASURED: `grep -rln '^import SQLite3' Packages/Sources/ | sort -u | wc -l` → `22`.]

Split: 19 in Search, 1 in SampleIndex (`Sample.Index.Database.swift`), 1 in Diagnostics (`Diagnostics.Probes.swift` — read-only probe, separate target, foundation-tier), 1 in Shared.Utils (`Shared.Utils.SQL.swift` — SQL helper that lives in SharedConstants since #536). [MEASURED.] [DERIVED: 19 + 1 + 1 + 1 = 22.]

The Diagnostics + Shared.Utils.SQL files are correctly placed (Diagnostics is foundation-tier infrastructure; SQL helper is utility). The 20 in Search + SampleIndex are the pluggability gap.

---

## 4. Rule-canon audit findings

Per `mihaela-agents/Rules/universal/rule-canon-audit.md`, "follow the rules" means execute every acceptance check the rules ship, not just read prose. Findings against current `main`:

### 4.1 code-style.md §302 ("one non-private type per file")

**Empty — pass.** [MEASURED 2026-05-22: ran the canonical bash block from §302 over `Packages/Sources/Search Packages/Sources/SearchModels`; no output.]

### 4.2 gof-di-rules.md §7 (`check-package-purity.sh`)

**Pass with grandfathered exception.** Script output ends with: *"Package purity check passed — but 6 grandfathered import(s) remain in: Enrichment. Follow-up issue tracks migrating these out."* [MEASURED 2026-05-22.]

The Enrichment grandfathering is independent of the producer-backend pluggability gap. It's a known follow-up tracked by a separate issue (not investigated here; not blocking).

### 4.3 gof-di-rules.md §5 (`check-target-foundation-only.sh`)

**One violation.** Already described in §3.2 above: `Search: Packages/Sources/Search/Search.IndexBuilder.swift:1:import EnrichmentModels`. Caused by `EnrichmentModels` being absent from the script's `MODELS_TARGETS` allow-list, not by Search misbehaving.

### 4.4 per-package-import-contract.md (the checked-in doc)

**The doc is stale.** [STRUCTURAL: compared `docs/package-import-contract.md` Search row against `grep -rh '^import ' Packages/Sources/Search | sort -u`.] Search's allowed-imports column omits `EnrichmentModels`. Easy fix: add `EnrichmentModels` to the column and to the audit-script allow-list in the same PR.

### 4.5 `xcrun swift build` and `xcrun swift test`

**Not run for this analysis** — this is a read-only audit doc, no code changes. The v1.2.0 baseline is 2408 tests across 347 suites passing in 101.2s as of 2026-05-21. [DOCUMENTED: `docs/audits/issue-merit-audit-2026-05-21.md` "Full test suite baseline | **2408/347 passed in 101.2s** (matches v1.2.0 ship state)".]

Any future PR landing the work described in §6 below MUST cite a fresh run that maintains this baseline.

---

## 5. The 2026-05-12 plan: status (STRUCTURAL)

`docs/plans/2026-05-12-v1-1-package-split.md` (665 lines, authored 2026-05-12) predates both the current `gof-di-rules.md` shape and epic `#536` (the strict-DI singleton-kill that landed 2026-05-14). [DOCUMENTED: plan file metadata + epic reference.] It plans 25 sub-package extractions across 4 phases. Current actual existence:

### 5.1 Phase 1 (Shared dissection — 6 planned targets)

| Planned target | Status | Note |
|---|---|---|
| `MCPSharedTools` | ✅ exists | [MEASURED.] |
| `SharedConstants` | ✅ exists | [MEASURED.] |
| `SharedCore` | ❌ absent | Absorbed into `SharedConstants` per #536. [DOCUMENTED: see `docs/package-import-contract.md` line 5 "absorbed `SharedCore` / `SharedUtils` / `SharedModels` / `SharedConfiguration` into `SharedConstants`".] |
| `SharedUtils` | ❌ absent | Same as above. |
| `SharedModels` | ❌ absent | Same as above. |
| `SharedConfiguration` | ❌ absent | Same as above. |

**2 of 6 planned exist.** [DERIVED: 2/6 = 33%.] Phase 1 was executed but in a **different shape than the plan** — `#536` collapsed 4 sub-packages into `SharedConstants`. The plan still describes the original 4-way split. **Plan is obsolete on this phase.**

### 5.2 Phase 2 (Core dissection — 8 planned targets)

| Planned target | Status |
|---|---|
| `CoreProtocols` | ✅ exists |
| `CoreHTMLParser` | ❌ absent |
| `CoreJSONParser` | ✅ exists |
| `CorePackageIndexing` | ✅ exists |
| `CoreSampleCode` | ✅ exists |
| `CoreArchive` | ❌ absent |
| `CoreSpecializedCrawlers` | ❌ absent |
| `CoreCrawler` (rename of `Core`) | ❌ absent (Core still named `Core`) |

[MEASURED 2026-05-22.] **4 of 8 planned exist.** [DERIVED: 4/8 = 50%.] Phase 2 is **half-done.** `CoreHTMLParser` would extract `Core/HTMLParser/` (4 files). `CoreCrawler` would rename the residual Core target. `CoreArchive` + `CoreSpecializedCrawlers` would extract specialised crawlers from `Crawler`.

### 5.3 Phase 3 (Search dissection — 8 planned targets)

| Planned target | Status |
|---|---|
| `SearchSchema` | ❌ absent |
| `SearchUtilities` | ❌ absent |
| `SearchIntent` | ❌ absent |
| `SearchRanking` | ❌ absent |
| `SearchIndexCore` | ❌ absent |
| `SearchStrategies` | ❌ absent |
| `SearchQuery` | ❌ absent |
| `SearchAPI` (rename of `Search`) | ❌ absent (still `Search`) |

[MEASURED.] **0 of 8 planned exist. Phase 3 has not started.** The `Packages/Package.swift` Search-target comment block (visible in §6 below) explicitly references this plan: *"They remain in the Search target for now because a clean `SearchStrategies` package extraction requires SearchIndexCore (§3.5) to be done first."* [DOCUMENTED: `Packages/Package.swift` searchTarget declaration block.]

### 5.4 SampleIndex sub-extraction (4 planned targets, mirrors Phase 3)

| Planned target | Status |
|---|---|
| `SampleIndexSchema` | ❌ absent |
| `SampleIndexCore` | ❌ absent |
| `SampleIndexQuery` | ❌ absent |
| `SampleIndexAPI` (rename) | ❌ absent (still `SampleIndex`) |

**0 of 4 planned exist.**

### 5.5 Aggregate plan status

[DERIVED: 6 of 26 planned targets exist (23% of plan).] Two phases done-in-different-shape; one phase half-done; two phases zero-done. **The plan is partially obsolete and substantially unexecuted.** Following it verbatim is impossible (Phase 1 went a different direction). Following its Phase 3 + SampleIndex sections is still mechanically possible — those phases don't depend on the un-executed Phase 1 shape.

The plan also predates the `gof-di-rules.md` "TOTAL INDEPENDENCE" framing. Its design rationale is **modularity for compile speed and clarity**, not pluggability. The 8-Search-target end-state lets each sub-target compile independently but doesn't by itself make the SQLite3 dependency swappable — that requires the additional protocol-fronting work this analysis recommends. The plan and the pluggability directive are **compatible but distinct**.

---

## 6. The target topology

There is one shape that satisfies the user's stated goal (TOTAL INDEPENDENCE of each package with DI). Earlier drafts of this doc considered partial alternatives (a 2-target Search split, a plan-only execution, a hybrid). They were dropped. They do not satisfy the goal. The user said *"no moralizing, I don't care how long it takes"*; partial-independence is moralizing about scope.

What the user cares about, restated verbatim from the canon they pointed at:
- *"every package can be pulled out of monorepo anytime, every one, anytime"*
- *"full autonomy for each package, every dep is injectible"*
- *"TOTAL INDEPENDENCE of each package with DI"*
- *"dependencies all the way, not using other packages, protocols instead"*

The shape that satisfies this:

### 6.1 Every welded backend lifts to a sibling concrete target

For each of the 7 producers in §3.3 with a welded backend, the secret-life pattern applies:

| Today | After |
|---|---|
| `Search` imports `SQLite3` | `Search` (orchestration, no SQLite3) + `SearchSQLite` (concrete) |
| `SampleIndex` imports `SQLite3` | `SampleIndex` + `SampleIndexSQLite` |
| `Crawler` imports `WebKit` | `Crawler` + `CrawlerWebKit` (sibling: `CrawlerAsyncHTTPClient` for Linux when needed) |
| `Core` imports `WebKit` | `Core` + `CoreWebKit` |
| `CoreJSONParser` imports `WebKit` | `CoreJSONParser` + `CoreJSONParserWebKit` |
| `CoreSampleCode` imports `WebKit` | `CoreSampleCode` + `CoreSampleCodeWebKit` |
| `Availability` imports `FoundationNetworking` | `Availability` + `AvailabilityFoundationNetworking` |

`Logging` is already at this shape (`LoggingModels` foundation-only seam + `Logging` writer concrete in a sibling target). It's the existence proof inside cupertino.

The 4 WebKit-touching producers (Core, CoreJSONParser, CoreSampleCode, Crawler) may collapse to a shared `WebFetcher` foundation-tier target if their WebKit usage is identical (a single MIME/URL helper). Decided per file-by-file inspection during the refresh PR, not now.

### 6.2 Every concrete is one target

The secret-life pattern is **one concrete per SPM target**. 27 importers, 27 targets. The cupertino equivalent inside Search:

- 7 source-indexing strategies (`Search.Strategies.AppleArchive`, `AppleDocs`, `HIG`, `SampleCode`, `SwiftEvolution`, `SwiftOrg`, `Packages`) → 7 SPM targets, each conforming a `SearchModels.SourceIndexingStrategy` protocol.
- Inheritance walkers, availability annotators, enrichment passes — every concrete that today co-habits a producer target lifts to its own target. The Enrichment package already has 5 sibling pass-types (`Enrichment.AppleConstraintsPass`, `HierarchyPass`, `PackagesAppleConstraintsPass`, `PackagesAppleImportsPass`, `SamplesAppleConstraintsPass`, `SynonymsPass`); they should each be their own SPM target conforming the existing `EnrichmentModels.EnrichmentPass` protocol.

Each of these is independently liftable, independently substitutable, independently swappable. Adding a new strategy (WWDC tech-talks, Apple sample-code v2, anything) is a new SPM target, zero touches to existing ones.

### 6.3 The 2026-05-12 plan is partially obsolete and gets refreshed in place

`docs/plans/2026-05-12-v1-1-package-split.md` already specs Phase 3 (Search dissection into 8 sub-targets). The refresh:
- Mark Phase 1 done-in-different-shape per `#536` (4 sub-packages absorbed into `SharedConstants`).
- Update Phase 2 status (4 of 8 done; 4 still to do).
- Extend Phase 3 spec to include the SearchSQLite extraction + per-strategy granularity.
- Add Phase 5 (the 5 welded-backend producers the original plan didn't mention).
- Add a SampleIndex parallel section.

The refreshed plan is the canonical sequencing record. This analysis doc is its design rationale.

### 6.4 End-state shape (whole workspace)

Approximate end-state target count: **~35-42 producer SPM targets** (current: 28). Plus the existing 11 `*Models` companions (unchanged in topology; extended with new write-side + strategy protocols). Plus matching test targets.

Every producer's lift-out trace passes: `<Producer> + <Producer>Models + SharedConstants` (+ a small number of other `*Models` foundation-only seams) builds green under `xcrun swift build` against a minimal `Package.swift`.

`grep '^import SQLite3'` returns hits **only** in `SearchSQLite`, `SampleIndexSQLite`, `Diagnostics`, and `Shared.Utils.SQL` (the foundation-tier SQL helper). Same for `WebKit` (only in the `*WebKit` siblings + the optional shared `WebFetcher`). Same for `FoundationNetworking` (only in `AvailabilityFoundationNetworking`).

This is what the secret-life trace produces in production. This is what cupertino's equivalent has to produce.

---

## 7. Sequencing

The arc is large and the user has explicitly chosen scope-doesn't-matter. Sequencing is therefore purely a function of dependency order and risk-isolation, not size minimization.

Each step is a separate PR. Each PR cites `xcrun swift build` + `xcrun swift test` per `verification-before-completion.md`, maintains the v1.2.0 baseline (2408 tests / 347 suites — DOCUMENTED §4.5), and ships its own CHANGELOG entry.

### 7.1 Pre-flight (hygiene; ships before the main arc)

| # | PR | Notes |
|---|---|---|
| 0a | Add `EnrichmentModels` to `MODELS_TARGETS` in `scripts/check-target-foundation-only.sh`; re-audit the entire allow-list against `Package.swift` for other drift | trivial; clears the one current rule-canon-audit failure |
| 0b | Update `docs/package-import-contract.md` Search row to include `EnrichmentModels` | trivial doc fix |
| 0c | Refresh `docs/plans/2026-05-12-v1-1-package-split.md` per §6.3: mark Phase 1 done-in-different-shape; update Phase 2; replace Phase 3 spec with §6.1/6.2 shape; add Phase 4 (the 5 welded-backend producers); add SampleIndex parallel section | docs only; supersedes this analysis as the canonical sequencing record |

### 7.2 Search arc (largest producer; landing pattern that the rest of the arc replicates)

Protocol-fronting first, then extractions, then concrete-move, then per-strategy split, then lift-out.

| # | PR |
|---|---|
| 1 | Add write-side protocols to `SearchModels`: `Search.IndexWriter`, `Search.IndexWriterFactory`, `Search.PackageQueryProtocol`, `Search.PackageQueryFactory`, `Search.SourceIndexingStrategy`. Make `Search.Index` conform via one-line witness extensions. Zero file moves. |
| 2 | Rewire `Search.IndexBuilder` to take `any Search.IndexWriter` via init. Rewire each of the 7 `Search.Strategies.*` to take `any Search.IndexWriter` via init. CLI constructs `Search.Index` and hands it as the protocol. |
| 3 | Phase-3.1 SearchSchema extraction (migrations + DDL → foundation-only target) |
| 4 | Phase-3.2 SearchUtilities extraction (helpers, query parsing, counts, doc-kind, source definitions, search-result value type, candidate fetcher) |
| 5 | Phase-3.3 SearchIntent extraction (QueryIntent + detection) |
| 6 | Phase-3.4 SearchRanking carve (BM25 + heuristics + symbol boost). Highest verification bar: ranking output must be byte-identical. |
| 7 | Extract `SearchSQLite` target: move the 19 `Search.Index.*.swift` files + `PackageIndex.swift` + `Search.PackageQuery.swift` here. Conform to all SearchModels write protocols. Search target drops `import SQLite3`. |
| 8a | Extract `AppleArchiveStrategy` as own SPM target |
| 8b | Extract `AppleDocsStrategy` |
| 8c | Extract `HIGStrategy` |
| 8d | Extract `SampleCodeStrategy` |
| 8e | Extract `SwiftEvolutionStrategy` |
| 8f | Extract `SwiftOrgStrategy` |
| 8g | Extract `PackagesStrategy` |
| 9 | Phase-3.7 SearchQuery extraction (slim `search()` + `searchByAttribute` + `searchSymbols` + `searchCodeExamples`) |
| 10 | Phase-3.8 rename residue → SearchAPI (lifecycle + SmartQuery + ComposableResult) |
| 11 | Lift-out trace: `SearchAPI + SearchModels + SharedConstants + LoggingModels + Resources + ASTIndexer + EnrichmentModels + CorePackageIndexingModels + CoreProtocols` builds green with `xcrun swift build` under a synthesised minimal `Package.swift`. No SQLite3 anywhere in the lifted graph. |
| 12 | Lift-out trace for each `<Source>Strategy` target individually |

### 7.3 SampleIndex arc (mirrors §7.2 pattern at smaller scale)

| # | PR |
|---|---|
| 13 | Add write-side protocols to `SampleIndexModels` (mirror of Search) |
| 14 | Rewire `SampleIndex.Builder` to take protocols via init |
| 15 | Extract `SampleIndexSchema`, `SampleIndexUtilities` (if needed; the producer is small) |
| 16 | Extract `SampleIndexSQLite` |
| 17 | Per-source-strategy extractions inside SampleIndex (if any; today only 5 files, may not warrant) |
| 18 | Lift-out trace for SampleIndex |

### 7.4 Crawler arc (WebKit gets the same treatment)

| # | PR |
|---|---|
| 19 | Add `CrawlerModels.HTTPFetching` protocol + `HTTPFetcherFactory` |
| 20 | Rewire Crawler + State machine to take `any HTTPFetching` via init |
| 21 | Extract `CrawlerWebKit` sibling target; conforms `HTTPFetching` |
| 22 | Lift-out trace for Crawler (no WebKit in the lifted graph) |
| 23 | Optional now-or-later: `CrawlerAsyncHTTPClient` for Linux support (deferred to existing memory `cupertino_no_linux_for_now.md`; can wait) |

### 7.5 Core / CoreJSONParser / CoreSampleCode WebKit usage

These 3 producers each have a small WebKit footprint. Decision per file-by-file inspection during 0c's refresh PR: either each gets a `*WebKit` sibling, or all of them share a single `WebFetcher` foundation-tier target. The decision is mechanical from the file inspection, not architectural.

| # | PR |
|---|---|
| 24 | Per the 0c decision: extract `CoreWebKit` + `CoreJSONParserWebKit` + `CoreSampleCodeWebKit`, OR extract `WebFetcher` shared foundation-tier target |
| 25 | Rewire the 3 producers to consume the protocol; drop their WebKit imports |
| 26 | Lift-out traces for the 3 producers |

### 7.6 Availability arc (FoundationNetworking)

| # | PR |
|---|---|
| 27 | Add `Availability.Networking` protocol to a new foundation-only `AvailabilityModels` (or to `CoreProtocols` — TBD by inspection) |
| 28 | Rewire Availability fetcher to consume protocol |
| 29 | Extract `AvailabilityFoundationNetworking` sibling target |
| 30 | Lift-out trace |

### 7.7 Enrichment per-pass granularity (matches §6.2)

| # | PR |
|---|---|
| 31 | Audit Enrichment: confirm `EnrichmentModels.EnrichmentPass` protocol exists (it does, per #837); split the 6 sibling pass-types into 6 SPM targets, each conforming the protocol |
| 32-37 | One PR per pass: `Enrichment.AppleConstraintsPass`, `Enrichment.HierarchyPass`, `Enrichment.PackagesAppleConstraintsPass`, `Enrichment.PackagesAppleImportsPass`, `Enrichment.SamplesAppleConstraintsPass`, `Enrichment.SynonymsPass` |
| 38 | Lift-out traces for each |

### 7.8 Closing

| # | PR |
|---|---|
| 39 | Full re-audit of `docs/package-import-contract.md` — every row reflects the end-state. Run `scripts/check-target-foundation-only.sh` + `scripts/check-target-portability.sh` across every producer. |
| 40 | Update `docs/plans/2026-05-12-v1-1-package-split.md` to mark every phase done. |
| 41 | Close epic #893. |

**Arc total: ~40 PRs.** Per the user: scope size is not a deciding factor.

---

## 8. Failure modes to expect

[Per `first-principles-analysis.md` §5: catalogue realistic failure modes for each subsystem.]

| Failure mode | Where it bites | Mitigation |
|---|---|---|
| Ranking output changes byte-for-byte after SearchRanking carve | PR step 6; users see different result ordering for stable queries | Per plan §3.4 risk note: re-run full SearchTests matrix; manual 20-query diff against v1.2.0 bundle |
| FTS5 `INSERT INTO` performance regresses when prepared statements move behind a protocol abstraction | PR step 7 (SearchSQLite extraction); full reindex slows from 12h to longer | Benchmark a small reindex (a single framework, say SwiftUI) before/after; if regression > 5%, investigate whether the protocol shape needs a prepared-statement caching API |
| Existing Strategy types in `Search/Strategies/` accept `Search.Index` concrete; rewiring to `any Search.IndexWriter` reveals hidden state access | PR step 2 | Audit each Strategy file before the rewire; any access to `Search.Index` internals beyond the public surface needs to be lifted into the protocol |
| Test fixtures that pass `Search.Index` constructors directly to test code break when the type moves to `SearchSQLite` | PR step 7 | Tests should already use `any Search.Database` for read assertions; write-side test fixtures need a similar mock or factory |
| Composition root grows unmanageably as more concretes are wired | Throughout | Per `gof-di-rules.md` §6, accept this; the composition root is supposed to be the wide point. Mitigate via `CLIImpl.Live*Factory.swift` per-factory files |
| `EnrichmentModels` is one of several seams not in the audit script's allow-list; more drift may be hiding | PR step 0a | While fixing the EnrichmentModels miss, re-audit the script's `MODELS_TARGETS` against the actual `*Models` targets in `Package.swift` |
| Lift-out trace fails because a transitive dep is missing | PR steps 11, 18, 22, 26, 30, 38 | Iterate: each missing dep gets added to the minimal Package.swift until build passes; this is exactly what the trace exists to surface |
| #769 layer-separation epic lands in parallel and creates merge conflicts | Throughout | Coordinate sequencing: epic #769 is currently un-started (per `gh issue view 769` 2026-05-21 status). Either freeze #769 work during this arc, or merge #769 Phase 1 (Crawler→Indexer handoff contract) first since it's docs-only |
| #893 epic body needs updating as PRs land | Throughout | Per `github-discipline.md` rule 1.1: edit the status block + child-issue refs in place as each PR closes |
| WebKit MIME-type helpers behave differently if replaced with a Foundation-only equivalent | PR steps 24-26 | The inspection in step 0c surfaces whether WebKit is the only API providing this. If so, the protocol exposes WebKit-equivalent behaviour; the `*WebKit` siblings keep the framework. Alternative backends only added when needed. |
| `FoundationNetworking` on macOS is a no-op import but the Linux build needs it explicitly | PR step 27-30 | The `AvailabilityFoundationNetworking` sibling carries the `#if canImport(FoundationNetworking)` guard; the producer never sees it |
| Strategy extraction blows up incremental build times because of new module boundaries | PR steps 8a-8g | Accept the cost; per `gof-di-rules.md` rule 5, "every package lifts out" is the primary goal. Incremental compile speed is a secondary concern. |

---

## 9. Open questions

These are sequencing questions, not principle questions. The principle (TOTAL INDEPENDENCE of every producer, per `gof-di-rules.md`) is settled; the questions below are only about ordering.

1. **#769 timing.** Epic #769 (layer separation into standalone binaries) is independent of this arc. Do its docs-only Phase 1 (#770 corpus contract) before this arc starts? Land it in parallel? Land it after? Either of the first two is fine; "after" risks merge friction.
2. **Pre-flight folding.** PRs 0a/0b/0c are docs-only. Land as 3 separate PRs, or one combined hygiene PR? (Doesn't matter much; either is reversible.)
3. **WebKit decision in 0c.** Whether the 4 WebKit-touching producers each get their own sibling OR share a single `WebFetcher` foundation-tier target. Mechanical decision once the file inspection happens during the plan refresh.

---

## 10. Glossary

- **`*Models` seam target**: cupertino's term for a foundation-only SPM target carrying protocols + value types but no concrete behaviour. Example: `SearchModels`, `SampleIndexModels`. Equivalent to `Persistence` / `Schema` / `Importer` / `Renderer` in secret-life. Deps: empty or `[SharedConstants]`.
- **`Live*Factory`**: cupertino's term for the GoF Factory Method (1994 p. 107) concrete implementation living in the composition root (`CLIImpl.*.swift`). Constructs the live concrete and hands it to consumers as `any <Protocol>`.
- **STRICT_PRODUCERS**: the array in `scripts/check-target-foundation-only.sh` enumerating producer targets the script audits against the foundation-only allow-list. Every name in this array gets per-file `grep '^import'` audit on each PR.
- **Welded backend**: an external framework (SQLite3, WebKit, FoundationNetworking) that a producer imports directly rather than going through a protocol-typed value supplied via init. The pluggability gap.
- **Lift-out trace**: physically copying a producer + its declared transitive deps to a `/tmp/lift-<name>-*` directory, synthesising a minimal `Package.swift`, running `xcrun swift build`. Green = the producer is mechanically standalone-portable. Reference: `scripts/check-target-portability.sh` (cupertino) / `secret-life/Docs/protocol-seam-audit.md` § "Lift-out checks".
- **Interim regime vs target regime**: `gof-di-rules.md` §8. Interim = producer imports any `*Models` + foundation tier. Target = producer imports only its own `*Models` (or external primitives). Cupertino is at interim today; this analysis is about getting closer to target.
- **secret-life**: `mihaela-analytics/secret-life`, the reference implementation Mihaela points to. Documented at `Docs/protocol-seam-audit.md` and `Docs/package-import-contract.md` in that repo.

---

## 11. References

- `mihaela-agents/Rules/swift/gof-di-rules.md` — 12 canonical rules; this analysis grounds every choice against them.
- `mihaela-agents/Rules/swift/per-package-import-contract.md` — operational deep-dive on rules 4-8.
- `mihaela-agents/Rules/swift/shared-protocols-package.md` — the alternative `SharedProtocols` shape (everliv pattern); cupertino diverges from this in favour of per-producer `*Models`.
- `mihaela-agents/Rules/universal/first-principles-analysis.md` — measurement-discipline rules this doc applies.
- `mihaela-agents/Rules/universal/rule-canon-audit.md` — the "execute every acceptance check" procedure §4 above ran.
- `mihaela-analytics/secret-life/Docs/protocol-seam-audit.md` — the production reference (4 seams + 27 importers + lift-out trace).
- `mihaela-analytics/secret-life/Docs/package-import-contract.md` — secret-life's per-target contract; the shape this analysis targets cupertino at.
- `docs/plans/2026-05-12-v1-1-package-split.md` — the partially-obsolete pre-existing plan. To be refreshed in PR-1.
- `docs/package-import-contract.md` — cupertino's currently-inaccurate import contract. To be updated through this arc.
- Gamma, Helm, Johnson, Vlissides (1994), *Design Patterns* — Factory Method p. 107; Strategy p. 315; Singleton p. 127 (rejected).
- Seemann, M. (2011), *Dependency Injection in .NET* — Service Locator anti-pattern ch. 5; Composition Root ch. 4.

---

## Provenance

Author: Mihaela Mihaljevic (drafted via Claude Code session, 2026-05-22).
Location: `docs/research/pluggability-analysis-2026-05-22.md`.
Status: Open for review. No code changes accompany this doc. Action items live in §7 (sequencing) and §9 (sequencing questions).

### Revision history

- **2026-05-22 v1**: Initial draft. Presented Options A/B/C (2 / 8 / 9 sub-targets) as alternatives. Recommended Option C.
- **2026-05-22 v2**: User caught the scope-optimisation in v1. The A/B/C framing was discarded. v1 left 5 of 7 welded-backend producers unaddressed (Crawler/WebKit, Core/WebKit, CoreJSONParser/WebKit, CoreSampleCode/WebKit, Availability/FoundationNetworking) and kept the 7 source-indexing strategies inside a single `SearchStrategies` target. v2 lifts every welded-backend producer and splits every concrete to its own SPM target, per the user's stated goal of TOTAL INDEPENDENCE.
- **2026-05-22 v3 (post-PR-#908 numeric refresh)**. PR #908 (the pre-flight hygiene §7.1 PRs 0a + 0b) landed. Stale MEASURED claims in §3.1 / §3.2 / §3.3 / §4.3 / §4.4 reflect the pre-#908 state and are inaccurate after merge. Specifically: §3.1 count "28 producer targets" is now 30; §3.1 prose breakdown "11 `*Models` foundation-only seam targets + 17 producer-or-infrastructure targets" is now 12 + 18 (AppleConstraintsKit + EnrichmentModels were opted into STRICT_PRODUCERS); §3.2 verbatim line "**1 real violation**" is now zero (and §4.3's "One violation" line matches; both reflected the same script-failure state that #908 fixed); §3.2 claim "the doc currently asserts Search imports … (no EnrichmentModels)" is also now false (Search row updated by #908); §3.3 welded-backend audit "8 of 28 producers (29%)" is now 8 of 30 (DERIVED ratio rerun: 8/30 ≈ 27%; the 7-actual-gap-producers list is unchanged because #908 did not extract any concrete backend); §4.4 the contract-doc-is-stale paragraph is satisfied (the doc was refreshed in the same PR). Re-run any specific measurement before citing.

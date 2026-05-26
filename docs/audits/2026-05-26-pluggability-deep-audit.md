# 2026-05-26 Pluggability Deep Audit — Source Independence Day

## Frame

Per [#919](https://github.com/mihaelamj/cupertino/issues/919) / Source Independence Day: adding a new content source (or DB) must be a strictly 2-file PR (provider descriptor + indexer concrete) with zero edits to existing concretes, registries, switches, or static literals.

Prior audit batches 1–10 closed [#1045](https://github.com/mihaelamj/cupertino/issues/1045)'s 4 Gaps for the search-side wiring (SmartQuery weights, footer availableSources, DocKind dict, DocsIndexing directoryByKey). This audit is the layer-by-layer follow-up after that ship, searching for *remaining* 80% holes.

Method: 8-layer top-down audit. Each layer asks "does adding a new source require touching this code?". If yes, that's a finding.

Status legend:
- ✅ Layer clean (registry-derived end-to-end)
- ⚠ Maintenance trap (production paths clean today, but a fallback / static literal sits as a future-PR footgun)
- ❌ Real pluggability hole (adding a new source requires editing existing code)

## Findings

### Layer 1 — SearchModels foundation tier  ✅

`Search.SourceDefinition` + `Search.SourceProperties` + `Search.SourceLookup` carry every field the consumer layers need (`rankWeight`, `defaultDocKindRawValue`, `docKindRawValuesByID` computed). Defaults safe (`rankWeight` defaults to 1.0; `defaultDocKindRawValue` defaults to nil). No static literals shadow the registry path.

### Layer 2 — Per-source providers (8 sources)  ✅

Cross-referenced each `<X>Source.Definition.swift` against the pre-#1042 SmartQuery `sourceWeights` static literal: 5 sources declare explicit `rankWeight`, 3 inherit the default 1.0 (matching pre-#1042 values). All five sources that need a DocKind taxonomy declare `defaultDocKindRawValue`. AppleDocsSource correctly absents itself (bespoke classifier path in `classifyAppleDocs`). Sample / Packages correctly absent (they don't write `docs_metadata`).

`searchRoute` default = `.docs` on the protocol; HIG / Sample / Packages override.

### Layer 3 — SearchSQLite indexer + classifier  ✅

`Search.Classify.kind` threads `docKindByID` at both call sites in `Search.Index.IndexingDocs.swift` (L155, L498). Pinned by `Issue1045ProductionCallSiteTests.gap3_indexingDocsCallSiteThreadsDocKindDict`.

Legacy switch arms in `DocKind.swift:83-98` are dead for the 5 in-tree sources that declare a `defaultDocKindRawValue` (the dict short-circuit at L80 fires first); only the apple-docs arm + default-unknown remain live. Cleanup candidate but not behaviourally wrong.

Shared `apple-sample-code.db` file under `--clear` is safe by design: docs pipeline's `clearIndex()` only DELETEs `docs_fts` + `docs_metadata`; samples pipeline writes disjoint `samples_*` tables (separate schema_version per `Sample.Index.Defaults.swift:31` comment).

### Layer 4 — CLI command paths  ✅

Helper invocation matrix:

| Helper | Call sites | Pinned by grep test? |
| --- | --- | --- |
| `makeSmartQuerySourceWeights` | Search.swift L306 | ✓ |
| `makeFormatterAvailableSources` | SourceRunners ×3 + ListFrameworks ×1 | ✓ |
| `makeDocsIndexingDirectoryByKey` | Save.Indexers L118 | ✓ |
| `makeDocKindRawValuesByID` | 0 (consumed via `sourceLookup.docKindRawValuesByID`) | grep test pins the `docKindByID:` keyword at the threading site |

Single-fetcher SmartQuery at `Search.SourceRunners.swift:257` + `PackageSearch.swift:116` does not pass `sourceWeightsOverride`. Behaviourally inert (RRF over one input is degenerate per `PackageSearch.swift:90` comment); leaving alone.

### Layer 5 — MCP server path  ✅

`CLIImpl.Command.Serve.swift:213-221` derives both `searchToolSourceEnumValues` and `resourceProviderKnownSchemes` from `CLIImpl.makeProductionSourceRegistry()`. Adding a new source flows automatically into:
- MCP tool input-schema enum
- ResourceProvider URI-scheme acceptance set
- Unified-search formatter's "Searched ALL sources" header + footer tip
- Frameworks-listing footer

### Layer 6 — Services / Formatters / Footer rendering  ⚠

**Maintenance trap (no production impact today)**: `Shared.Constants.Search.availableSources` is a hardcoded 8-source `[String]` literal used as a `?? fallback` at 3 sites:
- `Services.Formatter.Footer.Search.swift:71`
- `Services.Formatter.Unified.Markdown.swift:69`
- `Services.Formatter.Unified.Text.swift:76`

All production callers (CLI + MCP) thread the registry-derived list and the fallback is dead-on-prod. Reachable today only by `Services.UnifiedSearcher`'s back-compat extension overload at L62-87 (forwards `availableSources: nil`), used by `ServicesModelsTests.swift:434` only.

**Risk**: a future PR that forgets to wire `availableSources` would silently omit the new source from the footer. Defensive fallback masks the wiring bug instead of failing loud.

**Proposed fix**: make `availableSources: [String]` non-optional on the formatter init surface; delete the static literal + the back-compat extension overload + update the test stub to construct the registry-derived list at fixture-build time.

Status: parked. Not blocking. File as separate issue for future ship.

### Layer 7 — Setup / ReleaseTool / Doctor  ❌ (2 real findings)

**Finding 7.1 — Doctor `healthChecks` array is hardcoded 3-entry list**
- File: `CLIImpl.Command.Doctor.swift:130-134`
- Shape: `[PackagesHealthCheck, SamplesHealthCheck, SearchHealthCheck]` — three conformers covering the *legacy* DB shape (packages.db / samples.db / search.db).
- Post-#1036 there are 7–8 per-source DBs (apple-documentation.db, hig.db, apple-archive.db, swift-evolution.db, swift-org.db, swift-book.db, apple-sample-code.db). None of these have a `DatabaseHealthCheck` conformer.
- Consequence: `cupertino doctor` doesn't actually health-check the per-source DBs. They appear in `printSchemaVersions` (Finding 7.2) but get no integrity / row-count / journal-mode probe.
- The #931 PR landed the strategy seam (`Distribution.DatabaseHealthCheck` protocol) but did not extend the conformer list to cover the per-source DBs.
- **Adding a new source per Source Independence Day**: would require a new `<X>HealthCheck` conformer + a new entry in this list. Two extra edits beyond the 2-file goal.

**Finding 7.2 — Doctor `printSchemaVersions` entries list is hardcoded 9-entry literal**
- File: `CLIImpl.Command.Doctor.swift:257-267`
- Shape: 9 `(DatabaseDescriptor, URL)` tuples literally enumerating every shipped DB.
- The function comment at L254 explicitly admits "Adding a new per-source DB: append one entry below." That is the 80% pluggability anti-pattern.
- **Adding a new source per Source Independence Day**: would require appending a tuple here. One extra edit beyond the 2-file goal.
- Proposed fix: derive from `CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.destinationDB)` plus the 2 special-case path resolvers (`.packages` → `paths.packagesDatabase`; `.appleSampleCode` → `Sample.Index.databasePath(baseDirectory:)`).

### Layer 8 — Tests cover all wirings  ⚠

`Issue930DatabaseHealthCheckTests` pins the *strategy seam* (every conformer iterated, isRequired policy correct). It does NOT pin the *coverage invariant* — no test asserts "every production `destinationDB` has a corresponding `Distribution.DatabaseHealthCheck` conformer in the `healthChecks` list". Same omission for `printSchemaVersions` (no test that registers a fake source + asserts the new descriptor appears in the output).

The existing `PluggabilityInvariantTests.closedSetSourcePrefixAllPrefixes` explicitly DOCUMENTS the `Shared.Constants.SourcePrefix.allPrefixes` closed-set gap as a regression marker for #932. The analogous `Shared.Constants.Search.availableSources` static fallback (Layer 6 maintenance trap) is NOT pinned as a closed-set marker — no equivalent test announces it as a known gap.

**Action**: when filing the Layer 7 issues, also propose a test that pins coverage invariance: register a fake source via a one-line registry append + assert both `healthChecks` and `printSchemaVersions` reflect the new source. Without this test, future PRs can ship a new source whose DB never appears in Doctor and CI stays green.

### Layer 9 — Hidden static literals + closed enums

**Finding 9.1 — `Search.SearchRoute` is a closed enum (5 cases)**
- File: `Packages/Sources/SearchModels/Search.SourceProvider.swift:134`
- A new source whose dispatch differs from `.docs / .hig / .samples / .packages / .unified` requires a new case here (plus the dispatcher switch).
- Pragmatic: `.unified` is the documented fallback for sources without bespoke routing — so adding a source does NOT require editing SearchRoute unless the new source needs its OWN dispatcher.
- Verdict: acceptable as designed; the closed enum is a deliberate dispatcher contract.

**Finding 9.2 — Dead static literals (production-safe; tests pin them)**
Three static `[X]` literals in Shared have **zero production callers** in `Packages/Sources/`:
- `Shared.Constants.SourcePrefix.allPrefixes` — pinned as a known closed-set gap by `PluggabilityInvariantTests.closedSetSourcePrefixAllPrefixes` (regression marker for #932). Production-side, replaced by `Search.SourceLookup.allIDs` per audit batch 2 (SearchSQLite `Search.Index.SearchByAttribute.swift:475` comment).
- `Shared.Constants.DisplayName.allSourceInfos` — unused in production.
- `Shared.Models.DatabaseDescriptor.allKnown` — referenced only by `ConstantsAuditTests`.
- **Verdict**: dead-on-prod, parked. Safe to cull in a follow-up cleanup but no behavioural risk today.

**Finding 9.7 — MAJOR: `cupertino fetch` source dispatch switch is hardcoded 10-arm**  ❌
- File: `CLIImpl.Command.Fetch.swift:226-260`
- Shape: a top-level `switch source` with 10 explicit arms — every shipped source enumerated, plus a `default:` ValidationError whose **message string also lists every source by name** at lines 255-258.
- Adding a new source therefore requires THREE edits in Fetch.swift alone:
  1. A new `case` arm in the dispatch switch.
  2. A new handler method (`run<X>Fetch` / `run<X>Crawl`).
  3. Update of the default error-message string listing valid sources.
- The Source Independence Day standard is "2-file PR, zero edits to existing concretes". This is a 3-edit-per-source hole and one of the bigger remaining gaps in the epic.
- **Proposed fix path**: lift the dispatch into a `Search.SourceProvider`-attached fetch strategy (or a `FetchService` strategy keyed on `fetchInfo`). The default `runStandardCrawl` already handles web-crawlable sources; the special handlers (`runPackageFetch`, `runHIGCrawl`, etc.) need to be lifted into per-source targets so the dispatcher becomes a `provider.makeFetchStrategy(...)` call.
- **Related**: the per-source handler methods (`runPackageFetch`, `runCodeFetch`, `runSamplesFetch`, `runArchiveCrawl`, `runHIGCrawl`, `runEvolutionCrawl`) themselves represent the un-pluggable per-source fetch logic. Today they live as private methods on `CLIImpl.Command.Fetch`. Adding a new source needs a new method here.

**Finding 9.8 — Minor: `Fetch.displayName(forSource:)` + `Fetch.defaultOutputDir(forSource:)` have hardcoded special-token switches**
- File: `CLIImpl.Command.Fetch.swift:320-324` + `:339-353`
- Each has a 3–4-case switch for "all" / "availability" / "apple-sample-code" before falling through to registry-derived lookup.
- These are SPECIAL TOKENS, not source providers — fan-out aliases + maintenance ops. A new source flows through the registry fall-through automatically (provider.fetchInfo.displayName / defaultOutputDirKey).
- Verdict: acceptable; the special-token list itself is small + stable.

### Layer 10 — Strategy plumbing (CandidateFetcher / EnrichmentRunner)  ✅ (mild observation)

**Finding 10.1 (mild)**: `CLIImpl.Command.Search.SmartReport.buildFetchers` has a hardcoded 3-way dispatch (docs / packages / samples). Each bucket has its own opener method (`openDocsFetchers` / `openPackagesFetcher` / `openSamplesFetcher`).

The 3-bucket split mirrors the 3-DB-family architecture (search-tier / packages.db / apple-sample-code.db). Adding a new source WITHIN one of those families is fully plug-and-play (`openDocsFetchers` iterates `Self.docsSources()` which is registry-derived). Adding a source with a brand-new DB family would need a 4th opener — an architectural change, not a routine addition.

`openDocsFetchers` itself is registry-aware (iterates `docsSources()` → registry filter). ✓

EnrichmentRunner is constructed per-DB with 3 generic passes (Synonyms / AppleConstraints / Hierarchy) — these are pipeline-wide, not source-specific. New sources reuse them; a hypothetical source needing its OWN pass would require a code edit here (acceptable tradeoff for a niche case).

### Layer 11 — Crawler / Fetcher / Importer paths  ❌ (depth of Finding 9.7)

**Finding 11.1 — Per-source crawler concretes live in cross-cutting Crawler/ package, not in `<X>Source/`**
- Files: `Packages/Sources/Crawler/Crawler.AppleArchive.swift`, `Crawler.AppleDocs.swift`, `Crawler.Evolution.swift`, `Crawler.HIG.swift`.
- For 100% source pluggability the crawler concrete for a source should ship INSIDE its `<X>Source` target. Today it ships in the shared Crawler package, and Fetch.swift's `run<X>Crawl` methods name them directly (e.g. `Crawler.AppleDocs(...)`, `Crawler.HIG(...)`).
- Files touched to add one new web-crawlable source today (rough lower bound):
  1. `Packages/Sources/<X>Source/<X>Source.swift` (provider definition)
  2. `Packages/Sources/<X>Source/<X>Source.Definition.swift` (rankWeight, docKind)
  3. `Packages/Sources/<X>Source/Search.Strategies.<X>.swift` (per-source strategy)
  4. `Packages/Sources/Crawler/Crawler.<X>.swift` (the crawler itself) ← lives outside the source target
  5. `Packages/Sources/CLI/Commands/CLIImpl.Command.Fetch.swift` (new dispatch case + new `run<X>Crawl` method) ← see 9.7
  6. `Packages/Sources/CLI/CLIImpl.SourceRegistry.swift` (one `.register(<X>Source())` line)
  7. `Packages/Package.swift` (target + testTarget declarations)
  8. `docs/sources/<id>/manifest.yaml` (descriptor)
- That's 8 file edits for one new web-crawlable source. The Source Independence Day target is 2.
- **Proposed fix path**: lift each crawler concrete into its `<X>Source` target; have `Search.SourceProvider` expose a `makeCrawler(env:)` (or `makeFetchStrategy(env:)`) method. Composition root invokes `provider.makeFetchStrategy(...)` instead of switching on source-id.

### Layer 12 — Manifest / scripts / CI  ⚠

**Finding 12.1 — `scripts/check-source-manifests.sh` has hardcoded allowlists**:
- `ALLOWED_FETCHER_KINDS=(apple-docs-api web-crawl git-clone http-archive github-api webkit-scrape file-bundle)` (7)
- `ALLOWED_SEARCHERS=(text symbols property-wrappers concurrency conformances generics package-search sample-files)` (8)
- `ALLOWED_OPERATIONS=...` (similar)
- Adding a new FETCHER KIND (not a new source — a new *type* of fetcher) requires editing this script. Per-fetcher-type pluggability is a different scope from per-source.
- Verdict: per-source-type pluggability hole, lower priority than per-source-id pluggability. Allowlist is small + stable.

CI workflow (`ci.yml`) does not hardcode a source list. ✓

### Layer 13 — Package.swift target topology  ✅

`allSourceTargetNames` (Package.swift:19-28) is hardcoded but the per-source target declaration is unavoidable SwiftPM ceremony — every package's Package.swift must enumerate its targets. The audit batch covered by `Issue1042PluggabilityContractTests` Cluster 14 already pins that test/binary targets use the helper, not 8 repeated lists. Adding a new source target to `allSourceTargetNames` + a new `.target(...)` declaration is the minimum Package.swift edit any new SPM target requires.

Distribution migrator (`Distribution.PerSourceDBSplitMigrator.swift:540-571`) is registry-aware (`registry.groupedByDestinationDB(excluding: [.packages, .search])`). ✓

### Layer 14 — SearchEval / hidden source-id switch dispatchers  ❌ (3 real findings)

**Finding 14.1 — `SaveSiblingGate` has hardcoded source-id switch**
- File: `Packages/Sources/CLI/Commands/SaveSiblingGate.swift:638-651`
- Shape: `switch sourceID { case "packages" → packages bucket | case "samples", "apple-sample-code" → samples+docs | case "apple-docs", "swift-evolution", "hig", "apple-archive", "swift-org", "swift-book" → docs }`
- Adding a new docs-tier source requires editing the 6-source list in the docs-bucket case.
- The classifier is "which save targets does this source-id touch?" — could be derived from each provider's `destinationDB` (everything not `.packages` and not `.appleSampleCode` is in the docs bucket).
- **Proposed fix path**: replace the literal switch with `registry.entry(for: sourceID)?.destinationDB`-based bucket classification.

**Finding 14.2 — `CLIImpl.Command.Search.run` has hardcoded source-id dispatch switch**
- File: `CLIImpl.Command.Search.swift:228-249`
- Shape: `switch source { case samples/appleSampleCode → runSampleSearch | case hig → runHIGSearch | case packages → runPackageSearch | case appleDocs/appleArchive/swiftEvolution/swiftOrg/swiftBook → runDocsSearch | default → runUnifiedSearch }`
- **This is exactly what `Search.SourceProvider.searchRoute` was designed to replace** (audit batch cluster 8). The provider declares `.docs / .hig / .samples / .packages / .unified`. The CLI dispatch SHOULD be `switch provider.searchRoute { ... }`.
- Today the seam exists but the production dispatch hasn't been refactored to consume it. Per-source-id switch still rules.
- **Proposed fix path**: replace the source-id switch with a `searchRoute`-based dispatch. The `Issue1042PluggabilityContractTests` cluster-8 contract test would then have a counterpart behavioural test asserting that a registered new source with `.searchRoute = .docs` flows into `runDocsSearch` automatically.

**Finding 14.3 — `Services.ReadService.resolveSource` has hardcoded 3-bucket dispatch switch**
- File: `Services/ReadCommands/Services.ReadService.swift:65-87`
- Shape: maps source-id to one of three `ReadService.Source` enum cases (`.docs / .samples / .packages`).
- Same shape, same fix: replace with `registry.entry(for: raw)?.searchRoute` mapping.

**Finding 14.4 — MCP `CompositeToolProvider.handleSearch` has hardcoded source-id dispatch switch** (mirror of 14.2)
- File: `Packages/Sources/SearchToolProvider/CompositeToolProvider.swift:631-687`
- Identical pattern to 14.2. The CLI and MCP paths both switch on source-id when they should switch on `searchRoute`. The provider has the seam; both consumers ignore it.

**Finding 14.5 — `Save.Indexers.resolveSourceDirectory` legacy switch has 5 dead arms post-Gap-4**
- File: `Save.Indexers.swift:482-509`
- Post-Gap-4 wiring, the dict path always supplies a non-nil URL for the 5 docs-tier sources (appleDocs / swiftEvolution / swiftOrg / appleArchive / hig). The legacy switch is only reached for the 2 sentinels (samples / swiftBook).
- **5 of the 8 switch arms are dead code in production today**. The dict resolution wins before the switch fires.
- Cleanup candidate: delete the 5 dead arms; keep the 2 sentinel arms + default. Even better: lift the sentinel-vs-real distinction into a `Search.SourceProvider.requiresInputDirectory` property so the switch dissolves entirely.

### Layer 15 — HOW-TO-ADD-A-SOURCE.md drift check  ❌ (major drift)

**Finding 15.1 — `docs/sources/HOW-TO-ADD-A-SOURCE.md` undercounts required edits**

The doc opens with "Required: the four lines that register a new source" (line 27) and lists 4 minimum edits. The actual minimum edit count today, after summing every Finding above, is **substantially higher** for a fully-integrated source. A realistic floor for a new web-crawlable source:

| # | Surface | Edit | Source of finding |
| - | --- | --- | --- |
| 1 | `Packages/Sources/<X>Source/<X>Source.swift` + 3-4 sibling files | new files | HOW-TO ✓ |
| 2 | `Packages/Package.swift` (`allSourceTargetNames` + `.target` + `.testTarget`) | 3 edits in 1 file | HOW-TO ✓ |
| 3 | `CLIImpl.SourceRegistry.swift` (`.register()` line) | 1 edit | HOW-TO ✓ |
| 4 | `Shared.Models.DatabaseDescriptor` (new descriptor + `allKnown` append) | 2 edits in 1 file | HOW-TO ✓ |
| 5 | `docs/sources/<id>/manifest.yaml` | 1 new file | HOW-TO ✓ |
| 6 | `CLIImpl.Command.Fetch.swift` (new `case` arm + new `run<X>Crawl` method + default-arm error string) | **3 edits in 1 file** | Finding 9.7 — UNDOCUMENTED in HOW-TO |
| 7 | `Packages/Sources/Crawler/Crawler.<X>.swift` (new crawler concrete) | 1 new file in cross-cutting Crawler package | Finding 11.1 — UNDOCUMENTED |
| 8 | `Packages/Sources/CLI/Commands/SaveSiblingGate.swift` (new `case` arm classifying the source-id into a target bucket) | 1 edit | Finding 14.1 — UNDOCUMENTED |
| 9 | `Packages/Sources/CLI/Commands/CLIImpl.Command.Search.swift` (new `case` arm in the search-route dispatch) | 1 edit | Finding 14.2 — UNDOCUMENTED |
| 10 | `Packages/Sources/Services/ReadCommands/Services.ReadService.swift` (new `case` arm) | 1 edit | Finding 14.3 — UNDOCUMENTED |
| 11 | `Packages/Sources/SearchToolProvider/CompositeToolProvider.swift` (MCP search dispatch new `case` arm) | 1 edit | Finding 14.4 — UNDOCUMENTED |
| 12 | `Packages/Sources/CLI/Commands/CLIImpl.Command.Doctor.<X>HealthCheck.swift` (new conformer) | 1 new file | Finding 7.1 — UNDOCUMENTED |
| 13 | `Packages/Sources/CLI/Commands/CLIImpl.Command.Doctor.swift` (`healthChecks` array append + `printSchemaVersions` entries-list append) | 2 edits | Findings 7.1 + 7.2 — UNDOCUMENTED |

**Total: 13+ file touches across 9+ different production files for one new source.** The HOW-TO claims "4 lines". The drift comes from:
1. The HOW-TO was authored mid-#1042 epic when the remaining holes were tracked in #1045's outstanding-edit list, then never updated when #1045 closed.
2. The "Still TODO" section (lines 9-13) still references `#1045` Acceptances #1-4 as open — but those closed today.
3. The HOW-TO completely OMITS the Doctor / Fetch / SaveSiblingGate / Search / ReadService / MCP dispatch holes — these never had #1042 cluster numbers because they were discovered post-audit.

**Action**: rewrite `HOW-TO-ADD-A-SOURCE.md` to honestly enumerate the 13+ edits, OR (preferred) close enough of the outstanding pluggability holes that the count drops back to ~4 and the doc becomes accurate. The discrepancy itself is the load-bearing signal: the doc captures the *aspirational* shape, not the present one.

## Cumulative findings ledger

| # | Layer | Severity | One-liner |
| - | --- | --- | --- |
| 6.0 | 6 | ⚠ maintenance trap | `Shared.Constants.Search.availableSources` static literal is the dead-on-prod fallback at 3 formatter sites. |
| 7.1 | 7 | ❌ real hole | `Doctor.healthChecks` is a hardcoded 3-conformer list; per-source DBs (apple-documentation.db, hig.db, …) have no health check. |
| 7.2 | 7 | ❌ real hole | `Doctor.printSchemaVersions` `entries` array is a hardcoded 9-tuple literal. |
| 8.0 | 8 | ⚠ test coverage | No test pins "every production destinationDB has a HealthCheck conformer". The strategy seam is tested; coverage invariance is not. |
| 9.7 | 9 | ❌ MAJOR hole | `cupertino fetch` source dispatch switch is a hardcoded 10-arm + a default-arm error message listing every source by name. 3 edits per new source in this file alone. |
| 11.1 | 11 | ❌ structural | Per-source crawler concretes live in cross-cutting `Crawler/` package, not in `<X>Source/`. Adds 1 file outside the source target. |
| 12.1 | 12 | ⚠ scripts | `scripts/check-source-manifests.sh` has hardcoded allowlists for fetcher kinds / searchers / operations. Per-fetcher-type pluggability hole, lower priority. |
| 14.1 | 14 | ❌ real hole | `SaveSiblingGate` source-id switch hardcoded 6-source docs list. |
| 14.2 | 14 | ❌ real hole | `CLIImpl.Command.Search.run` source-id dispatch switch (the `searchRoute` seam exists, dispatch still ignores it). |
| 14.3 | 14 | ❌ real hole | `Services.ReadService.resolveSource` source-id 3-bucket switch. |
| 14.4 | 14 | ❌ real hole | MCP `CompositeToolProvider.handleSearch` source-id dispatch switch (mirror of 14.2). |
| 14.5 | 14 | ⚠ dead arms | `Save.Indexers.resolveSourceDirectory` legacy switch has 5 arms that are dead post-Gap-4 wiring. |
| 15.1 | 15 | ❌ doc drift | `HOW-TO-ADD-A-SOURCE.md` claims 4-line edit; actual is 13+. The doc undercounts by ~3×. |

**Bottom line: Source Independence Day is ~70% landed.** The foundation (registry, provider protocol, per-source DBs, dict-supplied wirings for the 4 Gaps) is solid. The remaining ~30% lives in stale dispatch switches that pre-date the `searchRoute` seam (Findings 14.2 + 14.3 + 14.4 are the same regression in 3 different files) plus a few standalone holes (Doctor 7.1/7.2, Fetch 9.7, SaveSiblingGate 14.1, Crawler 11.1).

## Recommended issue carve-up

Group the findings into issues by *fix shape*, not by file:

- **Issue A** (already filed as #1048-style chore): Doctor pluggability — wire `healthChecks` + `printSchemaVersions` from the registry; add coverage-invariance test. Covers 7.1 + 7.2 + 8.0.
- **Issue B**: `searchRoute`-driven dispatch refactor — replace the source-id switches in `CLIImpl.Command.Search`, `Services.ReadService.resolveSource`, `CompositeToolProvider.handleSearch`, and `SaveSiblingGate` with `provider.searchRoute`-based dispatch. Covers 14.1 + 14.2 + 14.3 + 14.4.
- **Issue C**: Per-source fetch strategy — lift `Crawler.<X>` concretes into their `<X>Source` targets; add `provider.makeFetchStrategy(env:)` protocol method; collapse Fetch.swift's dispatch switch. Covers 9.7 + 11.1.
- **Issue D**: Strict `availableSources` — make the formatter param non-optional; delete the static fallback + back-compat overload. Covers 6.0.
- **Issue E** (low-priority polish): cull dead switch arms; remove `Shared.Constants.SourcePrefix.allPrefixes` + `allSourceInfos` + `allKnown` (dead-on-prod). Covers 9.2 + 14.5.
- **Issue F**: Rewrite `HOW-TO-ADD-A-SOURCE.md` after Issues A–C land, so the doc's edit-count claim matches reality.




## Action items — 2026-05-26 status

**8 of 9 findings closed in this audit's follow-up commits.**

- [x] **14.5** culled dead arms + closed latent `--docs-dir` override bug (`b3fa1b9f`).
- [x] **7.2** `printSchemaVersions` entries list registry-derived (`c3864911`).
- [x] **7.1** `Doctor.healthChecks` registry-derived; `SearchHealthCheck` parameterised on descriptor; coverage-invariance test pins the contract (`c3864911`).
- [x] **14.1** `SaveSiblingGate.classifyPostSplitSourceID` switches on `destinationDB` (`c3864911`).
- [x] **14.3** `Services.ReadService.resolveSource` consumes `destinationsByID` dict (`c3864911`).
- [x] **14.2** `CLIImpl.Command.Search.run` dispatches via `provider.searchRoute` (`05c4e5d5`).
- [x] **14.4** MCP `CompositeToolProvider.handleSearch` consumes `searchToolRoutesByID` dict; Serve composition root wires it; test fixture pulls canonical map from new `CupertinoComposition` target (`05c4e5d5`).
- [x] **6.0** formatter `availableSources` non-optional; `Shared.Constants.Search.availableSources` static + its companions deleted; all production callers thread registry-derived list (`2ff09a6e`).
- [x] **9.2** dead-on-prod `DisplayName.allSourceInfos` static deleted; `SourcePrefix.allPrefixes` + `DatabaseDescriptor.allKnown` kept as documentation lists with drift-detector tests that compare against the production registry (`2ff09a6e`).
- [x] **Architecture** new `CupertinoComposition` SPM target holds the single canonical `makeProductionSourceRegistry()` factory. CLI's `CLIImpl.makeProductionSourceRegistry()` and the `SearchToolProviderTests` fixture both delegate to it. Adding a new source = ONE `.register(<X>Source())` line in `Cupertino.CompositionRoot.swift`. All downstream consumers (Doctor, MCP, CLI dispatch, sibling-gate, read-service, formatters, drift-detector tests) pick up the new source automatically.

**1 remaining open finding** — too big to land in the same audit-close-out session, queued for a dedicated PR:

- [ ] **9.7 + 11.1** — `cupertino fetch` dispatch + per-source crawler concretes. The 10-arm switch in `Fetch.swift` plus the 4 `Crawler.<X>` files in the cross-cutting Crawler package need to lift into per-source `<X>Source` targets behind a new `Search.SourceProvider.makeFetchStrategy(...)` protocol method. Each existing `run<X>Crawl/Fetch` method (200-500 LOC each, heavy CLI-flag state coupling) needs to be extracted into a per-source strategy concrete. Full plan + step sequence at the new follow-up GitHub issue (to be filed).
  - Pluggability impact: adding a new web-crawlable source TODAY needs (a) new file in cross-cutting `Crawler/` package, (b) new case in `Fetch.swift` switch, (c) new `run<X>Crawl` method, (d) update to default-arm error-message string. After this fix lands: ONE provider with `makeFetchStrategy` returning a strategy concrete; zero edits to Fetch.swift or Crawler.
  - Scope: 12-20 file changes touching ~1500 LOC across Fetch.swift, the 4 Crawler.<X> files, and 4 per-source target files. Genuinely needs its own PR for review-ability.

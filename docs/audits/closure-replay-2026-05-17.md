# Closure Replay — 2026-05-17 (Stage A of ironclad sweep)

**Scope:** re-verify all 16 closures from session 2026-05-17 against the FULL acceptance criteria written in each issue's body. The "partial shipping" pattern that caused PR #729's #101 miss is the failure mode we are guarding against: closing on N-of-M acceptance bullets and assuming the rest came along.

**Method (applied to every issue below):**

1. `gh issue view <N> --json body,title,closed_at,comments` for the original acceptance text + the closing comment.
2. Extract **every** "Acceptance" / "Done when" / "Definition of Done" bullet — including the body's prose criteria if no explicit acceptance section exists.
3. For each bullet: map to specific file(s) + function(s) + test(s) named in the issue body OR in the merging PR description. Not single-keyword grep.
4. Probe the current state of develop with that map. Cite evidence (file:line, test name, grep output, CLI sample) — never "looks right".
5. Record verdict:
   - ✅ **Confirmed closed** — every bullet met, evidence cited
   - 🔄 **Reopen** — one or more bullets unmet
   - 🟡 **Partial-shipping (documented)** — some bullets met, remaining scope explicitly named inline + (where applicable) new follow-up issue filed; closure stands

**Canonical DB state at replay time:**

```
sqlite3 ~/.cupertino/search.db
  → frameworks: 420
  → docs:       285735
  → user_version: 13 (v1.0.2 ship state — note the brew DB has not yet ingested the v1.2.0-staged reindex)
```

This matters: 3 of the substantive closures (#77, #668, #626) are **reindex-gated** — the code shipped but the live DB still reflects pre-fix state until the v1.2.0 bundle is regenerated and `cupertino setup` brings it down. Those are flagged for explicit re-assertion in the v1.2.0 release ceremony.

---

## Results table

| # | Title (truncated) | Verdict | Notes |
|---|---|---|---|
| #708 | multi-term FTS5 AND-collapse | ✅ Confirmed closed | False positive on corrupt DB; canonical DB returns 6 results, top scores match closing comment |
| #709 | class-reference page ranking miss | ✅ Confirmed closed | False positive; top-1 `VNRecognizeTextRequest` score 17,901.97 matches closing |
| #715 | over-precise multi-term low-score | ✅ Confirmed closed | False positive; top-1 `Canvas` score 1853.19 matches closing |
| #719 | SwiftUI class-reference docs sparse | ✅ Confirmed closed | False positive; 4 named symbols all return top-1 canonical class-ref pages |
| #225 | Index Swift language version | ✅ Confirmed closed | Part A (#716) + Part B (#718); 7 bullets all met. `--swift` flag landed on unified `search` (natural successor to `ask`) |
| **#226** | **MCP --platform / --min-version** | **🔄 REOPEN** | **Bullets 2 (required-together validation) + 3 (MCP `info.platform_filter_partial` field) NEVER shipped** |
| #275 | doctor --freshness | ✅ Confirmed closed | 3 design Qs resolved, 6 tests, per-flag doc, CHANGELOG; brew binary v1.1.0 doesn't expose yet (staged for v1.2.0 bundle) |
| #665 | search_generics MCP tool | ✅ Confirmed closed | 5 bullets met; tools/list bumped 11→12, 21 tests across 3 files |
| #113 | doc:// → https:// rewriter | ✅ Confirmed closed | 6 bullets met; CHANGELOG section header drift (1.1.0 → 1.2.0) is cosmetic |
| #194 | embedded swift-packages drop | 🟡 Partial-shipping (documented) | 568 KB binary bloat removed (load-bearing goal); accessor neutered to empty `[]` instead of deleted — design pivot documented in closing comment + CoreProtocols docstring |
| #722 | SaveSiblingGate --force-replace | ✅ Confirmed closed | --force-replace half fully shipped (24 tests); --from-setup half formally scoped out via scope-finding comment (legitimate scope reduction) |
| **#77** | **CamelCase token-boundary expansion** | **🔄 REOPEN** | **Bullet 6 (re-index time benchmarked + recorded in CHANGELOG) UNMET** — only index-size impact recorded, not wall-clock |
| #668 | docs_structured coverage HIG/Evolution/Archive | 🟡 Partial-shipping (reindex-gated) | Code wiring + 5 tests done; live `(missing)` rate unverifiable until v1.2.0 reindex ships. **v1.2.0 ceremony must re-assert** |
| #626 | kind=unknown reduction | 🟡 Partial-shipping (reindex-gated) | Three-tier cascade + 17 tests done; <30% target unverified on live DB (still 57.2%). **v1.2.0 ceremony must re-assert** |
| #409 | AST is_public + generic_params | ✅ Confirmed closed | Layer 1 (is_public repurpose, #663) + Layer 2 (search_generics, #707) + follow-up (#721); 21 truth-table tests |
| #624 | /cupertino-test-everything skill | ✅ Confirmed closed | Cross-repo deliverable at `mihaela-agents/skills/cupertino/test-everything/SKILL.md` (875 lines); all 7 named bullets implemented, exceeds spec |

**Net:**
- ✅ 11 confirmed closed
- 🟡 3 partial-shipping documented (one process pivot + two reindex-gated)
- 🔄 **2 reopened** (#226, #77)

That's a **2-in-16 false-closure rate (12.5%)**. Matches the #101 miss pattern (closed on partial-acceptance evidence). The replay caught the slip, which is the point of Stage A.

---

## Findings on the audit methodology itself

1. **Single-keyword grep is insufficient.** The #226 miss was visible only because the agent ran `grep -rn "platform_filter_partial"` and got **zero matches anywhere** — that's the kind of probe that catches "shipped under a different name" vs "didn't ship at all." A weaker probe ("look in CompositeToolProvider for platform handling") would have found the schema-axis work and stopped.

2. **CHANGELOG benchmarks are a separate kind of acceptance.** The #77 miss was "we recorded *index-size* impact but the bullet asked for *wall-clock re-index time*." Both are "stats in the CHANGELOG"; the audit must distinguish.

3. **Reindex-gated closures are a recurring pattern.** #668, #626 (and parts of #77, #225, #275, #409) all ship code that takes effect only after a fresh `cupertino save --docs`. The v1.2.0 release ceremony is the natural re-assertion point. Without that re-assertion, a partial-shipping closure stays unverified forever.

4. **Cross-repo closures (#624) require explicit cross-repo verification.** First-pass audits don't cross repo boundaries; deep pass does. Add this to the closure protocol (Stage E).

5. **Scope reductions can be legitimate.** #722's `--from-setup` half and #194's "neuter don't delete" path were both formally scoped-out with honest closing comments. Distinguishing this from silent scope abandonment requires the closing comment to NAME the dropped acceptance bullets, not just describe what shipped.

---

## Per-issue detail

### False-positive batch (#708, #709, #715, #719)

#### #708 — search: multi-term query returns zero hits when FTS5 AND-mode finds no single page with all tokens

**Field report symptom:** `cupertino search "MKMapView MKAnnotation MapKit" --source apple-docs` returned nothing on the (corrupted) brew bundle while single-term `MapKit` returned only Maps capability / location-testing docs.

**Closing rationale:** Local `~/.cupertino/search.db` was corrupt (160 MB, 21,701 docs / 37 frameworks — no mapkit framework at all) from an earlier runaway-save incident, not a real FTS5 AND-collapse bug.

**Replay against canonical DB:**
- Query: `cupertino search 'MKMapView MKAnnotation MapKit' --source apple-docs`
- Result: **Found 6 result(s)**. Top hits: `MKOverlay` (mapkit, score 216.91), `mapView(_:selectionAccessoryFor:)` (mapkit, score 72.36), `mapView(_:viewFor:)` (mapkit, score 72.24). All three tokens co-occur on canonical mapkit pages.

**Verdict:** ✅ Confirmed closed. Evidence: https://github.com/mihaelamj/cupertino/issues/708 closing comment.

#### #709 — ranking: direct class-reference pages miss while sample-project listings dominate

**Field report symptom:** `VNRecognizeTextRequest` lookup returned the visionOS `vision-detecting-objects-in-still-images` sample-project page instead of the canonical class-reference page.

**Replay against canonical DB:**
- Query: `cupertino search 'VNRecognizeTextRequest' --source apple-docs`
- Result: **Found 4 result(s)**. Top-1: `VNRecognizeTextRequest` (vision, score **17901.97**) — the canonical class-reference page. Score gap to #2 is two orders of magnitude.

**Verdict:** ✅ Confirmed closed.

#### #715 — search: over-precise multi-term queries return low-score irrelevant results

**Field report symptom:** `cupertino search 'Canvas SwiftUI GraphicsContext drawing'` returned `Module Aliasing` (score 0.0246) and `docc/Step` (0.0242) — both irrelevant.

**Replay against canonical DB:**
- Query 1 (apple-docs only): Top-1 `Canvas | Apple Developer Documentation` (swiftui, score **1853.19**), top-2 `GraphicsContext` (swiftui, score 493.31).
- Query 2 (default fan-out): Top-1 still `Canvas` (apple-docs source). Original noise gone.

**Verdict:** ✅ Confirmed closed.

#### #719 — corpus: SwiftUI class-reference docs are sparse in apple-docs index

**Field report symptom:** Chapter-writing agent claimed SwiftUI class-references missing; `GeometryReader`/`GeometryProxy` zero hits.

**Replay against canonical DB:**
- `GeometryReader` → 7 results, top-1 `GeometryReader` (swiftui, score **63669.12**)
- `GeometryProxy` → 20 results, top-1 (swiftui, score **57985.17**)
- `NavigationStack` → 20 results, top-1 (swiftui, score **6438.03**)
- `matchedGeometryEffect` → 4 results, top-1 `MatchedGeometryProperties` (213.20), canonical method at rank 2 (186.45)

All four scores in the closing comment match my replay exactly.

**Verdict:** ✅ Confirmed closed.

---

### Substantive batch — confirmed closures

#### #225 — Index Swift language version

7 acceptance bullets across Part A (packages.db swift_tools_version) and Part B (search.db implementation_swift_version). All 7 verified:
- Part A: schema column at `Search/PackageIndex.swift:254`; migration v2→v3 at `:333-342`; regex parser at `ASTIndexer.AvailabilityParsers.swift:65`; `--swift-tools` flag on package-search at `CLIImpl.Command.PackageSearch.swift:69`
- Part B: column added in migration v15→v16 at `Search.Index.Migrations.swift:227-240`; both markdown parser forms covered at `Search.StrategyHelpers.swift:191-219`; Evolution strategy populates at `Search.Strategies.SwiftEvolution.swift:199-231`; `--swift` flag at `CLIImpl.Command.Search.swift:133`

**Note:** acceptance bullet 7 mentioned `ask` command — `ask` was unified into `search`, so the flag lives on the successor command. Documented inline in the issue closure (not silent).

**Verdict:** ✅ Confirmed closed. PRs: #716 (Part A), #718 (Part B).

#### #275 — doctor --freshness

3 design questions resolved + implementation:
- Q1 (signal): per-source crawledAt distribution with nearest-rank quantiles — `Diagnostics.Probes.swift:188-234`
- Q2 (surface): `cupertino doctor --freshness` sub-flag — `CLIImpl.Command.Doctor.swift:105`
- Q3 (semantics): raw Int64 epoch only, no thresholds — `Diagnostics.Probes.swift:248-256`
- Implementation: 6 tests in `Issue275FreshnessProbeTests.swift:29`; per-flag doc at `docs/commands/doctor/option (--)/freshness.md`

**Note:** brew v1.1.0 binary doesn't yet expose `--freshness` — staged for v1.2.0 bundle. CHANGELOG documents.

**Verdict:** ✅ Confirmed closed. PR: #693.

#### #665 — search_generics MCP tool

5 bullets all met:
- Tool registered at `CompositeToolProvider.swift:415-417`; constant at `Shared.Constants.swift:680 (toolSearchGenerics = "search_generics")`
- 21 truth-table tests across `Issue665SearchByGenericConstraintTests.swift`, `Issue665SearchGenericsMCPMarkerTests.swift`, `Issue665PlatformFilterFollowupTests.swift`
- tools/list count bumped 11→12 (`Issue645ToolsListHonestyTests.swift:100`)
- Swift API: `Search.Index.SemanticSearch.swift:518-560`

**Verdict:** ✅ Confirmed closed. PRs: #707 (base), #721 (platform-filter follow-up).

#### #113 — doc:// → https:// rewriter

6 bullets met:
- Rewriter at `Search.Index.DocLinkRewriter.swift:36`; wired at `Search.Index.IndexingDocs.swift:32, :43, :421, :423`
- 16 unit sub-tests in `Issue113DocLinkRewriterTests.swift`
- Audit log emission at `Search.Index.IndexingDocs.swift:45-56`, pinned by `Issue113AuditCountEmissionTests` (4 tests via CapturingRecording)
- Post-save sweep test at `Issue113IndexerRewriteIntegrationTests.swift:154`; 5 E2E sub-tests
- CHANGELOG entry at line 31, 33 (under "Unreleased — staged for 1.2.0" — section renumbered post-issue-filing)

**Verdict:** ✅ Confirmed closed. PRs: #710 (base), #712 (audit-count follow-up).

#### #722 — SaveSiblingGate --force-replace

Substantive half (`--force-replace`) fully shipped: typed-confirmation gate, --yes bypass, SIGTERM→30s-grace→SIGKILL termination ladder, post-kill verification, `Action.forceReplaceSiblings` + `TerminationOutcome` enums, 24 tests across 6 suites in `Issue722ForceReplaceTests.swift`, per-flag docs at `docs/commands/save/option (--)/force-replace.md` + `force-replace-grace.md`.

`--from-setup` half was formally scoped-out via [scope-finding comment](https://github.com/mihaelamj/cupertino/issues/722#issuecomment-4468563722): no setup→save subprocess invocation exists in the codebase. Legitimate scope reduction with re-file hook.

**Verdict:** ✅ Confirmed closed. PR: #725.

#### #409 — AST is_public + generic_params

3 bullets met:
- Layer 1 (is_public repurpose for apple-docs rows): `Search.Index.IndexingDocs.swift:727-746` — option (b) from the issue body
- Layer 2 (search_generics MCP tool): `CompositeToolProvider.swift:276 (props), :418 (registration)`
- 21 truth-table tests across 3 files
- Bullet 3 (CLI tip text) was conditional on "if a new search command lands" — work shipped as MCP-only, so condition didn't trigger

**Verdict:** ✅ Confirmed closed. PRs: #663 (Layer 1), #707 (Layer 2 base), #721 (Layer 2 follow-up).

#### #624 — /cupertino-test-everything skill

7 named acceptance points all implemented in 875-line SKILL.md at `mihaela-agents/skills/cupertino/test-everything/SKILL.md`:
- 10-step pipeline (Steps 1-9 + Step 10 conditional on `--deep`); exceeds named 10 (adds 3a, 3b, 8b, 8c, 9b, 11)
- PASS/FAIL per step + final verdict at lines 808-827
- Markdown report to `~/Downloads/cupertino-test-everything-<date>.md`
- `--deep` adds 3 specific audits (lines 788-798): canonical-type wrong-winner (45 types), BUG 5 multi-URI scope (15 URIs), search→read round-trip on top-50
- `--no-clean` skips clean (lines 16, 70)
- Exit code 0/1 per result (line 815-822, 826)

Cross-repo deliverable; 4 commits cited (`2fac2ed`, `38bfe26`, `6cd81cc`, `0c00742`).

**Verdict:** ✅ Confirmed closed.

---

### Partial-shipping batch (documented, closure stands)

#### #194 — Eliminate bundled swift-packages URL list once packages.db is primary

**5 acceptance bullets; 2 of 5 explicit closure path, 3 of 5 formally pivoted:**

| # | Bullet | Status |
|---|---|---|
| 1 | Delete `SwiftPackagesCatalogEmbedded.swift` | ✅ deleted |
| 2 | Delete `Core.Protocols.SwiftPackagesCatalog.swift` accessor | 🟡 neutered to empty `[]` (lines 92-114), not deleted |
| 3 | Rewrite callers to read from `packages.db` directly | 🟡 not rewritten — callers get empty results; TUI banner + `guard !packages.isEmpty` skip cover empty-state UX |
| 4 | Drop `SwiftPackageEntry` struct | 🟡 retained for empty-contract test pin |
| 5 | Remove swift-packages case from generator | ✅ `scripts/generate-embedded-catalogs.sh:77-80` skip block |

**Closure-comment honesty:** the deferred scope is named explicitly ("Core.Protocols.SwiftPackagesCatalog.loadEntries returns empty unconditionally"). Empty-contract pinned by `CoreProtocolsTests.swift:123`. The 568 KB binary-bloat goal (the load-bearing purpose) is met.

**Recommended follow-up:** file new issue tracking eventual deletion of the neutered accessor + caller rewrite. The CoreProtocols docstring at lines 99-104 already names the rewire-from-packages.db work as a pending sub-PR.

**Verdict:** 🟡 Partial-shipping documented. PR: #711.

#### #668 — docs_structured coverage for HIG/Evolution/Archive (reindex-gated)

**3 acceptance bullets:**

| # | Bullet | Status |
|---|---|---|
| 1 | Identify indexer path for 3 sources | ✅ HIG / SwiftEvolution / AppleArchive strategies all call `Search.StrategyHelpers.makeArticleStructuredPage(...)` |
| 2 | Wire through `indexStructuredDocument` | ✅ all 3 switched from `indexDocument` to `indexStructuredDocument` (lines 145, 155, 222); 5 tests in `Issue668DocsStructuredCoverageTests.swift` |
| 3 | `(missing)` rate drops to single digits per `cupertino doctor --kind-coverage` | 🟡 **reindex-gated** — live v1.1.0 DB still shows zero rows for the 3 sources; closing comment promises "on next v1.2.0 reindex" |

**Verdict:** 🟡 Partial-shipping. Code in place; bullet 3 needs the v1.2.0 reindex to assert.

**v1.2.0 release ceremony action item:** after the reindex bundle ships, run `cupertino doctor --kind-coverage` and confirm `(missing)` rate <10% for archive/hig/evolution. If not, reopen.

#### #626 — kind=unknown reduction (reindex-gated)

**3 acceptance bullets:**

| # | Bullet | Status |
|---|---|---|
| 1 | Unknown rate <30% post-reindex | 🟡 live DB still 57.2% (162,820 / 284,518) — reindex-gated; closing comment projects "57% → ~19%" |
| 2 | #616 HEURISTIC 1.6 boost fires on more pages | 🟡 implied by bullet 1; observable post-reindex |
| 3 | Regression tests cover new extraction paths | ✅ 17 `@Test` directives in `Issue626KindExtractionExpansionTests.swift`; three-tier cascade at `Core.JSONParser.AppleJSONToMarkdown.swift:585-588`; new Kind enum cases at `Shared.Models.StructuredDocumentationPage.swift:174-178` |

**v1.2.0 release ceremony action item:** confirm unknown rate <30% on reindexed bundle.

**Verdict:** 🟡 Partial-shipping.

---

### REOPEN batch (action required this session)

#### #226 — MCP --platform / --min-version with cross-source notice 🔄

**4 acceptance bullets; 2 of 4 unmet:**

| # | Bullet | Status |
|---|---|---|
| 1 | `platform` (enum) + `min_version` (string) params on search-style tools | 🟡 schema-axis shipped as 5 separate `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` fields — functionally equivalent shape, but different from the issue's `platform + min_version` pair |
| 2 | **Required-together validation; one without the other rejected at param validation with a clear MCP error** | ❌ **UNMET** — no required-together validation; each min_* field is independently optional |
| 3 | **Response surfacing: `info.platform_filter_partial` field with `filtered_sources`/`unfiltered_sources` for cross-source notice** | ❌ **UNMET** — zero matches for `platform_filter_partial` / `filtered_sources` / `unfiltered_sources` anywhere in `Packages/Sources/`. CLI has the notice (`SmartReport.swift:54-57, 419-425`); MCP layer does not. This is exactly the cross-source signal the issue body called out as "the load-bearing piece for AI clients" |
| 4 | Coverage on all 5 in-scope tools | ✅ all 5 search-style tools (search + 3 AST tools + search_generics) merge in `platformFilterProperties`; pinned by `Issue665PlatformFilterFollowupTests` |

**Reopen rationale:** The schema-axis half shipped; the validation + cross-source-notice half did not. The closure assumed PR #706 + #721 fully delivered #226 because the platform filter on the schema was visible — the more subtle bullets (validation, info-field) were missed exactly like #101's duplicate-constant fold-in.

**Remaining scope for re-close:**
- Add required-together MCP error when one of (`platform`, `min_version`) is present without the other (or, in the shipped shape, when any `min_*` field is present without the corresponding platform — needs a design decision).
- Add `info` field to tool response with `platform_filter_partial` code + `filtered_sources` / `unfiltered_sources` when the response contains rows from sources that don't honour the filter.
- Tests pin both behaviors.

#### #77 — CamelCase token-boundary expansion 🔄

**6 acceptance bullets; 1 of 6 unmet:**

| # | Bullet | Status |
|---|---|---|
| 1 | `search("grid")` returns LazyVGrid above rank-cliff | 🟡 reindex-gated — symbol_components column absent on v13 DB; verifiable post-v1.2.0 |
| 2 | `search("session")` returns URLSession above rank-cliff | 🟡 same — reindex-gated |
| 3 | `search("LazyVGrid")` exact-match unchanged | ✅ top-1 score 60,793 |
| 4 | BM25F weights documented in code | ✅ `Search.Index.Search.swift:102-121` (symbols=5.0 vs symbol_components=1.5 rationale) |
| 5 | AST extractor tests cover URLSession/JSONDecoder/HTTPSCookieStorage/XMLParser | ✅ `Issue77CamelCaseSplitterTests.swift:38-41` parametrised test |
| 6 | **Re-index time benchmarked + recorded in CHANGELOG** | ❌ **UNMET** — CHANGELOG records index-SIZE impact (~10% docs_fts growth) but no wall-clock re-index DURATION. The bullet is explicit: "Re-index time benchmarked, recorded in CHANGELOG." |

**Reopen rationale:** bullet 6 is the kind of acceptance that's easy to miss because the CHANGELOG entry IS in the file — it just doesn't carry the data the bullet requires. Same audit-pattern as #226: shape-level verification passed, content-level missed.

**Remaining scope for re-close:** run a clean `cupertino save --docs` against the canonical corpus on a standard reference machine, record wall-clock duration in CHANGELOG under the #77 entry. Probably 30 min - 2h of work + 6-12h elapsed for the reindex itself.

**Note on bullets 1 + 2:** these are also reindex-gated; the v1.2.0 release ceremony should re-assert them once the new bundle is in `~/.cupertino/`.

---

## Stage A summary

**Restored trust in 11 closures, exposed 2 false closures + 3 reindex-gated partial-shippings.**

The 2 false closures (#226, #77) followed the same pattern as #101: the visible half of the acceptance criteria shipped, the more subtle half was missed in the closing comment's "looks done" judgment.

The 3 reindex-gated partial-shippings (#668, #626, #77-bullets-1+2) are a release-ceremony shape, not a methodology failure — the code is in place but the live DB hasn't ingested it. They are tracked here as explicit action items for the v1.2.0 release ceremony.

**Action items from Stage A:**
1. Reopen #226 with the precise unmet-bullet findings (validation + cross-source info field)
2. Reopen #77 with the precise unmet-bullet finding (CHANGELOG wall-clock duration)
3. File new follow-up issue for #194's eventual accessor deletion + caller rewrite (the explicit deferred scope from the closing comment)
4. v1.2.0 release ceremony to add: `cupertino doctor --kind-coverage` check (covers #668, #626, the live-DB half of #77 bullets 1+2)

**Next stages:**
- **Stage B** (older closures sample): defer until after release ceremony — Stage A's recent-closures sample yielded a 12.5% false-closure rate, so the older-closures pool is likely to surface similar issues; doing it during release prep is too costly.
- **Stage C** (open-issue currency probe): ready to run; the 53 still-open issues + #226/#77 reopens = 55 issues to walk.
- **Stage D** (regression locks): inputs ready — the 11 confirmed-closed issues from Stage A are the lock candidates.
- **Stage E** (process changes): closure-protocol template should encode the patterns from this audit's "Findings on the audit methodology itself" section.

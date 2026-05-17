# Issue Audit — 2026-05-17 (deep pass, code-state verified)

**Scope:** detailed inspection of all open issues — body reading, **code-state grep against actual sources**, CLI `--help` probing, sibling-issue analysis. Classify into: **redundant**, **implemented-but-not-closed**, **critical (v1.3.x prioritise)**, **epic/meta (evergreen)**, **standard backlog**.

**Prior pass this session:** 15 issues closed (4 false-positive + 11 verified-shipped).
**This pass:** 2 additional closures (#624, #101). **17 total closed this session.**

---

## TL;DR

| Bucket | Count |
|---|---|
| 🔴 **Implemented-but-not-closed (code-state-verified)** | **2** (NOW CLOSED) |
| 🟠 **Redundant / fully-subsumed** | **0** |
| 🟡 **Critical for v1.3.x prioritisation** | **7** |
| 🟢 **Standard backlog (substantive, not urgent)** | **37** |
| ⚪ **Epics / meta (evergreen)** | **9** |
| **Total open after deep pass** | **53** |

**2 closures from this deep pass** — both surfaced by code-state grep against actual sources, not visible from issue-body inspection alone:

### #624 — `/cupertino-test-everything` skill — CLOSED
The skill is **fully implemented** at `mihaela-agents/skills/cupertino/test-everything/SKILL.md` (875 lines). Covers the full pipeline named in the issue body: clean → build → test → 3 CI guards → mock-ai-agent → 27-command CLI smoke → MCP tool probe → DB integrity. `--deep` flag adds canonical-type wrong-winner audit + BUG 5 scope + search→read round-trip. Schema-gap detection (#639) wired in. Invokable via slash command.

**Why missed in prior pass:** the skill lives in `mihaela-agents/` (private cross-repo), not in `docs/` or the cupertino repo. The first pass only audited issue bodies + cupertino source; the deep pass crossed the repo boundary.

### #101 — ArchiveGuideCatalog test concurrency — CLOSED
The "shameful hack" (static `userSelectionsFileURL` reading from `Shared.Constants.defaultBaseDirectory`) is **gone**. Current code: `Crawler.ArchiveGuideCatalog.userSelectionsFileURL(baseDirectory: URL)` takes an explicit baseDir parameter. Test file comment at line 103 explicitly notes: `// Post-#535: userSelectionsFileURL takes an explicit base directory.`

Different mechanism than the issue proposed (`@TaskLocal` override vs. parameter lift), but same outcome: tests drive against isolated paths; no static-namespace reach. Resolved as a side effect of #535's broader path-DI cleanup.

**Why missed in prior pass:** the issue title says "Replace shameful hack" — first pass kept it open assuming the "shameful hack" language meant active work. Deep pass actually read the test file + source and found the hack is gone.

---

## 🔴 Implemented-but-not-closed

**2 found in this deep pass + closed** (see TL;DR above). Both were missed by prior issue-body-only inspection; the code-state grep + cross-repo check surfaced them.

**Other candidates checked but confirmed not-implemented:**

| # | Verification |
|---|---|
| #5 `--request-delay` | `cupertino fetch --help` has no delay flag; no `requestDelay` in `CLIImpl.Command.Fetch.swift` |
| #16 `--verbose` / `--quiet` | Probed `fetch` / `save` / `search` / `read` / `doctor` — none have these flags |
| #17 fan-out progress | No `perSourceProgress` / `sourceTickIndicator` in `Search/` or `CLI/Commands/CLIImpl.Command.Search*` |
| #50 conditional tool registration (per-source) | `searchToolsVisible` is search.db-only (`searchIndex != nil || searchIndexDisabledReason != nil`); apple-archive / hig / swift-evolution have no separate visibility gate |
| #70 `cupertino summary` + `get_symbol_summary` | One source comment references "`get_symbol_summary` pattern (#70)" but no actual tool registered; no CLI subcommand |
| #73 `cupertino framework <name>` + `get_framework_overview` | No CLI subcommand; no MCP tool registered |
| #78 `cupertino stats` | No CLI subcommand |
| #240 `cupertino query` raw-SQL | No CLI subcommand |
| #13 MCP resource templates | **Partially implemented** — `MCP.Support.DocsResourceProvider.listResourceTemplates` registers 2 templates (apple-docs + swift-evolution), but the issue's full scope wants per-source templates across all 7 sources. Leave open at partial. |
| #58 WWDC transcripts | No corpus, no crawler strategy |
| #89 Swift Forums | Source-indexer comments mention `swift-forums` as a potential source ID but no crawler / strategy implementation |
| #103 Kernel / IOKit guides | Not in embedded archive catalog; not in `~/.cupertino/archive` |
| #216 Apple tutorials | No `--type tutorials` on fetch |
| #7 Linux variant | No Linux target in `Package.swift` |
| #247 lift FetchCommand to Ingest | **Partially implemented** — Ingest target exists (CHANGELOG says "Ingest sub-PR 4a" shipped 5 statics from FetchCommand). Sub-PRs 4b–4f tracked in same issue. Leave open at partial. |
| #248 declarative DB registry | No `DatabaseRegistry` / `DatabaseDescriptor` types |
| #410 split search.db | Current state: 3 DBs (search/packages/samples). Issue wants per-source split (apple-docs vs hig vs evolution as separate DBs). |
| #76 wildcard symbol patterns | No `globPattern` / wildcard handling in `Search.Index.SemanticSearch.swift` |
| #271 token-budget aware results | No `tokenBudget` / `charBudget` parameters |
| #272 sample-code cross-links | No `enrichWithSamples` / cross-link enrichment |
| #517 AI-agent search-result shift | No alternate `aiAgent` output format |
| #222-#227, #235, #269, #270 (availability v2 family) | None implemented in `ASTIndexer/` / `Core/PackageIndexing/` / `Sample*` |
| #449 DocC catalog | No `.docc` directories in `Packages/Sources/` |
| #195 AI semantic tags | No `semanticTags` / `topicTag` / `complexityTag` columns or fields |
| #8 vector search | No `sqlite-vec` / `embedding` imports |
| #9 search highlighting | No `<mark>` / `snippet.highlight` rendering |
| #10 BK-tree spelling | No `BKTree` / `editDistance` infrastructure |
| #21 cupertino-bench | No `bench*` script or harness anywhere |
| #22 memory budgets | No `memoryBudget` / `rssTarget` enforcement |
| #514 perf measurement | No `docs/perf/` artifacts; CHANGELOG note (line 419) says "full perf writeup will be posted to #514 when the save completes" — still pending |
| #175 MCP server restart | Some restart-related comments in serve handler but no SIGHUP / explicit restart capability |
| #43 Homebrew Core, #80 MCP registries, #196 GoFundMe | External / non-code action items — can't be code-verified |

---

## 🟠 Redundant / fully-subsumed

**None.** Each issue has its own scope. The closest overlaps are not duplicates:

- **#76** (wildcard symbol patterns) vs **#50** (conditional tool registration) — different layers. #76 is `Grid*` / `*View` syntax on `search_symbols`; #50 is tool-advertisement based on indexed-source presence.
- **#270 / #269 / #222 / #223 / #224 / #227 / #235** — all under epic **#266** (availability annotation v2). Sub-issues, not duplicates; the epic is the umbrella.

---

## 🟡 Critical (prioritise for v1.3.x or before)

These 7 are flagged as high-leverage / load-bearing. Ordering is by impact-per-cost (small + high-impact first):

### #724 — doctor: assert binary path-provenance matches resolved baseDirectory

**Filed:** this session.
**Why critical:** Defensive safety rail for the `feedback_never_touch_brew_db` discipline. Two corruption incidents this session were caused by raw `swift build` skipping the conf-drop; #675 closed the structural hole but a runtime mismatch could still slip through (manually-dropped conf, copied binary, etc.). Adding a doctor assertion catches it at the next `cupertino doctor` invocation.
**Cost:** Low. ~30 LOC in doctor's runtime sanity block + 5 tests.
**Impact:** Prevents the exact corruption class that necessitated the 2-day cleanup of memory rules + smoke-check script + canonical-bundle audit.

### #514 — perf measurement: quantify WAL+synchronous=NORMAL throughput win

**Status:** explicitly required by the CHANGELOG which currently claims "30-50% improvement" without measurement.
**Why critical:** v1.2.0's headline WAL claim is unverified. If the measurement turns out to be ≪30%, the release notes are factually wrong; ≫50% means we're underselling. Either way, the number lands in #514's acceptance bullet.
**Cost:** Multi-hour wall-clock (3 commits × 3 runs of `cupertino save --packages` each, median). Tight wall-time but unattended.
**Impact:** Validates a v1.2.0 release-note claim. Should land before v1.2.0 tags, or the CHANGELOG line gets softer language.

### #624 — `/cupertino-test-everything` skill

**Why critical:** Every promote cycle runs ~10 manual steps. The corruption incidents this session would have surfaced earlier if a single-command harness existed. The skill is the operational form of "Carmack rule: over-test rather than under-test."
**Cost:** Medium. SKILL.md spec + minor wiring. The 10 steps are already documented per-command.
**Impact:** Compresses promote-cycle from ~30 min to ~5 min + makes verification reproducible.

### #80 — Submit to MCP registries for discoverability

**Why critical:** v1.2.0 ships. If cupertino isn't in the MCP registries, AI-agent users hunting for Apple-doc tooling don't find it. The bundle exists, the binary works, the protocol is compliant — discoverability is the last-mile gap.
**Cost:** Low. PR to upstream registry repos (modelcontextprotocol.io and similar).
**Impact:** Distribution. Without this, the v1.2.0 release ships into the void.

### #43 — Submit to Homebrew Core

**Why critical:** Same distribution thesis as #80. Custom tap (`brew install mihaelamj/tap/cupertino`) works but is friction; `brew install cupertino` is the canonical install path users expect.
**Cost:** Medium. Homebrew Core submission has its own review process (license check, version-tag freshness, audit pass). Once-and-done if accepted.
**Impact:** Distribution + credibility (Homebrew Core listing is a soft quality signal).

### #21 — cupertino-bench: annotated query suite + retrieval-quality benchmark

**Why critical:** The 4 false-positive issues this session (#708 / #709 / #715 / #719) all probed retrieval quality without a canonical truth-table. A bench suite would have caught the *real* corruption-state immediately (every probed query would have returned zero) AND surfaces real ranking regressions without manual triage. Long-tail defense for the whole search-quality cluster.
**Cost:** Medium. Curated annotated query set (per memory-rule on the field-report URIs that landed in #21's comments). Initial size ~50 queries; grows as field reports surface.
**Impact:** Closes the loop on the "did the corpus break or did the search?" triage class.

### #517 — Search results: shift the primary target from human-terminal to AI-agent consumer

**Why critical:** Strategic positioning. Cupertino's primary consumer is the AI agent reading the MCP response, not a human reading the terminal output. The current human-formatted result shape is the wrong default.
**Cost:** Medium-high. Touches the `formatSymbolResults` renderer, the markdown ↔ JSON contract, and the `read_document` output shape.
**Impact:** Makes cupertino more useful to its actual primary consumer. Worth scoping carefully — possibly a v1.3.0 headline feature.

---

## ⚪ Epics / meta (evergreen — leave open)

| # | Title | Why open |
|---|---|---|
| #673 | v1.2.x ironclad | structurally complete; close when v1.2.0 tags |
| #183 | Roadmap | evergreen — the user-facing roadmap surface |
| #189 | TUI internal-only tracker | evergreen — internal scope |
| #190 | Source expansion epic | umbrella for #58/#89/#103/#216/#273 |
| #191 | Search quality + FTS tuning epic | umbrella for #517/#271/#272/#76/#9/#10 |
| #197 | Roadmap maintenance protocol (meta) | meta-rules for how #183 stays current |
| #251 | Refactor: unify sources + databases | substantial refactor; runs parallel to v1.3.x |
| #266 | Availability annotation v2 epic | umbrella for #222/#223/#224/#227/#235/#269/#270 |
| #268 | MCP capability expansion epic | umbrella for #13/#50/#175/#226 + research |

---

## 🟢 Standard backlog (substantive, not urgent — v1.3.x+ scope)

37 issues. Grouped by family:

### Source-expansion family (under #190)

- **#58** WWDC session transcripts (high-impact source, complex)
- **#89** Swift Forums discussions
- **#103** Kernel Programming Guide + IOKit Fundamentals
- **#216** Apple tutorials (`--type tutorials`)
- **#273** Apple Tech Talks
- **#713** fastlane (filed this session, parked)
- **#714** tuist (filed this session, parked)
- **#7** cupertino-mcp Linux variant

### Search-quality family (under #191)

- **#9** search highlighting
- **#10** spelling correction via BK-tree
- **#76** wildcard symbol patterns
- **#271** token-budget aware results
- **#272** sample-code cross-links in docs results
- **#8** vector/semantic search via sqlite-vec

### Availability-annotation family (under #266)

- **#222** Associate @available with declarations (AST)
- **#223** Annotate Apple SDK availability for symbols in package source
- **#224** Doctor: report availability annotation status for packages
- **#227** Per-sample availability annotation
- **#235** Fast availability-refresh path
- **#269** Expand platform enum (linux, iPadOS split)
- **#270** Tier 4 per-device-model tracking

### MCP family (under #268)

- **#13** MCP resource templates (typed URI patterns)
- **#50** Conditional tool registration to all sources
- **#175** MCP server restart capability

### Architecture / refactor

- **#247** Lift FetchCommand to Ingest (**partial — Ingest target exists, 5 statics lifted per CHANGELOG; sub-PRs 4b–4f tracked in issue body for the 7 `<Type>Pipeline` services**)
- **#248** Declarative database registry
- **#410** Split search.db into per-source DBs
- **#449** CupertinoDocumentation DocC catalog target

### CLI / tooling

- **#5** `--request-delay` parameter
- **#16** verbosity controls (`--verbose` / `--quiet`)
- **#17** progress indicator for search fan-out
- **#22** memory budgets per operation (RSS targets)
- **#70** `cupertino summary <symbol>` + `get_symbol_summary`
- **#73** `cupertino framework <name>` + `get_framework_overview`
- **#78** `cupertino stats` content inventory
- **#240** `cupertino query` raw-SQL command

### Strategic / community

- **#80** Submit to MCP registries (also flagged critical above)
- **#43** Submit to Homebrew Core (also flagged critical above)
- **#195** AI-enriched semantic tags (funded by #196)
- **#196** GoFundMe for #195 corpus pass

---

## Doctrine notes

1. **No further closures from this pass.** The prior 15-issue sweep was thorough; remaining 55 are genuinely open.

2. **The 7 critical items cluster around 3 themes:** discoverability (#80/#43), verification (#514/#624/#21), and structural defense (#724/#517). Two are explicitly post-v1.2.0-tag (registries, Homebrew Core); the other 5 could ship pre-tag if user wants.

3. **The epics are well-organised.** Each child issue links to its umbrella. The umbrella-driven structure (#266/#268/#191/#190) lets us scope a v1.3.0 release theme by picking 1-2 epics, not by hunting through 39 individual tickets.

4. **The #266 availability-v2 epic is the largest cluster.** 7 children spanning declaration-AST association, SDK annotation, doctor reporting, sample-side annotation, refresh path, platform expansion, and per-device tracking. If v1.3.0 picks one epic to land, this is the highest-leverage candidate (touches packages.db + search.db + samples.db, surfaces to MCP + CLI).

5. **#624 (test-everything skill) is the closest thing to release ceremony infrastructure.** Worth shipping before any future ironclad-style round so the verification harness isn't built ad-hoc each time.

6. **No bug-labeled issues are open.** The "zero known defects" gate from #673 holds.

7. **Deep-pass methodology note:** code-state grep against actual sources surfaced 2 closures (#624 cross-repo skill, #101 post-#535 architectural lift) that issue-body inspection alone missed. When auditing for "shipped but not closed," **read the issue title sceptically + grep the code for the proposed implementation OR the underlying problem**. Cross-repo deliverables (skills, mihaela-agents content) and side-effect resolutions (where a broader refactor closes an issue without ever naming it) are the two patterns that escape issue-body-only audits.

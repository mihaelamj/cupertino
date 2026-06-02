# Issue-by-issue relevance audit + epic organization (2026-06-02)

Full sweep of every open issue on the tracker: a relevance verdict for each, and a complete organization of the backlog into epics. Successor to `issue-merit-audit-2026-05-21.md` and `issue-priority-2026-05-29.md`.

## Method

Every open issue was read (title, `## Status` block, problem statement) and judged on two axes:

- **Relevance**: is it still real, or stale/done/superseded?
  - `KEEP`: valid, actionable now
  - `GATED`: valid but blocked on a phase, dependency, or re-index
  - `DEFERRED`: valid but parked by an explicit maintainer decision
  - `DORMANT`: valid but intentionally not scheduled
  - `CLOSEABLE`: done or superseded; close it
- **Epic**: which epic owns it (existing epic, or one of the new epics defined below).

Counts at audit time: 97 open issues after closing #1184 (fixed in PR #1183) and #1071 (resolved by the v1.3.0 release) during this audit.

### Limitations (read before trusting a verdict)

This is **triage from each issue's own `## Status` block + problem statement, not a code-verified audit.** A `KEEP` here means "the issue still reads as valid," not "independently confirmed against the codebase." Verdicts marked `CLOSEABLE` were checked against concrete evidence (#1184 against PR #1183, #1071 against `databaseVersion`, #748 against the shipped README's acceptance criteria); the rest were not re-verified against code. Treat the table as a routing map, not a correctness guarantee. Per-issue code verification is a separate, heavier pass.

The epic grouping is **prose membership** recorded in epic bodies + this doc; GitHub has no machine-readable parent/child link here, so a newly filed issue is an orphan until manually claimed. Several epics are deliberately thin (2 to 4 members) and exist as routing buckets, not large bodies of work. Cross-references noted as "(cross-ref X)" mean a second epic touches the issue; the bolded epic in the membership list is the single owner.

## Epic taxonomy

### Existing epics (kept; orphans claimed below)

| Epic | Title | Status |
|---|---|---|
| **#190** | Source expansion | live (was gated on #251, now closed; re-home under #190) |
| **#191** | Search quality + FTS tuning | partial (most v1.2.0 work shipped; eval + ranking tail open) |
| **#266** | Availability annotation v2 | live |
| **#268** | MCP capability expansion | live (keystone #742) |
| **#769** | Layer separation | live (9 children, none started) |
| **#1036** | Per-source DB split | partial (only #1061 left) |
| **#189** | TUI internal tracker | dormant (internal-only) |

Closed during the prior session as complete/superseded: **#943** (query batteries), **#251** (unify sources + databases).

### New epics (created 2026-06-02, then corrected)

> The first cut created nine new epic issues. The same-day first-principles review (see the Revision section at the end) found that five of them were *categories*, not coordinated initiatives, and closed them. Only the four below survive as epics. (A `topical:` label axis briefly introduced to replace the categories was itself reverted the same day; see the Revision section.) The membership lists for the five closed ones are retained below for the record.

| New epic | Title | North-star phase |
|---|---|---|
| **#1221** | Recrawl: resumable + measured re-index | recrawl |
| **#1222** | Linux port (runtime then indexing) | (parallel) |
| **#1223** | Declarative pluggability (Source Independence Day cont.) | (parallel) |
| **#1228** | Semantic & vector search | vector |

Closed as categories: **#1220** (bug sweep; bugs use the `bug` label), **#1224** (CLI), **#1225** (diagnostics), **#1226** (docs), **#1227** (distribution: two standalone issues). None warranted an epic.

## Epic membership

- **#190 Source expansion**: #58 (WWDC), #89 (Swift Forums), #103 (Kernel/IOKit archive), #216 (tutorials), #273 (Tech Talks), #713 (fastlane+tuist), #892 (xcodebuild), #957 (community packages corpus)
- **#191 Search quality + FTS**: #9 (highlighting), #10 (BK-tree spelling), #21 (cupertino-bench), #792 (regression comparator), #816 (anti-hallucination eval), #817 (eval harness relocation), #818 (synonyms at ranking), #819 (symbol-attribute filters), #820 (design-vocab routing), #821 (prose BM25F profile), #822 (TREC pooling)
- **#266 Availability annotation v2**: #222, #223, #224, #227, #235, #269 (linux+iPadOS enum), #270 (tier-4 device model)
- **#268 MCP capability expansion**: #13 (resource templates), #50 (conditional registration), #70 (summary), #73 (framework overview), #76 (wildcard symbols), #175 (server restart), #271 (token-budget), #272 (sample cross-links), #517 (AI-agent consumer), #742 (diagnostic keystone), #1178 (desktop E2E), #1208 (list-documents), #1210 (document children), #1212 (initialize.instructions)
- **#769 Layer separation**: #247, #770, #771, #772, #773, #774, #775, #776, #777, #778
- **#1036 Per-source DB split**: #1061 (drop `docs_metadata.source`)
- **#1221 Recrawl** (epic): #1146 (`--resume`, DONE #1148), #514 (WAL measurement), #800 (quadratic throughput), #22 (memory budgets)
- **#1222 Linux port** (epic): #1151 (indexing + `linux` axis), #1152 (runtime read/serve)
- **#1223 Declarative pluggability** (epic): #248 (DB registry), #962 (CLI from MCP registry), #965 (AST tools DB-pluggable), #1075 (enrichment seam), #730 (delete neutered accessor), #909 (audit-script consistency)
- **`bug` label** (was #1220, closed): empty. All closed: #1041 (#1243), #1132 (#1240), #1200 (#1202), #1201 (#1203)
- **CLI area** (was #1224, closed): #16 (verbosity), #17 (search progress), #78 (stats), #240 (raw SQL query), #801 (build number), #885 (setup --force hint)
- **Diagnostics area** (was #1225, closed): #724 (path-provenance), #1161 (os.log subsystem docs), #1162 (serve warning to stderr), #1163 (logging cleanup), #1209 (doctor per-source uniform)
- **Docs area** (was #1226, closed): #449 (DocC catalog), #1048 (code-comment + DocC), #1054 (HOW-TO-ADD-A-SOURCE rewrite), #1175 (recommend Homebrew)
- **distribution (standalone, was #1227, closed)**: #43 (Homebrew Core), #80 (MCP registries)
- **#1228 Semantic & vector search**: #8 (sqlite-vec), #195 (AI semantic tags), #196 (GoFundMe for tags pass)
- **Standalone (no epic)**: #183 (the roadmap itself), #197 (roadmap maintenance protocol)

## Relevance verdicts (per issue)

| # | Verdict | Epic | Note |
|---|---|---|---|
| 8 | GATED | #1228 | vector phase; needs design before pickup |
| 9 | KEEP | 191 | FTS5 `highlight()` unused |
| 10 | GATED | 191 | depends on vocabulary; no impl |
| 13 | KEEP | 268 | 2/9 templates shipped |
| 16 | KEEP | cli | no impl |
| 17 | KEEP | cli | fan-out exists, no reporter |
| 21 | KEEP | 191 | Phase A liftable today |
| 22 | DEFERRED | #1221 | no impl; perf budget |
| 43 | KEEP | distribution | stability criterion now met |
| 50 | KEEP | 268 | conditional tool registration |
| 58 | GATED | 190 | was #251-blocked (now closed) |
| 70 | KEEP | 268 | data already in schema |
| 73 | KEEP | 268 | data already in schema |
| 76 | KEEP | 268 | search_symbols extension |
| 78 | KEEP | cli | no content-inventory CLI |
| 80 | KEEP | distribution | 2/4 registries live |
| 89 | GATED | 190 | source-expansion child |
| 103 | GATED | 190 | source-expansion child |
| 175 | KEEP | 268 | serve restart on DB refresh |
| 183 | KEEP | standalone | the roadmap |
| 189 | DORMANT | 189 | internal TUI tracker |
| 195 | GATED | #1228 | gated on #196 funding |
| 196 | DEFERRED | #1228 | funding holding-pattern; re-cost vs Haiku 4.5 |
| 197 | CLOSED | standalone | protocol documented in `docs/roadmap-maintenance-protocol.md`; body was stale |
| 216 | GATED | 190 | tutorials source |
| 222 | KEEP | 266 | AST decl association |
| 223 | KEEP | 266 | Apple SDK availability for symbols |
| 224 | KEEP | 266 | doctor coverage for packages |
| 227 | KEEP | 266 | dual-axis split remaining |
| 235 | KEEP | 266 | fast refresh (cross-ref #1221) |
| 240 | KEEP | cli | raw SQL surface (post-#239) |
| 247 | KEEP | 769 | partial; 7 pipelines unlifted |
| 248 | KEEP | #1223 | DatabaseRegistry seam unbuilt |
| 266 | EPIC | 266 | availability v2 |
| 268 | EPIC | 268 | MCP capability |
| 269 | KEEP | 266 | platform enum (cross-ref #1222) |
| 270 | DEFERRED | 266 | tier-4 device model |
| 271 | GATED | 268 | needs #742 diagnostic block |
| 272 | KEEP | 268 | sample cross-links |
| 273 | GATED | 190 | Tech Talks source |
| 449 | KEEP | docs | no DocC catalog yet |
| 514 | KEEP | #1221 | docs-workload measurement remaining |
| 517 | GATED | 268 | needs #21 + #742 |
| 713 | GATED | 190 | tools source |
| 724 | KEEP | diagnostics | path-provenance safety rail |
| 730 | KEEP | #1223 | post-#194 cleanup |
| 742 | KEEP | 268 | Phase 2.1 keystone (high pri) |
| 748 | CLOSEABLE | docs | dual-consumer README shipped 2026-06-01 (verify + close) |
| 769 | EPIC | 769 | layer separation |
| 770 | KEEP | 769 | handoff contract |
| 771 | GATED | 769 | blocked on #770 |
| 772 | GATED | 769 | target pkg re-choice post-#1056 |
| 773 | GATED | 769 | blocked on #772 |
| 774 | GATED | 769 | blocked on #770/#771 |
| 775 | GATED | 769 | blocked on #773/#774 |
| 776 | GATED | 769 | blocked on #773/#774 |
| 777 | KEEP | 769 | indexer recovery pass |
| 778 | KEEP | 769 | post-processor CLI |
| 792 | KEEP | 191 | regression comparator |
| 800 | DEFERRED | #1221 | deferred per maintainer 2026-05-19 |
| 801 | KEEP | cli | build-number in --version |
| 816 | KEEP | 191 | the actual release-blocker eval |
| 817 | CLOSED | 191 | done: harnesses now in `scripts/eval/` (phase1-5 + lib + smokes) |
| 818 | KEEP | 191 | worst class baseline (18%) |
| 819 | KEEP | 191 | symbol-attribute filters |
| 820 | KEEP | 191 | HIG/archive routing |
| 821 | KEEP | 191 | prose weight profile |
| 822 | KEEP | 191 | human qrels research |
| 885 | KEEP | cli | setup --force hint |
| 892 | GATED | 190 | xcodebuild source |
| 909 | KEEP | #1223 | audit-script consistency |
| 957 | KEEP | 190 | community packages corpus |
| 962 | KEEP | #1223 | derive CLI from MCP registry |
| 965 | KEEP | #1223 | AST tools DB-pluggable |
| 1036 | EPIC | 1036 | per-source DB split |
| 1041 | CLOSED | bug | fixed by #1243: framework-scoped caveat + README numbers refreshed |
| 1048 | KEEP | docs | comment cleanup + DocC |
| 1054 | CLOSED | docs | ALREADY DONE: doc rewritten in #1056; stale framing gone |
| 1061 | KEEP | 1036 | drop source column |
| 1075 | CLOSED | #1223 | premature placeholder (N/A until a second source joins); refile then |
| 1132 | CLOSED | bug | synonyms attach (22 >=20); synonymsAttached test re-enabled + green (#1240) |
| 1146 | CLOSED | #1221 | done (#1148); documented + closed as-built (#1245) |
| 1151 | GATED | #1222 | Linux indexing + `linux` axis |
| 1152 | KEEP | #1222 | Linux runtime read/serve |
| 1161 | CLOSED | diagnostics | ALREADY FIXED by #1164 (docs commit my fix-scan regex missed) |
| 1162 | KEEP | diagnostics | serve warning to stderr |
| 1163 | PARTIAL | diagnostics | item 1 (SampleIndex subsystem) fixed; items 2,3 remain |
| 1175 | KEEP | docs | recommend Homebrew first |
| 1178 | KEEP | 268 | UNBLOCKED: #1168 closed, serve --base-dir exists; actionable now |
| 1200 | CLOSED | bug | ALREADY FIXED by PR #1202 (`c721cf79`); audit-1 verdict was wrong |
| 1201 | CLOSED | bug | ALREADY FIXED by PR #1203 (`eb587a28`); audit-1 verdict was wrong |
| 1208 | KEEP | 268 | list-documents tool |
| 1209 | KEEP | diagnostics | doctor per-source uniform |
| 1210 | KEEP | 268 | document children tree |
| 1212 | KEEP | 268 | initialize.instructions |

Closed during this audit: **#1184** (fixed in PR #1183), **#1071** (resolved by v1.3.0), **#748** (dual-consumer README shipped), and during the first-principles cleanup pass: **#197** (protocol documented + body stale), **#817** (harnesses relocated), **#1075** (premature placeholder). Plus the 5 category-epics demoted to labels (see Revision).

## Recommended execution order

1. **Bugs** (north-star: bugs; `bug` label). The bug list is now empty: #1041 (#1243), #1132 (#1240), #1200 (#1202), #1201 (#1203) all closed.
2. **#1221 recrawl** (north-star: recrawl). #1146 (`--resume`) is the enabler and already in progress.
3. **#742** keystone, then the **#268** MCP-capability fan-out it unblocks.
4. **#1228 semantic & vector** (north-star: vector) follows the diagnostic surface.
5. Parallel tracks: epics **#1222** Linux, **#1223** pluggability; the cli, diagnostics, docs, and distribution issues (no epic; e.g. #43 / #80). Pick up opportunistically.

## Quick wins (closeable or near-trivial)

- **#748**: dual-consumer README shipped 2026-06-01; verified against 5/6 acceptance criteria and closed.
- **#1200**, **#1201**: one-file fixes from the docs/commands audit.
- **#1175**: README install-ordering one-liner.

## Revision (2026-06-02, post-critique): epic vs label, then the label axis reverted

This organization went through three honest steps in one day.

**Step 1, first cut (wrong primitive):** nine epic *issues* were created to represent categories. A bare category is not a coordinated initiative, so it should not be an epic.

**Step 2, the "use labels" correction:** categories were moved to a `topical:` label axis (the axis `github-discipline.md` defines but had never built), applied to 93 issues. Reasoning: a label is queryable and travels with the issue, where prose membership in an epic body rots.

**Step 3, resolution of the open question (the label axis reverted):** Step 2 assumed area-routing is a consumed need. It is not. Evidence gathered 2026-06-02: no workflow, script, or doc routes issues by area; the decision surfaces that pre-date the experiment are this audit's parent roadmap #183 (phase-sequenced) plus the `bug` / `priority: high` / `epic` labels; the GH project board is phase-organized. With no consumer and no auto-labeler, the axis would decay into an inconsistent half-state, which is worse than none. So the 9 topical labels were **deleted**. The principle that justified them ("structure only where it changes a decision") is the same principle that removes them once the decision-relevance is shown absent. Plain area words in the Epic column above are descriptive, not labels.

Net actions that stand:

- **Closed 5 category-epics** (#1220 bug sweep, #1224 CLI, #1225 diagnostics, #1226 docs, #1227 distribution): categories, not coordinated work. Bugs are tracked by the `bug` label; the rest are plain enhancements.
- Removed the `epic` label from #742 (the keystone *under* #268, not a peer epic).
- **Decision surfaces:** #183 phases + `bug` / `priority: high` / `epic`. No topical axis.

**Surviving epics (11)**, reserved for coordinated multi-step work: #189 (TUI, dormant), #190 (source expansion), #191 (search quality), #266 (availability v2), #268 (MCP capability), #769 (layer separation), #1036 (per-source DB split), #1221 (recrawl), #1222 (Linux), #1223 (declarative pluggability), #1228 (semantic + vector).

### Verification policy

This audit is triage, not a code-verified pass (see Limitations). A full speculative code-verification of all ~95 issues is the wrong investment: most will not be touched soon. The policy is **verify at pickup**: when an issue is about to be worked, build/grep/read it against the current code to confirm its `KEEP` verdict still holds, and only then. The verdicts here route work; they do not certify it.

## Re-audit (2026-06-02, code-verified)

The first pass (above) was triage from issue status blocks. This pass verified central claims against `origin/develop` with grep / file / schema checks and a commit-history scan, not self-reports. Method and findings:

**Biggest finding: FOUR issues were already fixed/done but never closed.** The status-block pass (and several later references in this session) wrongly treated them as open:

- **#1200** (list_samples empty input schema): fixed by PR #1202, commit `c721cf79`. `toolListSamples` advertises `listSamplesProperties`; the empty `[:]` at the adjacent line belongs to `list_frameworks`. **Closed.**
- **#1201** (save --help stale text): fixed by PR #1203, commit `eb587a28`. The lists are registry-generated; the stale sentence is gone. **Closed.**
- **#1161** (wrong os.log subsystem in docs): fixed by PR #1164, commit `4d23c370`. README + design doc now use `com.cupertino.cli`. **Closed.**
- **#1054** (HOW-TO-ADD-A-SOURCE rewrite): done in #1056; the doc opens with "Required: the two files" (not the stale "four lines"), no #1045-open framing remains. **Closed.**
- Plus **#1163** is **partial**: item 1 (SampleIndex stray subsystem) is fixed; items 2 (dead `transport` category) and 3 (untested subsystem) remain, so it stays open.

**Correction to my own completeness claim.** I first scanned commit subjects for `fix/feat/close/resolve(#N)` and concluded "no other open issue has a merged fix." That was **wrong**, with two blind spots: (1) the regex missed other conventional prefixes, so it missed #1161's `docs(#1161)` fix; (2) a commit-subject scan cannot catch a fix that does not cite the issue number at all (#1054 was fixed by #1056; #1163 item 1 by an uncited change) -- only reading the code finds those. The reliable method is the per-issue code grep, not the commit scan. The commit scan's one residual hit is **#962** (partial: option parity shipped, auto-generated subcommands not).

**Then I did grep all the remaining planning issues** (2026-06-02). Confirmed genuinely not-implemented (premise holds, valid), by area:
- Sources: #58 / #89 / #216 / #273 / #713 / #892 (no `<X>Source` target).
- Layer separation: #770-#778 (no `cupertino-crawler` / `-indexer` / `-postprocessor` targets, no `CoreCrawler` / `CoreIndexer` split, no CI standalone-binary job, no handoff-contract doc).
- Availability: #222 / #235 / #269 (no `.linux`/`.iPadOS` case) / #270.
- Search / eval: #8 / #10 / #21 / #195 / #70 / #73 / #76 / #271 / #272 / #742 / #816 / #818 / #819 / #821; #17 (the `ProgressReporter` that exists is RemoteSync download progress, not a search-fan-out reporter).
- MCP: #1208 / #1210 / #1212 / #13 (no `variables` field); #50 + #965 (single `searchIndex`, not a registry).
- CLI / diagnostics: #16 / #78 / #240 / #801 / #885 / #248 / #730 / #449 / #724 / #1209 (`--docs-dir`/`--evolution-dir` still present).
- Linux: #1151 / #1152 (only a linuxbrew PATH string exists; no `#if os(Linux)` support).

**Honest scope + caveats:**

- Not greppable, left as TRIAGE: #43 / #80 (external submissions; #80 partial, no `server.json` so the GitHub MCP Registry submission is absent, the two live badges are in the README), #196 (funding), #517 (a framing decision), #822 (research), #800 (deferred perf).
- **Second sweep (2026-06-02) corrected three earlier punts**: (a) **#1178** is UNBLOCKED, not gated, its blocker #1168 is CLOSED so `serve --base-dir` exists; (b) **#1132** was claimed "needs a DB" then punted, but a read-only SELECT on the snapshot `apple-documentation.db` shows `framework_aliases` has 340 rows with 22 non-empty synonyms (the "7 rows / 0 synonyms" body is stale; only the test re-enable remains); (c) **#1041** was "file path not located" but the formatter is `ServicesModels/Formatters/Services.Formatter.Frameworks.Text.swift` and still emits the plain label, so VERIFIED valid. Lesson: "not greppable" and "file not found" were laziness, not real limits.
- **#1146** (`--resume`) has no implementation on `origin/develop`; its "in progress" status is true only on an unmerged feature branch. The README/#1221 diagram labels it "in progress", accurate for the branch, not the trunk.
- Naive keyword greps produced false positives ("stats" in a JSON parser, "restart" in a comment, #1212's match being the mock client, #17's reporter being RemoteSync's); every PRESENT was re-checked with exact tokens + line context.

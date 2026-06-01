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

### New epics (created 2026-06-02)

| New epic | Title | North-star phase |
|---|---|---|
| **#1220** | v1.3.x bug sweep & correctness | bugs |
| **#1221** | Recrawl: resumable + measured re-index | recrawl |
| **#1222** | Linux port (runtime then indexing) | (parallel) |
| **#1223** | Declarative pluggability (Source Independence Day cont.) | (parallel) |
| **#1224** | CLI ergonomics & observability | (parallel) |
| **#1225** | Diagnostics & logging | (parallel) |
| **#1226** | Docs & DocC | (parallel) |
| **#1227** | Distribution & discoverability | (parallel) |
| **#1228** | Semantic & vector search | vector |

## Epic membership

- **#190 Source expansion**: #58 (WWDC), #89 (Swift Forums), #103 (Kernel/IOKit archive), #216 (tutorials), #273 (Tech Talks), #713 (fastlane+tuist), #892 (xcodebuild), #957 (community packages corpus)
- **#191 Search quality + FTS**: #9 (highlighting), #10 (BK-tree spelling), #21 (cupertino-bench), #792 (regression comparator), #816 (anti-hallucination eval), #817 (eval harness relocation), #818 (synonyms at ranking), #819 (symbol-attribute filters), #820 (design-vocab routing), #821 (prose BM25F profile), #822 (TREC pooling)
- **#266 Availability annotation v2**: #222, #223, #224, #227, #235, #269 (linux+iPadOS enum), #270 (tier-4 device model)
- **#268 MCP capability expansion**: #13 (resource templates), #50 (conditional registration), #70 (summary), #73 (framework overview), #76 (wildcard symbols), #175 (server restart), #271 (token-budget), #272 (sample cross-links), #517 (AI-agent consumer), #742 (diagnostic keystone), #1178 (desktop E2E), #1208 (list-documents), #1210 (document children), #1212 (initialize.instructions)
- **#769 Layer separation**: #247, #770, #771, #772, #773, #774, #775, #776, #777, #778
- **#1036 Per-source DB split**: #1061 (drop `docs_metadata.source`)
- **#1220 Bug sweep**: #1041, #1132 (recrawl-gated), #1200, #1201
- **#1221 Recrawl**: #1146 (`--resume`, in progress), #514 (WAL measurement), #800 (quadratic throughput), #22 (memory budgets)
- **#1222 Linux port**: #1151 (indexing + `linux` axis), #1152 (runtime read/serve)
- **#1223 Declarative pluggability**: #248 (DB registry), #962 (CLI from MCP registry), #965 (AST tools DB-pluggable), #1075 (enrichment seam), #730 (delete neutered accessor), #909 (audit-script consistency)
- **#1224 CLI ergonomics & observability**: #16 (verbosity), #17 (search progress), #78 (stats), #240 (raw SQL query), #801 (build number), #885 (setup --force hint)
- **#1225 Diagnostics & logging**: #724 (path-provenance), #1161 (os.log subsystem docs), #1162 (serve warning to stderr), #1163 (logging cleanup), #1209 (doctor per-source uniform)
- **#1226 Docs & DocC**: #449 (DocC catalog), #1048 (code-comment + DocC), #1054 (HOW-TO-ADD-A-SOURCE rewrite), #1175 (recommend Homebrew)
- **#1227 Distribution & discoverability**: #43 (Homebrew Core), #80 (MCP registries)
- **#1228 Semantic & vector search**: #8 (sqlite-vec), #195 (AI semantic tags), #196 (GoFundMe for tags pass)
- **Standalone (no epic)**: #183 (the roadmap itself), #197 (roadmap maintenance protocol)

## Relevance verdicts (per issue)

| # | Verdict | Epic | Note |
|---|---|---|---|
| 8 | GATED | #1228 | vector phase; needs design before pickup |
| 9 | KEEP | 191 | FTS5 `highlight()` unused |
| 10 | GATED | 191 | depends on vocabulary; no impl |
| 13 | KEEP | 268 | 2/9 templates shipped |
| 16 | KEEP | #1224 | no impl |
| 17 | KEEP | #1224 | fan-out exists, no reporter |
| 21 | KEEP | 191 | Phase A liftable today |
| 22 | DEFERRED | #1221 | no impl; perf budget |
| 43 | KEEP | #1227 | stability criterion now met |
| 50 | KEEP | 268 | conditional tool registration |
| 58 | GATED | 190 | was #251-blocked (now closed) |
| 70 | KEEP | 268 | data already in schema |
| 73 | KEEP | 268 | data already in schema |
| 76 | KEEP | 268 | search_symbols extension |
| 78 | KEEP | #1224 | no content-inventory CLI |
| 80 | KEEP | #1227 | 2/4 registries live |
| 89 | GATED | 190 | source-expansion child |
| 103 | GATED | 190 | source-expansion child |
| 175 | KEEP | 268 | serve restart on DB refresh |
| 183 | KEEP | standalone | the roadmap |
| 189 | DORMANT | 189 | internal TUI tracker |
| 195 | GATED | #1228 | gated on #196 funding |
| 196 | DEFERRED | #1228 | funding holding-pattern; re-cost vs Haiku 4.5 |
| 197 | KEEP | standalone | meta (roadmap protocol) |
| 216 | GATED | 190 | tutorials source |
| 222 | KEEP | 266 | AST decl association |
| 223 | KEEP | 266 | Apple SDK availability for symbols |
| 224 | KEEP | 266 | doctor coverage for packages |
| 227 | KEEP | 266 | dual-axis split remaining |
| 235 | KEEP | 266 | fast refresh (cross-ref #1221) |
| 240 | KEEP | #1224 | raw SQL surface (post-#239) |
| 247 | KEEP | 769 | partial; 7 pipelines unlifted |
| 248 | KEEP | #1223 | DatabaseRegistry seam unbuilt |
| 266 | EPIC | 266 | availability v2 |
| 268 | EPIC | 268 | MCP capability |
| 269 | KEEP | 266 | platform enum (cross-ref #1222) |
| 270 | DEFERRED | 266 | tier-4 device model |
| 271 | GATED | 268 | needs #742 diagnostic block |
| 272 | KEEP | 268 | sample cross-links |
| 273 | GATED | 190 | Tech Talks source |
| 449 | KEEP | #1226 | no DocC catalog yet |
| 514 | KEEP | #1221 | docs-workload measurement remaining |
| 517 | GATED | 268 | needs #21 + #742 |
| 713 | GATED | 190 | tools source |
| 724 | KEEP | #1225 | path-provenance safety rail |
| 730 | KEEP | #1223 | post-#194 cleanup |
| 742 | KEEP | 268 | Phase 2.1 keystone (high pri) |
| 748 | CLOSEABLE | #1226 | dual-consumer README shipped 2026-06-01 (verify + close) |
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
| 801 | KEEP | #1224 | build-number in --version |
| 816 | KEEP | 191 | the actual release-blocker eval |
| 817 | KEEP | 191 | partially done; relocate harnesses |
| 818 | KEEP | 191 | worst class baseline (18%) |
| 819 | KEEP | 191 | symbol-attribute filters |
| 820 | KEEP | 191 | HIG/archive routing |
| 821 | KEEP | 191 | prose weight profile |
| 822 | KEEP | 191 | human qrels research |
| 885 | KEEP | #1224 | setup --force hint |
| 892 | GATED | 190 | xcodebuild source |
| 909 | KEEP | #1223 | audit-script consistency |
| 957 | KEEP | 190 | community packages corpus |
| 962 | KEEP | #1223 | derive CLI from MCP registry |
| 965 | KEEP | #1223 | AST tools DB-pluggable |
| 1036 | EPIC | 1036 | per-source DB split |
| 1041 | KEEP | #1220 | unblocked by shipped bundle |
| 1048 | KEEP | #1226 | comment cleanup + DocC |
| 1054 | KEEP | #1226 | unblocked (gating issues closed) |
| 1061 | KEEP | 1036 | drop source column |
| 1075 | DEFERRED | #1223 | until a second source joins |
| 1132 | GATED | #1220 | code merged; recrawl-gated |
| 1146 | KEEP | #1221 | in progress on a branch |
| 1151 | GATED | #1222 | Linux indexing + `linux` axis |
| 1152 | KEEP | #1222 | Linux runtime read/serve |
| 1161 | KEEP | #1225 | wrong os.log subsystem in docs |
| 1162 | KEEP | #1225 | serve warning to stderr |
| 1163 | KEEP | #1225 | logging hygiene |
| 1175 | KEEP | #1226 | recommend Homebrew first |
| 1178 | GATED | 268 | needs serve --base-dir (#1168) |
| 1200 | KEEP | #1220 | list_samples schema mismatch |
| 1201 | KEEP | #1220 | save --help stale text |
| 1208 | KEEP | 268 | list-documents tool |
| 1209 | KEEP | #1225 | doctor per-source uniform |
| 1210 | KEEP | 268 | document children tree |
| 1212 | KEEP | 268 | initialize.instructions |

Closed during this audit: **#1184** (fixed in PR #1183), **#1071** (resolved by v1.3.0).

## Recommended execution order

1. **#1220 bug sweep** (north-star: bugs). #1200 + #1201 are fresh, DB-independent, one-file fixes; #1041 is unblocked by the shipped bundle; #1132 is recrawl-gated.
2. **#1221 recrawl** (north-star: recrawl). #1146 (`--resume`) is the enabler and already in progress.
3. **#742** keystone, then the **#268** MCP-capability fan-out it unblocks.
4. **#1228 semantic & vector** (north-star: vector) follows the diagnostic surface.
5. Parallel tracks (#1222 Linux, #1223 pluggability, #1224 CLI, #1225 diagnostics, #1226 docs, #1227 distribution) pick up opportunistically.

## Quick wins (closeable or near-trivial)

- **#748**: verify against the 2026-06-01 README restructure (dual-consumer framing shipped), then close.
- **#1200**, **#1201**: one-file fixes from the docs/commands audit.
- **#1175**: README install-ordering one-liner.

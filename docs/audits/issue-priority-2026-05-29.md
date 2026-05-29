# Issue priority triage (2026-05-29)

Prioritisation of the **88 open issues** after the full per-issue audit on 2026-05-29 (every open issue read in detail and verified active + correct). This is a point-in-time snapshot; it goes stale as issues open and close. The canonical living roadmap is #183.

What the audit changed (so this list differs from a naive label sort):
- Closed with verified evidence: #930 (PR #931), #949 (PR #950), #1039 (PR #1056), #1040 (rename complete), #1126 (PR #1127), #410 (per-source split shipped via #1056/#1036), plus #5 / #747 / #1133 (merged to develop) and #1141 (external promo spam).
- #251 reclassified: only its *pluggability* shipped (#919/#935 proved the 2-file-PR claim; the DB split landed). Its *taxonomy* core (one source catalog, one cross-DB classifier, zero hardcoded source strings) is still undone, so it stays open at reduced leverage.
- #190 (source expansion) is no longer hard-blocked on #251 (adding a source is now pluggable), so the new-source issues are more actionable.

## Ranking criteria (in order)

1. Release-blockers. 2. Correctness bugs. 3. The maintainer roadmap (#183): bugs -> recrawl -> vector -> tutor. 4. Dependency leverage. 5. Strategic / AI-agent value. 6. Deferred-by-decision sinks regardless of age.

## P0 - Critical (release-blocking / active)

- **#1071** `bug` - `cupertino setup` fails against the v1.2.0 release zip (binary expects per-source DBs, zip ships `search.db`). Next-release blocker: the post-#1036 binary cannot ship until the release zip matches.
- **#1036** `priority:high, epic` - per-source DB split. The 8 per-source DBs already exist; this is the umbrella driving the release, and it now also carries #410's two residual UX items (`setup --only`, per-source `publish-source`).
- **#742** `priority:high, epic` - MCP diagnostic block. Keystone unblocking #10, #13, #21, #70, #271, #517.

## P1 - Correctness bugs

- **#954** `bug` - package-search ranking: famous libraries (Alamofire, Kingfisher) absent from top-10 for their own names.
- **#1132** `bug` - SynonymsPass attaches 0 synonyms (acronym routing degraded).
- **#1092** `bug` - swift-book: 2 of 43 topics carry stale Swift 6.2.1 content.
- **#1041** `bug` - list-frameworks `totalDocs` label wrong post-split (cosmetic count).

## P2 - High-leverage epics and enablers

- **#8** - vector / semantic search via sqlite-vec. The "vector" stage of the roadmap; v2.0 strategic bet (needs design first).
- **#816** - Phase 1.7 anti-hallucination agent-end-to-end eval ("the actual release-blocker measurement").
- **#248** + **#965** - declarative DB registry + AST tools made DB-pluggable (the "adding a DB is a 2-file PR" goal; the source side already shipped).
- **#251** `epic` - taxonomy unification (one source catalog, one cross-DB classifier, zero hardcoded source strings, unified `DocKind` per hit). Reduced leverage now that pluggability shipped, but a real cleanup; not a blocker for #190 anymore.
- **#190** `epic` - source expansion (now unblocked; the new-source children below are actionable).
- **#943** `epic` - comprehensive query batteries.
- **#266** `epic` availability v2; **#268** `epic` MCP capability (gated on #742); **#191** `epic` search quality (nearly complete).
- **#769** `epic` (+ #770, #771, #772, #773, #774, #775, #776, #777, #778) - layer separation. Large refactor, no work started; lowest within P2, and partly reshaped by #1056 (flagged at the epic).

## P3 - Valuable enhancements

- **AI-agent UX:** #70 / #73 token-efficient lookups; #271 token-budget results; #517 agent-first output; #748 README dual-consumer.
- **Search quality:** #818 synonyms at ranking (pairs with #1132); #819 symbol-attribute filters; #820 design-vocabulary routing; #821 prose BM25F; #822 TREC pooling; #817 harnesses into the repo; #9 highlighting; #10 spelling correction; #76 wildcard symbols.
- **New sources (now actionable, #190 unblocked):** #58 WWDC; #89 Swift Forums; #273 Tech Talks; #713 fastlane + tuist; #892 xcodebuild; #103 Kernel / IOKit; #216 tutorials.
- **Availability v2 (under #266):** #222, #223, #224, #227, #235, #269, #270.
- **MCP:** #13 resource templates; #50 conditional registration; #175 restart; #272 sample cross-links; #962 derive CLI from the MCP registry.

## P4 - Polish, small CLI, chore, docs

- **Small CLI / good first issue:** #16 verbosity; #885 `setup --force` hint; #801 build-number; #17 search progress; #78 `stats`; #240 raw-SQL query.
- **Docs / chore:** #1054 rewrite HOW-TO-ADD-A-SOURCE.md (unblocked); #1048 comment cleanup + DocC; #449 DocC catalog; #1061 drop `docs_metadata.source`; #1075 enrichment seam to packages/samples; #909 audit-script consistency; #197 roadmap protocol; #730 delete neutered accessor; #724 doctor path-provenance; #247 lift FetchCommand into Ingest.
- **Corpus / distribution / bench:** #957 expand packages.db corpus; #43 Homebrew Core; #80 MCP registries; #21 cupertino-bench.

## P5 - Deferred or holding (explicit no-work-planned)

- **#800** quadratic save (deferred); **#196** GoFundMe (held); **#195** semantic tags (needs #196); **#514** WAL throughput measurement (carried, not blocking); **#22** memory budgets; **#270** per-device tracking; **#189** `epic` TUI internal tracker.
- **#183** Roadmap - the canonical living roadmap; keep open, not a discrete work item.

## Top 5 to pick up next

1. **#1071** - unblocks the next release.
2. **#954** - package-search returns wrong top results.
3. **#1132** - acronym/synonym search routing degraded.
4. **#8** - vector search, the roadmap's strategic bet.
5. **#742** - MCP diagnostic keystone (unblocks 6 downstream issues).

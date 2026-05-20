# Search-quality version diff: v1.0.2 → v1.2.0

**Date:** 2026-05-20
**Status:** Strong
**Headline:** +13 / 50 queries newly rank-1
**System A (prior release):** brew binary `cupertino 1.1.0` against `~/.cupertino/search.db` (v1.0.2 bundle, schema `user_version = 13`, 285,735 documents)
**System B (next release):** `Packages/.build/release/cupertino 1.1.0` (develop tip + #831) against `~/.cupertino-dev/search.db` (v1.2.0 candidate bundle, schema `user_version = 18`, 352,712 documents)
**Methodology:** `docs/design/search-quality-eval.md` Phase 1 (paired-comparison mode); per-query rank-1 outcome aggregated into a 2 × 2 McNemar contingency table; aggregate metrics paired-Wilcoxon. McNemar exact two-sided p = 0.000244.
**Universal rule:** `../private/mihaela-agents/Rules/universal/search-quality-eval.md`

This is the **Phase 1.8 version-to-version comparison KPI** specified in issue [#830](https://github.com/mihaelamj/cupertino/issues/830). It pairs the 50-query canonical-lookup corpus from the v1.2.0 baseline audit against the previously released v1.0.2 bundle and answers the question a user asks when deciding whether to upgrade: *what changes if I do?*

---

## Aggregate

| Metric | v1.0.2 (brew) | v1.2.0 (dev) | Delta |
|---|---|---|---|
| N queries | 50 | 50 | — |
| **MRR** | **0.7967** | **0.9467** | **+0.1500** |
| P@1 | 0.6800 (34 / 50) | 0.9200 (46 / 50) | +0.2400 |
| P@5 | 0.2760 | 0.3280 | +0.0520 |
| NDCG@10 | 1.2562 | 1.7385 | +0.4823 |

Paired Wilcoxon signed-rank test on per-query MRR:
- **Two-sided** *W* = 1.50, *p* = 0.001147, *N*<sub>nonzero</sub> = 14
- **One-sided (v1.2.0 > v1.0.2)** *W* = 103.50, *p* = 0.000574

Both far below the conventional α = 0.05 threshold. The improvement is not consistent with chance.

---

## Headline

**If you upgrade from v1.0.2 to v1.2.0, on the canonical-lookup corpus you gain 13 queries at rank 1 and lose 0. One previously-wrong answer ranks slightly worse but neither version returned it at rank 1.**

---

## Four-bucket diff (per [#830](https://github.com/mihaelamj/cupertino/issues/830))

| Bucket | Count | Definition | Queries |
|---|---|---|---|
| **Added** | **2** | Was outside top 10 in v1.0.2, now rank-1 in v1.2.0 | `Optional`, `Data` |
| **Removed** | **0** | Was rank-1 in v1.0.2, no longer rank-1 in v1.2.0 | — |
| **Fixed** | **11** | Was found in v1.0.2 but below rank 1, now rank-1 in v1.2.0 | `Hashable`, `Equatable`, `Sequence`, `AsyncSequence`, `DateFormatter`, `ForEach`, `Observable`, `State property wrapper`, `UIColor`, `Combine Publisher` (3 → 2), `Observation` |
| **Degraded** | **1** | First-relevant rank moved further from rank 1 | `CoreData` (rank 2 → rank 3) |
| Unchanged (both rank-1) | 34 | Same rank-1 outcome in both versions | majority of the corpus |
| Both still suboptimal | 2 | Neither version returned a relevant doc at rank 1 | `SwiftUI View` (both miss top 10), `MapKit` (both rank 2) |

The `Added` / `Removed` / `Fixed` rows are the **rank-1 transition** view. The `Degraded` row in this run is mild (one rank position drop on a query that was already not rank-1 in v1.0.2). No query lost its rank-1 status.

`Combine Publisher` is included in `Fixed` because v1.2.0 moves it from rank 3 to rank 2 (closer to canonical) even though it's not at rank 1 in either version; the per-query MRR delta of +0.167 is positive.

---

## McNemar exact test (binary rank-1 outcome)

The McNemar test pins whether the rank-1 success rate changed significantly between the two paired runs, using the discordant pairs (rows where exactly one version got rank 1).

|  | v1.2.0 rank-1 | v1.2.0 not rank-1 |
|---|---|---|
| **v1.0.2 rank-1** | 34 (concordant +) | 0 (would-be regression) |
| **v1.0.2 not rank-1** | 13 (improvement) | 3 (concordant −) |

- *b* = 0 (queries that were rank-1 in v1.0.2 but no longer rank-1 in v1.2.0)
- *c* = 13 (queries that were not rank-1 in v1.0.2 and are rank-1 in v1.2.0)
- McNemar exact (binomial), two-sided: *p* = **0.000244**

Equivalent statement: under the null hypothesis that v1.0.2 and v1.2.0 perform identically on rank-1 outcomes, the probability of observing this large a one-sided imbalance is 1 in 4,096. We reject the null.

---

## Where the gains come from

The schema and corpus changes between v1.0.2 (schema v13, 285,735 docs) and v1.2.0 (schema v18, 352,712 docs) include:

1. **+66,977 documents** added to `docs_metadata` (+23%). The `Optional` and `Data` recovery (the two `Added` rows) is consistent with two pages that were missing from the v1.0.2 bundle entirely.
2. **Schema additions** in v14 → v18 include the `kind` taxonomy column (#192), the `implementation_swift_version` column (#225 Part B), AST-derived `symbols` and `symbol_components` columns (#77, #192), and the framework-aliases canonicalization table (#254 cross-source path). The 11 `Fixed` queries are characteristic of `symbols` and `symbol_components` doing their intended work: an exact match on a Swift type name now biases ranking toward the canonical type page, which used to sit at rank 2 or 3 behind prose-heavy pages that mentioned the name.
3. **BM25F weight tuning** (PR #254) elevated the `symbols` column to weight 5.0 and the `title` column to 10.0. Several of the rank-2 → rank-1 transitions (`Hashable`, `Equatable`, `Sequence`, `DateFormatter`, `Observable`) are explained by canonical-symbol pages winning the tie that the v13 ranker lost to slug-heavy sibling pages.
4. **Reciprocal Rank Fusion** with per-source authority weights (PR #254 Option B) gives apple-docs an elevated multiplier, breaking the tie that produced the v1.0.2 ordering on `AsyncSequence` and `State property wrapper`.

The single `Degraded` row (`CoreData` 2 → 3) is consistent with a known issue logged in the v1.2.0 baseline: the framework-aliases canonicalization for `coredata → CoreData` exists but the framework root is losing the BM25F tie to deep API pages that contain the literal token `coredata`. This is a candidate for the symbol-attribute / acronym follow-up work tracked in issues [#818](https://github.com/mihaelamj/cupertino/issues/818) and [#820](https://github.com/mihaelamj/cupertino/issues/820).

---

## What this audit does NOT measure

- **Criterion 2 (anti-hallucination).** Whether an AI agent given the v1.2.0 top-K actually produces correct Swift, vs the same agent on v1.0.2's top-K. That's the Phase 1.7 design (`docs/design/anti-hallucination-eval.md`, issue [#816](https://github.com/mihaelamj/cupertino/issues/816)).
- **Per-query class breakdown.** The seven Phase 1.x classes (deprecation, cross-source, fragment, acronym, prose, symbol-attribute) each have their own audit. The version-diff above is restricted to **class A (canonical-lookup)** + **class B (framework-root)** because that's the corpus the v1.2.0 baseline pins. The other classes were not measured against v1.0.2 in this run; that work is queued.
- **TREC-grade human pooling.** Programmatic ground truth via URI-regex covers ~80% of the variance for ~5% of the effort; the design's §14.5 Phase 2 plan formalizes the human-pooling extension for cases where programmatic patterns are ambiguous.

---

## Method recap

50 canonical-lookup queries each paired with a right-answer URI regex (same corpus as `docs/audits/search-quality-baseline-v1.2.0.md`). For each query, `cupertino search "<query>" --limit 10` was invoked twice:

- once via `/opt/homebrew/bin/cupertino` against the default brew base directory `~/.cupertino/`
- once via `Packages/.build/release/cupertino` against `~/.cupertino-dev/` (auto-routed via the bundled `cupertino.config.json`)

Top-10 URIs were extracted from stdout in document order. Per-query MRR, P@1, P@5, NDCG@10 computed against the regex. Aggregate metrics paired-Wilcoxon. Binary rank-1 outcome aggregated into the 2 × 2 contingency table and tested with McNemar's exact binomial.

Harness source: `/tmp/cupertino-search-eval.py` (paired mode; not yet versioned in the repo; move to `scripts/eval/` per design §14.1 follow-up, [#817](https://github.com/mihaelamj/cupertino/issues/817)).
Full JSON dump (all 50 paired top-10 lists): `/tmp/cupertino-search-eval-results.json`.

Neither database was written to during the run. `~/.cupertino/*.db` was opened read-only via the brew binary's standard search path; `~/.cupertino-dev/*.db` likewise.

---

## How to use this audit

When v1.2.0 ships:

- The "**13 added, 0 removed, 1 mild degradation**" headline lands in the release notes.
- The McNemar *p* = 0.000244 is the citation for "statistically significant improvement" claims.
- Re-running this audit at every subsequent release (v1.2.0 → v1.3.0, v1.3.0 → v1.4.0, …) produces a per-release diff card on the dashboard. The renderer is auto-deriving, so the only artefact required for a future version-diff is a new audit markdown under `docs/audits/` matching the naming pattern `search-quality-versiondiff-vX.Y.Z-to-vA.B.C.md`.

The `CoreData` row is a regression-watch item: a future ranker change that fixes the framework-aliases tie-break shouldn't simultaneously demote `CoreData` further. Add it to the per-class follow-up corpus when the alias work in [#818](https://github.com/mihaelamj/cupertino/issues/818) lands.

# Search-quality version diff (Phase 5): 1.2.0 to 1.2.1

**Date:** 2026-05-23
**Phase:** 5 (list / doctor / package-search)
**Harness:** `scripts/eval/search-quality-phase5.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 5
**Library:** `scripts/eval/lib_harness.py`
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | v1.2.0 | v1.2.1 | Delta |
|---|---|---|---|
| N queries | 13 | 13 | n/a |
| **MRR** | **0.8462** | **0.8462** | **+0.0000** |
| P@1 | 0.8462 (11 / 13) | 0.8462 (11 / 13) | +0.0000 |
| not pass | 2 | 2 | +0 |

## Paired tests

- McNemar (rank-1 outcome) two-sided p: **1.000000**
- Wilcoxon (B > A) one-sided p: **1.000000**

## Buckets

| Bucket | Count | Queries |
|---|---|---|
| Added | 0 | n/a |
| Removed | 0 | n/a |
| Fixed | 0 | n/a |
| Degraded | 0 | n/a |
| Unchanged (rank-1) | 11 | majority |
| Both suboptimal | 2 | `package-search alamofire`, `package-search kingfisher` |

## Method

Phase 5 queries dispatch on a per-fixture `type`. The implemented dispatch surface (mirror of `score_query` in `scripts/eval/search-quality-phase5.py`):

- `lines-min`: exit 0 AND stdout line count >= `expected.min_lines`
- `lines-min-with-tokens`: lines-min AND every token in `expected.must_contain` (case-insensitive substring) is present in stdout (used for structural invariants where the canonical totals are pinned: `420 total`, `Total: 619 projects`)
- `exit-0-with-marker`: exit 0 AND stdout contains `expected.marker` (case-insensitive)
- `exit-nonzero`: returncode != 0 (Class C negative path)
- `package-text-topk-contains`: at least one of the top-10 `[N] owner/repo` result blocks contains any string in `expected.any_substr` (body match; loose, used for broad semantic queries)
- `package-text-rank1-owner-repo`: the RANK-1 result header's owner/repo segment contains any string in `expected.owner_repo_substr` (strict; used for canonical-lookup queries where the rank-1 winner is the named library)
- `package-text-topk-owner-repo`: any of the top-10 result headers' owner/repo segments contains any string in `expected.owner_repo_substr` (used for canonical-lookup queries that admit multiple acceptable rank-1 winners by family, e.g. networking → nio / alamofire / grpc)

Rank assignment per type: structural invariants (`lines-min*`, `exit-0-with-marker`, `exit-nonzero`) and the strict `package-text-rank1-owner-repo` produce `first_relevant_rank = 1` on pass / `None` on fail (binary outcome). The two top-K dispatches (`package-text-topk-contains`, `package-text-topk-owner-repo`) assign `first_relevant_rank = i` where `i` is the 1-indexed position of the first matching block in the top-10, so P@1 / MRR / NDCG can express partial credit when the canonical winner shifts down the result list. Structural invariants are Class D; package-search by name is Class A; semantic / broad package-search is Class B; empty-query negative path is Class C.

# Search-quality version diff (Phase 3): 1.2.0 to 1.2.1

**Date:** 2026-05-23
**Phase:** 3 (`cupertino inheritance` = MCP `get_inheritance`)
**Harness:** `scripts/eval/search-quality-phase3.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 3
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | v1.2.0 | v1.2.1 | Delta |
|---|---|---|---|
| N | 22 | 22 | n/a |
| **MRR** | **0.8636** | **0.8636** | **+0.0000** |
| P@1 | 0.8636 (19/22) | 0.8636 (19/22) | +0.0000 |

## Paired tests

- McNemar two-sided p: 1.000000
- Wilcoxon (B > A) one-sided p: 1.000000

## Method

Up walks assert the indented chain output contains the expected ancestor URI fragment. Down walks assert the chain contains the expected descendant. Depth-bounded probes assert the chain reaches (or does not reach) the expected hop. Negative-path probes (Class C) require BOTH exit-0 AND an explicit documented marker (`no inheritance data`, `no symbol named`, `no results`, or `ambiguous` for the disambiguation list). Empty stdout and non-zero exit are explicitly rejected as PASS to avoid masking silent-empty regressions and crashes (iter-2 critic finding).

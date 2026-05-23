# Search-quality version diff (Phase 3): v1.2.0 to v1.2.1-dev

**Date:** 2026-05-23
**Phase:** 3 (`cupertino inheritance` = MCP `get_inheritance`)
**Harness:** `scripts/eval/search-quality-phase3.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 3
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | v1.2.0 release | v1.2.1+#955 dev | Delta |
|---|---|---|---|
| N | 22 | 22 | n/a |
| **MRR** | **0.8636** | **1.0000** | **+0.1364** |
| P@1 | 0.8636 (19/22) | 1.0000 (22/22) | +0.1364 |

## Paired tests

- McNemar two-sided p: 0.250000
- Wilcoxon (B > A) one-sided p: 0.054405

## Method

Up walks assert the indented chain output contains the expected ancestor URI fragment. Down walks assert the chain contains the expected descendant. Depth-bounded probes assert the chain reaches (or does not reach) the expected hop. Negative-path probes (Class C) require an explicit documented marker (`no inheritance data`, `no symbol named`, `no results`, or `ambiguous` for the disambiguation list) present in stdout OR stderr (post-#953 the disambiguation + framework-miss diagnostics go to stderr via the synchronous `CLIImpl.printUserFacingDiagnostic` helper, while value-type and root-type markers stay on stdout as part of the successful `cupertino inheritance` output). Exit code is deliberately NOT constrained: value-type negatives exit 0 (correct successful answer "no inheritance data for value types"); disambiguation exits 1 (refusing to proceed without --framework). Both are valid Class C outcomes, so the harness accepts either.

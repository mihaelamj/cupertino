# Search-quality version diff (Phase 2): 1.2.0 to 1.2.1

**Date:** 2026-05-23
**Phase:** 2 (5 AST tools via MCP stdio)
**Harness:** `scripts/eval/search-quality-phase2.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 2
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | v1.2.0 | v1.2.1 | Delta |
|---|---|---|---|
| N | 20 | 20 | n/a |
| **MRR** | **0.6000** | **0.6000** | **+0.0000** |
| P@1 | 0.6000 (12/20) | 0.6000 (12/20) | +0.0000 |

## Paired tests

- McNemar two-sided p: 1.000000
- Wilcoxon (B > A) one-sided p: 1.000000

## Method

Each fixture spawns a fresh `cupertino serve --no-reap` subprocess and sends `initialize` + `notifications/initialized` + a single `tools/call` over stdio (20 fixtures x 2 arms = 40 cold starts per paired run; per-query cost dominated by serve startup). A persistent-Popen rewrite is a follow-up that would amortize startup; the current shape is the simpler robust default. Scoring: response text is parsed into per-result `### <name>` blocks; fixtures fail hard when the response carries `_No <kind> found_` or has zero `### ` blocks (no false-positive PASS on empty result sets, per iter-1 critic). Two scoring modes: `expect_any` matches any of a substring set against the parsed result-block body (not the response header); `expect_nonempty` requires at least one `### ` block to exist.

Per #948 these 5 tools have no CLI equivalent yet , once CLI subcommands land, the harness can collapse to shell-out (same shape as Phase 1).

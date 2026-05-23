# Search-quality version diff (Phase 4): v1.2.0 to v1.2.1-dev

**Date:** 2026-05-23
**Phase:** 4 (read commands)
**Harness:** `scripts/eval/search-quality-phase4.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 4
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | v1.2.0 release | v1.2.1+#955 dev | Delta |
|---|---|---|---|
| N | 13 | 13 | n/a |
| **MRR** | **0.9231** | **1.0000** | **+0.0769** |
| P@1 | 0.9231 (12/13) | 1.0000 (13/13) | +0.0769 |

## Paired tests

- McNemar two-sided p: 1.000000
- Wilcoxon (B > A) one-sided p: 0.158655

## Method

Each fixture probes one URI / project-id and asserts the format-appropriate signal: JSON parses with a content field, markdown body has at least 100 chars, sample read returns at least 50 chars. Negative-path probes (Class C) require BOTH an explicit per-error marker AND non-zero exit. Accepted marker substrings (post-iter-2 critic): `not found`, `no such`, `no document`, `project not found`, `no project named`, `read failed`, `invalid package identifier`. The marker list mirrors the user-facing diagnostic phrases emitted by each `Services.ReadService.ReadError` case after the #953 helper migration. The conjunction prevents two failure modes from being silently scored as PASS: a binary refactor that flips ExitCode.failure to ExitCode.success while still emitting the marker (semantic regression), and crashes / DB-open errors that exit non-zero with an unrelated message containing the substring `error` (iter-2 critic finding).

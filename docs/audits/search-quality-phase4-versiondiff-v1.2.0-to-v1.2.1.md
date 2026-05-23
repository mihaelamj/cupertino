# Search-quality version diff (Phase 4): 1.2.0 to 1.2.1

**Date:** 2026-05-23
**Phase:** 4 (read commands)
**Harness:** `scripts/eval/search-quality-phase4.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 4
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | v1.2.0 | v1.2.1 | Delta |
|---|---|---|---|
| N | 13 | 13 | n/a |
| **MRR** | **0.9231** | **0.9231** | **+0.0000** |
| P@1 | 0.9231 (12/13) | 0.9231 (12/13) | +0.0000 |

## Paired tests

- McNemar two-sided p: 1.000000
- Wilcoxon (B > A) one-sided p: 1.000000

## Method

Each fixture probes one URI / project-id and asserts the format-appropriate signal: JSON parses with a content field, markdown body has at least 100 chars, sample read returns at least 50 chars. Negative-path probes (Class C) require BOTH an explicit not-found marker (`not found`, `no such`, `no document`, `project not found`, `no project named`) AND non-zero exit. The conjunction prevents two failure modes from being silently scored as PASS: a binary refactor that flips ExitCode.failure to ExitCode.success while still emitting the marker (semantic regression), and crashes / DB-open errors that exit non-zero with an unrelated message containing the substring `error` (iter-2 critic finding).

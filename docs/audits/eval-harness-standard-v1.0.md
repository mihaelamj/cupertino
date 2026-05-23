# Eval-harness standard v1.0

**Filed**: 2026-05-23. **Status**: canonical. **Umbrella**: [#943](https://github.com/mihaelamj/cupertino/issues/943). **Infra**: [#949](https://github.com/mihaelamj/cupertino/issues/949).

This document is the contract every phase eval-harness script (`scripts/eval/search-quality-phase<N>.py`) follows. It describes the shared library (`scripts/eval/lib_harness.py`), the CLI flags every phase exposes, the JSON output schema, the paired-comparison audit-Markdown shape, and the CI smoke-mode hook.

Phase 1 (search, canonical-lookup + framework-root) is the reference implementation. Phases 2-5 (#944, #945, #946, #947) consume the same library.

---

## 1. Library: `scripts/eval/lib_harness.py`

One library, used by every phase. Carries the boilerplate every phase needs identically: per-query result dataclass, single-arm aggregate metrics, McNemar exact + Wilcoxon signed-rank paired tests, paired-comparison bucketing, JSON output writer, db stat probe, generic argparse builder + main runner.

### 1.1 `QueryOutcome` dataclass

Every phase's `score_fn` returns a `QueryOutcome`. Fields are shared across phases:

| Field | Type | Meaning |
|---|---|---|
| `query` | str | Human-readable query id (search string / symbol / URI / etc.) |
| `pattern` | str | Right-answer specifier (regex / expected-list / marker phrase) |
| `qclass` | str | Class `A` / `B` / `C` / `D` per the design doc |
| `notes` | str | Free-text notes from the fixture |
| `first_relevant_rank` | `Optional[int]` | 1-indexed rank of first relevant result; `None` if none in top 10 |
| `rr` | float | Reciprocal rank (`1 / first_relevant_rank`); 0 if no match |
| `p_at_1` | int | 1 if rank-1 matches, else 0 |
| `p_at_5` | float | Fraction of top-5 that match |
| `ndcg_at_10` | float | Standard NDCG@10, gain=1 per match, IDCG=1 |
| `top_uris` | list | First N raw result identifiers for audit |

Phases that need phase-specific extra payload subclass `QueryOutcome` and add fields; `dataclasses.asdict` in `run_main` picks them up.

### 1.2 Phase-specific `score_fn`

```python
def score_query(binary: str, search_db: str, fixture: <PhaseSpecific>) -> QueryOutcome: ...
```

`fixture` is whatever shape the phase's corpus uses (tuple for Phase 1; dict for richer phases). The function shells out to the right `cupertino X --format json` command (or speaks MCP stdio for Phase 2), parses the response, and computes the four metrics.

### 1.3 Optional MD writer

```python
def write_versiondiff_md(out_path, arm_a_label, arm_b_label, arm_a_agg, arm_b_agg, paired, arm_a_meta, arm_b_meta, version_a, version_b): ...
```

Each phase ships its own Markdown audit writer. Phase 1's writer matches the existing `docs/audits/search-quality-versiondiff-v1.0.2-to-v1.2.0.md` shape. Phase 2-5 writers follow the same structural skeleton (Aggregate / Paired tests / Buckets / Method recap / Not-captured).

---

## 2. CLI contract (every phase)

Every phase exposes the same flags via `lib_harness.make_argparser()`.

### 2.1 Single-arm

```sh
python3 scripts/eval/search-quality-phaseN.py \
    --binary /opt/homebrew/bin/cupertino \
    --search-db ~/.cupertino/search.db \
    --label "v1.2.1 brew" \
    --version "1.2.1" \
    --out /tmp/phaseN-v121.json
```

### 2.2 Paired-arm

```sh
python3 scripts/eval/search-quality-phaseN.py \
    --arm-a-binary /tmp/cup-v120/cupertino \
    --arm-a-search-db ~/.cupertino/search.db \
    --arm-a-label "v1.2.0 release" \
    --arm-a-version "1.2.0" \
    --arm-b-binary /opt/homebrew/bin/cupertino \
    --arm-b-search-db ~/.cupertino/search.db \
    --arm-b-label "v1.2.1 brew" \
    --arm-b-version "1.2.1" \
    --out /tmp/phaseN-versiondiff.json \
    --md-out docs/audits/search-quality-phaseN-versiondiff-v1.2.0-to-v1.2.1.md
```

### 2.3 Smoke mode

```sh
python3 scripts/eval/search-quality-phaseN.py \
    --binary /opt/homebrew/bin/cupertino \
    --search-db ~/.cupertino/search.db \
    --label smoke --version smoke \
    --smoke
```

Runs only the first fixture in the corpus. Total wall-time should be < 5 seconds per phase. Used by the `query-batteries-smoke` CI job.

---

## 3. JSON output schema

### 3.1 Single-arm

```json
{
  "label": "v1.2.1 brew",
  "version": "1.2.1",
  "agg": {
    "n": 50,
    "p_at_1_count": 46,
    "p_at_1": 0.92,
    "p_at_5_mean": 0.2,
    "mrr": 0.9467,
    "ndcg_at_10_mean": 0.9533,
    "not_in_top_10": 1
  },
  "outcomes": [
    {"query": "Hashable", "pattern": "...", "qclass": "A", "notes": "...",
     "first_relevant_rank": 1, "rr": 1.0, "p_at_1": 1, "p_at_5": 0.2,
     "ndcg_at_10": 1.0, "top_uris": ["apple-docs://swift/hashable", ...]}
  ]
}
```

### 3.2 Paired-arm

Adds `arm_a` / `arm_b` (each shaped like single-arm `agg` + `outcomes`) plus a `paired` object with `buckets`, `mcnemar`, `wilcoxon`.

```json
{
  "arm_a": {"label": "...", "meta": {"binary": "...", "db": "...", "schema": "v18", "docs": "352,712"}, "agg": {...}, "outcomes": [...]},
  "arm_b": {"label": "...", "meta": {...}, "agg": {...}, "outcomes": [...]},
  "paired": {
    "buckets": {"added": [...], "removed": [...], "fixed": [...], "degraded": [...], "unchanged_rank1": [...], "both_suboptimal": [...]},
    "mcnemar": {"both_rank1": 46, "a_only_rank1": 0, "b_only_rank1": 0, "neither_rank1": 4, "p_two_sided": 1.0},
    "wilcoxon": {"W_plus": 0, "W_minus": 0, "p_two_sided": 1.0, "p_one_sided_b_gt_a": 1.0, "n_nonzero": 0, "z": 0.0}
  }
}
```

---

## 4. Baseline document shape

When a phase ships, the FIRST run becomes the baseline. The Markdown audit goes to `docs/audits/search-quality-phase<N>-baseline-v1.2.x.md`. Structure mirrors `search-quality-versiondiff-v1.0.2-to-v1.2.0.md` (the existing v1.2.0 audit):

1. **Header**: date, arms (binary + db + schema + doc count), methodology, harness, universal rule, companion handbook
2. **Aggregate**: 5-column table of N / MRR / P@1 / P@5 / NDCG@10, both arms + delta
3. **Headline**: one-sentence summary (Added + Fixed count, Removed count)
4. **Paired statistical tests**: Wilcoxon (N_nonzero, W+, p-values) + McNemar (2x2 contingency + exact binomial p)
5. **Buckets**: 6 row table (Added / Removed / Fixed / Degraded / Unchanged / Both-suboptimal) with counts + queries
6. **Method recap**: how each query was scored
7. **What this measurement does NOT capture**: explicit scope limits

Subsequent runs that re-baseline (e.g. after a corpus expansion) replace this file; older baselines move to `docs/audits/archive/` with a date suffix.

---

## 5. CI integration

### 5.1 `query-batteries-smoke` job

New job in `.github/workflows/ci.yml`. Triggers on `pull_request` + `push to develop/main`. Runs every phase with `--smoke` (1 fixture each), total wall-time budget < 30 seconds.

```yaml
query-batteries-smoke:
  name: Query batteries smoke
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - uses: maxim-lobanov/setup-xcode@v1
      with: { xcode-version: latest-stable }
    - working-directory: Packages
      run: swift build -c release
    - run: |
        for phase in scripts/eval/search-quality-phase*.py; do
          python3 "$phase" \
            --binary Packages/.build/release/cupertino \
            --search-db ~/.cupertino-dev/search.db \
            --label smoke --version smoke \
            --smoke
        done
```

(The dev binary auto-isolates to `~/.cupertino-dev/` via the bundled `cupertino.config.json` per `make build-release`; CI must seed that dir with the bundle or invoke `setup` before the smoke runs.)

### 5.2 Full-run cadence

Full Phase 1-5 runs are reserved for tagged releases (the existing v1.2.x release ceremony adds them as part of the audit step). Not on every PR; the runs are too long (Phase 1 alone is ~5 minutes wall-time).

---

## 6. Adding a new phase

To add Phase 6 (or extend an existing phase):

1. Write the fixture corpus (constant list in the phase script OR external YAML).
2. Write `score_query(binary, search_db, fixture) -> QueryOutcome`. For non-CLI tools, write the MCP stdio invocation (see Phase 2's helper).
3. Write `write_versiondiff_md(out_path, ...)`. Mirror Phase 1's shape; the parameter list is fixed.
4. `main()` shrinks to:
   ```python
   def main():
       ap = make_argparser("PhaseN <description>")
       args = ap.parse_args()
       run_main(args, corpus=CORPUS, score_fn=score_query, md_writer=write_versiondiff_md, phase_name="phaseN")
   ```
5. Add the script to the CI smoke job's loop.
6. Land a baseline doc at `docs/audits/search-quality-phaseN-baseline-v1.2.x.md`.

Total per-phase work: ~200-400 LOC (corpus + score_fn + MD writer); the library handles the rest.

---

## 7. Companion documents

- `docs/design/search-quality-eval.md`: the methodology (Cranfield paradigm, query classes, metric definitions).
- `docs/audits/query-batteries-design-2026-05-23.md`: the per-phase fixture design (113 fixtures across Phase 2-5).
- `mihaela-agents/Rules/universal/search-quality-eval.md`: the universal IR-evaluation rule the methodology stands on.
- `docs/database-handbook.md` §5: the human-readable entry point into search-quality work.

---

## 8. Versioning

This is v1.0 of the standard. Breaking changes (e.g., changing `QueryOutcome` fields, changing the JSON output schema, changing the argparse contract) require bumping to v1.1+ AND updating every phase script in the same PR. Additive changes (new optional flags, new dataclass subclasses) stay at v1.0.

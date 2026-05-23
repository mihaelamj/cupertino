#!/usr/bin/env python3
"""
Phase 1 search-quality harness — canonical-lookup query class.

Per `docs/design/search-quality-eval.md` §G1-G4 + universal rule
`mihaela-agents/Rules/universal/search-quality-eval.md`.

Runs a fixed query corpus against a `(binary, search.db)` pair via
`cupertino search --format json` and computes the canonical
single-system metrics: P@1, P@5, MRR, NDCG@10. When two arms are
provided, also emits the paired comparison: ΔMRR + per-query
buckets (Added / Removed / Fixed / Degraded / Unchanged) +
McNemar 2×2 contingency on the rank-1 outcome + paired Wilcoxon
on the per-query reciprocal-rank vector.

Usage:

    # Single-arm (one baseline measurement):
    python3 scripts/eval/search-quality-phase1.py \\
        --binary /opt/homebrew/bin/cupertino \\
        --search-db ~/.cupertino/search.db \\
        --label "v1.1.0 brew" \\
        --out /tmp/v110.json

    # Paired comparison (two arms):
    python3 scripts/eval/search-quality-phase1.py \\
        --arm-a-binary /opt/homebrew/bin/cupertino \\
        --arm-a-search-db ~/.cupertino/search.db \\
        --arm-a-label "v1.1.0 (brew)" \\
        --arm-b-binary Packages/.build/release/cupertino \\
        --arm-b-search-db ~/.cupertino-dev/search.db \\
        --arm-b-label "v1.2.0 (dev)" \\
        --out /tmp/comparison.json \\
        --md-out docs/audits/search-quality-versiondiff-v1.1.0-to-v1.2.0.md

The query corpus is built into this file (CANONICAL_QUERIES). It
mirrors the v1.0.2-to-v1.2.0 versiondiff baseline's shape: ~50
single-token canonical lookups across Swift stdlib, Foundation,
SwiftUI, UIKit/AppKit, Combine, Concurrency, plus framework-root
queries. Each query has a regex pattern (the "right answer"
pattern) that matches the canonical URI for that concept.

NG1 of the design: this is NOT a general-purpose IR toolkit. It's
focused on cupertino's CLI shape and corpus.
"""
import json
import math
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from lib_harness import (  # noqa: E402
    QueryOutcome,
    make_argparser,
    run_main,
)

# MARK: Query corpus
#
# 50 canonical-lookup queries. Each tuple is:
#   (query_string, right_answer_uri_regex, query_class, notes)
#
# Class A = canonical lookup (single concept → single canonical URI).
# Class B = framework-root (framework name → framework landing page).
#
# The regex is matched against `uri` from `cupertino search --format
# json` output, anchored to apple-docs:// for both arms (the v1.0.2
# audit confirms this URI shape is identical in v1.0.2 / v1.1.0 /
# v1.2.0 search.db schemas).
#
# When a regex legitimately matches multiple sibling URIs (e.g. the
# framework-root pattern matches every page under that framework),
# the *first* matching rank counts as the rank for that query. That
# matches the existing baseline's accounting.
CANONICAL_QUERIES = [
    # Swift stdlib types — Class A
    ("Hashable", r"apple-docs://swift/hashable(/|$)", "A", "stdlib protocol"),
    ("Equatable", r"apple-docs://swift/equatable(/|$)", "A", "stdlib protocol"),
    ("Comparable", r"apple-docs://swift/comparable(/|$)", "A", "stdlib protocol"),
    ("Codable", r"apple-docs://swift/codable(/|$)", "A", "stdlib typealias"),
    ("Sendable", r"apple-docs://swift/sendable(/|$)", "A", "stdlib protocol"),
    ("Sequence", r"apple-docs://swift/sequence(/|$)", "A", "stdlib protocol"),
    ("AsyncSequence", r"apple-docs://swift/asyncsequence(/|$)", "A", "stdlib protocol (async)"),
    ("Collection", r"apple-docs://swift/collection(/|$)", "A", "stdlib protocol"),
    ("Optional", r"apple-docs://swift/optional(/|$)", "A", "stdlib enum"),
    ("Result", r"apple-docs://swift/result(/|$)", "A", "stdlib enum"),
    ("Array", r"apple-docs://swift/array(/|$)", "A", "stdlib struct"),
    ("Dictionary", r"apple-docs://swift/dictionary(/|$)", "A", "stdlib struct"),
    ("Set", r"apple-docs://swift/set(/|$)", "A", "stdlib struct"),
    # Foundation — Class A
    ("URLSession", r"apple-docs://foundation/urlsession(/|$)", "A", "Foundation class"),
    ("JSONDecoder", r"apple-docs://foundation/jsondecoder(/|$)", "A", "Foundation class"),
    ("JSONEncoder", r"apple-docs://foundation/jsonencoder(/|$)", "A", "Foundation class"),
    ("DateFormatter", r"apple-docs://foundation/dateformatter(/|$)", "A", "Foundation class"),
    ("Data", r"apple-docs://foundation/data(/|$)", "A", "Foundation struct"),
    ("Date", r"apple-docs://foundation/date(/|$)", "A", "Foundation struct"),
    ("URL", r"apple-docs://foundation/url(/|$)", "A", "Foundation struct"),
    ("Bundle", r"apple-docs://foundation/bundle(/|$)", "A", "Foundation class"),
    ("FileManager", r"apple-docs://foundation/filemanager(/|$)", "A", "Foundation class"),
    ("NotificationCenter", r"apple-docs://foundation/notificationcenter(/|$)", "A", "Foundation class"),
    # SwiftUI — Class A
    ("Observable", r"apple-docs://(observation|swiftui)/observable(/|$)", "A", "Observation macro"),
    ("Observation", r"apple-docs://observation(/|$)", "A", "Observation module"),
    ("State property wrapper", r"apple-docs://swiftui/state(/|$)", "A", "SwiftUI property wrapper"),
    ("Binding", r"apple-docs://swiftui/binding(/|$)", "A", "SwiftUI property wrapper"),
    ("EnvironmentObject", r"apple-docs://swiftui/environmentobject(/|$)", "A", "SwiftUI"),
    ("StateObject", r"apple-docs://swiftui/stateobject(/|$)", "A", "SwiftUI"),
    ("ForEach", r"apple-docs://swiftui/foreach(/|$)", "A", "SwiftUI"),
    ("LazyVGrid", r"apple-docs://swiftui/lazyvgrid(/|$)", "A", "SwiftUI"),
    ("NavigationStack", r"apple-docs://swiftui/navigationstack(/|$)", "A", "SwiftUI"),
    # UIKit / AppKit — Class A
    ("UIColor", r"apple-docs://uikit/uicolor(/|$)", "A", "UIKit"),
    ("UIView", r"apple-docs://uikit/uiview(/|$)", "A", "UIKit"),
    ("UIViewController", r"apple-docs://uikit/uiviewcontroller(/|$)", "A", "UIKit"),
    ("NSView", r"apple-docs://appkit/nsview(/|$)", "A", "AppKit"),
    ("NSWindow", r"apple-docs://appkit/nswindow(/|$)", "A", "AppKit"),
    # Combine — Class A
    ("Combine Publisher", r"apple-docs://combine/publisher(/|$)", "A", "Combine"),
    ("AnyCancellable", r"apple-docs://combine/anycancellable(/|$)", "A", "Combine"),
    # Concurrency — Class A
    ("MainActor", r"apple-docs://swift/mainactor(/|$)", "A", "Concurrency"),
    ("Task", r"apple-docs://swift/task(/|$)", "A", "Concurrency"),
    ("TaskGroup", r"apple-docs://swift/taskgroup(/|$)", "A", "Concurrency"),
    # CoreData / MapKit / others mentioned in v1.0.2 diff
    ("CoreData", r"apple-docs://coredata(/|$)", "B", "framework root"),
    ("MapKit", r"apple-docs://mapkit(/|$)", "B", "framework root"),
    # Framework roots — Class B
    ("SwiftUI", r"apple-docs://swiftui(/|$)", "B", "framework root"),
    ("UIKit", r"apple-docs://uikit(/|$)", "B", "framework root"),
    ("AppKit", r"apple-docs://appkit(/|$)", "B", "framework root"),
    ("Foundation", r"apple-docs://foundation(/|$)", "B", "framework root"),
    ("Combine", r"apple-docs://combine(/|$)", "B", "framework root"),
    ("SwiftUI View", r"apple-docs://swiftui/view(/|$)", "A", "the View protocol (note: classic v1.0.2 failure case)"),
]


def run_cupertino_search(binary: str, search_db: str, query: str, limit: int = 10) -> list:
    """Invoke `cupertino search --format json` and return the parsed
    list of result dicts (each has at least a `uri` key). Empty list
    on parse failure."""
    cmd = [
        binary,
        "search",
        "--search-db", search_db,
        "--format", "json",
        "--limit", str(limit),
        query,
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return []
    if proc.returncode != 0:
        return []
    out = proc.stdout.strip()
    if not out:
        return []
    # v1.2.0 prefixes stdout with an ISO 8601 timestamp per line
    # (#780/#781). The JSON body starts at the first `{` or `[`.
    # Strip everything before the JSON header.
    idx_obj = out.find("{")
    idx_arr = out.find("[")
    starts = [i for i in (idx_obj, idx_arr) if i >= 0]
    if not starts:
        return []
    out = out[min(starts):]
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return []
    # cupertino search --format json returns either a top-level list or
    # an object with a "results" key depending on flags. Handle both.
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("results", "candidates", "items"):
            if key in data and isinstance(data[key], list):
                return data[key]
    return []


def score_query(binary: str, search_db: str, fixture: tuple) -> QueryOutcome:
    """Score a single Phase 1 fixture. `fixture` is a 4-tuple from
    `CANONICAL_QUERIES`: (query, right-answer regex, class, notes)."""
    query, pattern, qclass, notes = fixture
    rows = run_cupertino_search(binary, search_db, query, limit=10)
    # cupertino's search JSON uses `identifier` for the canonical
    # `apple-docs://framework/concept` URL; older / alternate paths
    # use `uri`. Try `identifier` first, fall back to `uri`.
    uris = [r.get("identifier") or r.get("uri", "") for r in rows][:10]
    rx = re.compile(pattern, re.IGNORECASE)
    first_rank = None
    matches_in_top_5 = 0
    dcg = 0.0
    for i, uri in enumerate(uris, start=1):
        if rx.search(uri):
            if first_rank is None:
                first_rank = i
            if i <= 5:
                matches_in_top_5 += 1
            # NDCG gain term: 1 per match, discounted by log2(i+1)
            dcg += 1.0 / math.log2(i + 1)
    rr = (1.0 / first_rank) if first_rank else 0.0
    p1 = 1 if first_rank == 1 else 0
    p5 = matches_in_top_5 / 5.0
    # Ideal DCG for single-relevant: gain=1 at rank 1 → 1/log2(2)=1.0
    # With multi-match (sibling URIs), the ideal would be the same N
    # matches packed at ranks 1..N. We use 1.0 as IDCG so NDCG > 1 is
    # possible — same accounting quirk as the v1.0.2 baseline §8.2.
    ndcg = dcg / 1.0
    return QueryOutcome(
        query=query, pattern=pattern, qclass=qclass, notes=notes,
        first_relevant_rank=first_rank, rr=rr, p_at_1=p1, p_at_5=p5,
        ndcg_at_10=ndcg, top_uris=uris,
    )


# MARK: Markdown writer
def write_versiondiff_md(
    out_path: Path, arm_a_label: str, arm_b_label: str,
    arm_a_agg: dict, arm_b_agg: dict, paired: dict,
    arm_a_meta: dict, arm_b_meta: dict, version_a: str, version_b: str,
):
    """Emit a versiondiff audit MD matching the existing
    `docs/audits/search-quality-versiondiff-v1.0.2-to-v1.2.0.md`
    structure so the dashboard renderer picks it up automatically."""
    b = paired["buckets"]
    mc = paired["mcnemar"]
    w = paired["wilcoxon"]
    delta_mrr = arm_b_agg["mrr"] - arm_a_agg["mrr"]
    delta_p1 = arm_b_agg["p_at_1"] - arm_a_agg["p_at_1"]
    delta_p5 = arm_b_agg["p_at_5_mean"] - arm_a_agg["p_at_5_mean"]
    delta_ndcg = arm_b_agg["ndcg_at_10_mean"] - arm_a_agg["ndcg_at_10_mean"]

    def fmt_list(xs, fallback="—"):
        return ", ".join(f"`{q}`" for q in xs) if xs else fallback

    md = f"""# Search-quality version diff: {version_a} → {version_b}

**Date:** 2026-05-20
**Arm A:** {arm_a_label} — `{arm_a_meta.get('binary','?')}` × `{arm_a_meta.get('db','?')}` ({arm_a_meta.get('schema','?')}, {arm_a_meta.get('docs','?')} docs)
**Arm B:** {arm_b_label} — `{arm_b_meta.get('binary','?')}` × `{arm_b_meta.get('db','?')}` ({arm_b_meta.get('schema','?')}, {arm_b_meta.get('docs','?')} docs)
**Methodology:** `docs/design/search-quality-eval.md` Phase 1 (Class A canonical lookup + Class B framework-root, paired comparison mode)
**Harness:** `scripts/eval/search-quality-phase1.py`
**Universal rule:** `../private/mihaela-agents/Rules/universal/search-quality-eval.md`
**Companion handbook:** `docs/database-handbook.md` §5

This is the Phase 1.8 version-to-version comparison KPI specified in issue #830, applied to the `{version_a}` → `{version_b}` jump. End-to-end measurement (binary + DB both swap between arms) so it captures the full user-felt delta, not a binary-held-constant or schema-held-constant slice.

---

## Aggregate

| Metric | {arm_a_label} | {arm_b_label} | Delta |
|---|---|---|---|
| N queries | {arm_a_agg['n']} | {arm_b_agg['n']} | — |
| **MRR** | **{arm_a_agg['mrr']:.4f}** | **{arm_b_agg['mrr']:.4f}** | **{delta_mrr:+.4f}** |
| P@1 | {arm_a_agg['p_at_1']:.4f} ({arm_a_agg['p_at_1_count']} / {arm_a_agg['n']}) | {arm_b_agg['p_at_1']:.4f} ({arm_b_agg['p_at_1_count']} / {arm_b_agg['n']}) | {delta_p1:+.4f} |
| P@5 | {arm_a_agg['p_at_5_mean']:.4f} | {arm_b_agg['p_at_5_mean']:.4f} | {delta_p5:+.4f} |
| NDCG@10 | {arm_a_agg['ndcg_at_10_mean']:.4f} | {arm_b_agg['ndcg_at_10_mean']:.4f} | {delta_ndcg:+.4f} |

**Headline:** {len(b['added']) + len(b['fixed'])} / {arm_a_agg['n']} queries newly rank-1 in {version_b} (Added + Fixed); {len(b['removed'])} regression.

---

## Paired statistical tests

**Paired Wilcoxon signed-rank on per-query RR (B vs A):**

- N_nonzero = {w['n_nonzero']}
- W+ = {w['W_plus']:.2f}, W− = {w.get('W_minus', 0):.2f}
- Two-sided p = {w['p_two_sided']:.6f}
- One-sided p ({version_b} > {version_a}) = {w['p_one_sided_b_gt_a']:.6f}

**McNemar on rank-1 outcome:**

|  | {version_b} rank-1 | {version_b} not rank-1 |
|---|---|---|
| **{version_a} rank-1** | {mc['both_rank1']} (concordant +) | {mc['a_only_rank1']} (regression) |
| **{version_a} not rank-1** | {mc['b_only_rank1']} (improvement) | {mc['neither_rank1']} (concordant −) |

- Discordant pairs: b = {mc['a_only_rank1']}, c = {mc['b_only_rank1']}
- McNemar exact (binomial), two-sided p = **{mc['p_two_sided']:.6f}**

---

## Buckets

| Bucket | Count | Definition | Queries |
|---|---|---|---|
| **Added** | **{len(b['added'])}** | Was outside top 10 in {version_a}, now rank-1 in {version_b} | {fmt_list(b['added'])} |
| **Removed** | **{len(b['removed'])}** | Was rank-1 in {version_a}, no longer rank-1 in {version_b} | {fmt_list(b['removed'])} |
| **Fixed** | **{len(b['fixed'])}** | Was found in {version_a} but below rank 1, now rank-1 in {version_b} | {fmt_list(b['fixed'])} |
| **Degraded** | **{len(b['degraded'])}** | First-relevant rank moved further from rank 1 | {fmt_list(b['degraded'])} |
| Unchanged (both rank-1) | {len(b['unchanged_rank1'])} | Same rank-1 outcome in both versions | majority of the corpus |
| Both still suboptimal | {len(b['both_suboptimal'])} | Neither version returned a relevant doc at rank 1 | {fmt_list(b['both_suboptimal'])} |

---

## Method recap

Single-token canonical-lookup queries (Class A) + framework-root queries (Class B) from `scripts/eval/search-quality-phase1.py`'s `CANONICAL_QUERIES` corpus. For each query: `cupertino search --search-db <db> --format json --limit 10 "<query>"`, parse the URI list, check each against the per-query right-answer regex, record the first matching rank. Per-query reciprocal rank = 1 / first_rank (0 if no match in top 10). NDCG@10 uses gain=1 per match, IDCG=1 (multi-match sibling URIs can push NDCG > 1 as documented in `docs/design/search-quality-eval.md` §8.2; this is preserved here for comparability with the v1.0.2 audit).

---

## What this measurement does NOT capture

Same caveats as `search-quality-versiondiff-v1.0.2-to-v1.2.0.md`:

- **Criterion 2 (anti-hallucination).** Whether an AI agent given the {version_b} top-K actually produces correct Swift. Phase 1.7 (`docs/design/anti-hallucination-eval.md`).
- **Per-query class breakdown.** The seven Phase 1.x classes (deprecation, cross-source, fragment, acronym, prose, symbol-attribute, agent-end-to-end) each have their own audit. This version diff is restricted to **class A + class B**.
- **Coverage signals.** The v1.2.0 round shipped `apple_imports_json` (1/183 → 164/183) and `swift_tools_version` (0/183 → 182/183) coverage on packages.db, but the canonical-lookup corpus doesn't query packages. Those gains land in a separate packages-side audit that doesn't exist yet.
"""
    out_path.write_text(md)


# MARK: CLI
def main():
    ap = make_argparser("Phase 1 (search canonical-lookup)")
    args = ap.parse_args()
    run_main(args, corpus=CANONICAL_QUERIES, score_fn=score_query, md_writer=write_versiondiff_md, phase_name="phase1")


if __name__ == "__main__":
    main()

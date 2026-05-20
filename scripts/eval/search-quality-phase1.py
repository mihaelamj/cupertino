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
import argparse
import json
import math
import re
import statistics
import subprocess
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

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


@dataclass
class QueryOutcome:
    query: str
    pattern: str
    qclass: str
    notes: str
    first_relevant_rank: Optional[int]   # 1-indexed; None if no relevant URI in top 10
    rr: float                            # reciprocal rank; 0 if no relevant URI
    p_at_1: int                          # 1 if rank 1 matches, else 0
    p_at_5: float                        # fraction of top-5 that match (out of top 5)
    ndcg_at_10: float                    # standard NDCG@10 with single-relevant assumption (gain = 1 per match)
    top_uris: list                       # first 10 URIs for audit


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


def score_query(binary: str, search_db: str, query: str, pattern: str, qclass: str, notes: str) -> QueryOutcome:
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


def aggregate(outcomes: list) -> dict:
    n = len(outcomes)
    if n == 0:
        return {}
    return {
        "n": n,
        "p_at_1_count": sum(o.p_at_1 for o in outcomes),
        "p_at_1": sum(o.p_at_1 for o in outcomes) / n,
        "p_at_5_mean": statistics.mean(o.p_at_5 for o in outcomes),
        "mrr": statistics.mean(o.rr for o in outcomes),
        "ndcg_at_10_mean": statistics.mean(o.ndcg_at_10 for o in outcomes),
        "not_in_top_10": sum(1 for o in outcomes if o.first_relevant_rank is None),
    }


def wilcoxon_signed_rank_one_sided(deltas: list) -> dict:
    """Paired Wilcoxon signed-rank, one-sided (test that arm B > arm A).
    `deltas` is the per-query (RR_B - RR_A) vector. Zero deltas are
    discarded per the standard convention. Returns W, two-sided p,
    one-sided p, N_nonzero. Uses a normal approximation since N is
    typically ≥ 10."""
    nz = [d for d in deltas if d != 0.0]
    n = len(nz)
    if n == 0:
        return {"W_plus": 0, "p_two_sided": 1.0, "p_one_sided_b_gt_a": 1.0, "n_nonzero": 0}
    # Rank absolute values, average ties
    abs_pairs = sorted(((abs(d), d) for d in nz), key=lambda x: x[0])
    ranks = [0] * n
    i = 0
    while i < n:
        j = i
        while j + 1 < n and abs_pairs[j + 1][0] == abs_pairs[i][0]:
            j += 1
        avg_rank = (i + 1 + j + 1) / 2
        for k in range(i, j + 1):
            ranks[k] = avg_rank
        i = j + 1
    w_plus = sum(r for r, (_, d) in zip(ranks, abs_pairs) if d > 0)
    w_minus = sum(r for r, (_, d) in zip(ranks, abs_pairs) if d < 0)
    # Normal approximation
    mean = n * (n + 1) / 4
    var = n * (n + 1) * (2 * n + 1) / 24
    if var == 0:
        return {"W_plus": w_plus, "p_two_sided": 1.0, "p_one_sided_b_gt_a": 1.0, "n_nonzero": n}
    z = (w_plus - mean) / math.sqrt(var)
    # one-sided p that arm B > arm A (i.e. w_plus large)
    p_one = 0.5 * (1 - math.erf(z / math.sqrt(2)))
    p_two = 2 * min(p_one, 1 - p_one)
    return {
        "W_plus": w_plus, "W_minus": w_minus,
        "p_two_sided": p_two, "p_one_sided_b_gt_a": p_one,
        "n_nonzero": n, "z": z,
    }


def mcnemar_p_two_sided(b: int, c: int) -> float:
    """Exact McNemar (binomial) two-sided p. b = was-rank-1 in A, not
    in B; c = was-not-rank-1 in A, is-rank-1 in B. Discordant pairs."""
    n = b + c
    if n == 0:
        return 1.0
    # exact binomial: sum P(X <= min(b,c)) + P(X >= max(b,c)) with p=0.5
    m = min(b, c)
    # P(X <= m) + P(X >= n - m); symmetric so 2 * P(X <= m) clamped to 1
    from math import comb
    tail = sum(comb(n, k) for k in range(0, m + 1)) / (2 ** n)
    p = min(2 * tail, 1.0)
    return p


def paired_compare(arm_a_outcomes: list, arm_b_outcomes: list) -> dict:
    assert len(arm_a_outcomes) == len(arm_b_outcomes), "arm lengths must match"
    buckets = {"added": [], "removed": [], "fixed": [], "degraded": [], "unchanged_rank1": [], "both_suboptimal": []}
    deltas = []
    a_rank1 = b_rank1 = both_rank1 = 0
    for a, b in zip(arm_a_outcomes, arm_b_outcomes):
        assert a.query == b.query
        a_top10 = a.first_relevant_rank is not None
        b_top10 = b.first_relevant_rank is not None
        a1 = a.first_relevant_rank == 1
        b1 = b.first_relevant_rank == 1
        if a1: a_rank1 += 1
        if b1: b_rank1 += 1
        if a1 and b1: both_rank1 += 1

        deltas.append(b.rr - a.rr)

        # Bucket per the v1.0.2 audit's definitions
        if (not a_top10) and b1:
            buckets["added"].append(a.query)
        elif a1 and (not b1):
            buckets["removed"].append(a.query)
        elif a_top10 and (not a1) and b1:
            buckets["fixed"].append(a.query)
        elif a1 and b1:
            buckets["unchanged_rank1"].append(a.query)
        elif (a.first_relevant_rank and b.first_relevant_rank
              and b.first_relevant_rank > a.first_relevant_rank):
            buckets["degraded"].append(
                f"{a.query} (rank {a.first_relevant_rank} → rank {b.first_relevant_rank})"
            )
        elif not a1 and not b1 and not (b.first_relevant_rank and a.first_relevant_rank and b.first_relevant_rank < a.first_relevant_rank):
            buckets["both_suboptimal"].append(a.query)

    # McNemar matrix on rank-1 outcome
    a_only = a_rank1 - both_rank1   # rank-1 in A, not in B (== b in McNemar)
    b_only = b_rank1 - both_rank1   # rank-1 in B, not in A (== c in McNemar)
    neither = len(arm_a_outcomes) - both_rank1 - a_only - b_only

    mcnemar_p = mcnemar_p_two_sided(a_only, b_only)
    wilcoxon = wilcoxon_signed_rank_one_sided(deltas)

    return {
        "buckets": buckets,
        "mcnemar": {
            "both_rank1": both_rank1,
            "a_only_rank1": a_only,
            "b_only_rank1": b_only,
            "neither_rank1": neither,
            "p_two_sided": mcnemar_p,
        },
        "wilcoxon": wilcoxon,
    }


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
    ap = argparse.ArgumentParser()
    # Single-arm mode
    ap.add_argument("--binary", help="single-arm: cupertino binary path")
    ap.add_argument("--search-db", help="single-arm: search.db path")
    ap.add_argument("--label", default="single", help="single-arm: arm label")
    # Paired-arm mode
    ap.add_argument("--arm-a-binary")
    ap.add_argument("--arm-a-search-db")
    ap.add_argument("--arm-a-label", default="A")
    ap.add_argument("--arm-a-version", default="A")
    ap.add_argument("--arm-b-binary")
    ap.add_argument("--arm-b-search-db")
    ap.add_argument("--arm-b-label", default="B")
    ap.add_argument("--arm-b-version", default="B")
    # Output
    ap.add_argument("--out", help="JSON results dump path", required=False)
    ap.add_argument("--md-out", help="paired-mode markdown audit output path")
    args = ap.parse_args()

    def run_arm(binary: str, db: str, label: str) -> tuple:
        outcomes = []
        n = len(CANONICAL_QUERIES)
        for i, (q, rx, qc, notes) in enumerate(CANONICAL_QUERIES, start=1):
            out = score_query(binary, db, q, rx, qc, notes)
            outcomes.append(out)
            print(f"  [{label}] {i:2}/{n}  {q:<28}  rank={out.first_relevant_rank}  rr={out.rr:.4f}", file=sys.stderr)
        return outcomes, aggregate(outcomes)

    paired_mode = bool(args.arm_a_binary and args.arm_b_binary)

    if paired_mode:
        print(f"==> Arm A: {args.arm_a_label}", file=sys.stderr)
        arm_a_outcomes, arm_a_agg = run_arm(args.arm_a_binary, args.arm_a_search_db, "A")
        print(f"==> Arm B: {args.arm_b_label}", file=sys.stderr)
        arm_b_outcomes, arm_b_agg = run_arm(args.arm_b_binary, args.arm_b_search_db, "B")
        paired = paired_compare(arm_a_outcomes, arm_b_outcomes)

        # DB stat for the audit MD
        import sqlite3
        def db_stat(p):
            conn = sqlite3.connect(p)
            v = conn.execute("PRAGMA user_version;").fetchone()[0]
            n = conn.execute("SELECT COUNT(*) FROM docs_metadata;").fetchone()[0]
            conn.close()
            return {"schema": f"v{v}", "docs": f"{n:,}"}

        arm_a_meta = {"binary": args.arm_a_binary, "db": args.arm_a_search_db, **db_stat(args.arm_a_search_db)}
        arm_b_meta = {"binary": args.arm_b_binary, "db": args.arm_b_search_db, **db_stat(args.arm_b_search_db)}

        if args.out:
            Path(args.out).write_text(json.dumps({
                "arm_a": {"label": args.arm_a_label, "meta": arm_a_meta, "agg": arm_a_agg, "outcomes": [asdict(o) for o in arm_a_outcomes]},
                "arm_b": {"label": args.arm_b_label, "meta": arm_b_meta, "agg": arm_b_agg, "outcomes": [asdict(o) for o in arm_b_outcomes]},
                "paired": paired,
            }, indent=2, default=str))
            print(f"==> JSON dump: {args.out}", file=sys.stderr)

        if args.md_out:
            write_versiondiff_md(
                Path(args.md_out),
                arm_a_label=args.arm_a_label, arm_b_label=args.arm_b_label,
                arm_a_agg=arm_a_agg, arm_b_agg=arm_b_agg, paired=paired,
                arm_a_meta=arm_a_meta, arm_b_meta=arm_b_meta,
                version_a=args.arm_a_version, version_b=args.arm_b_version,
            )
            print(f"==> Markdown audit: {args.md_out}", file=sys.stderr)

        # Stdout summary
        print(f"\n==> Summary")
        print(f"  Arm A MRR: {arm_a_agg['mrr']:.4f}   P@1: {arm_a_agg['p_at_1']:.4f}")
        print(f"  Arm B MRR: {arm_b_agg['mrr']:.4f}   P@1: {arm_b_agg['p_at_1']:.4f}")
        print(f"  Delta MRR: {arm_b_agg['mrr'] - arm_a_agg['mrr']:+.4f}")
        print(f"  McNemar two-sided p: {paired['mcnemar']['p_two_sided']:.6f}")
        print(f"  Wilcoxon one-sided (B > A) p: {paired['wilcoxon']['p_one_sided_b_gt_a']:.6f}")
    else:
        if not args.binary or not args.search_db:
            ap.error("Single-arm mode needs --binary AND --search-db (or use paired-arm with --arm-a-* and --arm-b-* flags)")
        outcomes, agg = run_arm(args.binary, args.search_db, args.label)
        if args.out:
            Path(args.out).write_text(json.dumps({
                "label": args.label, "agg": agg,
                "outcomes": [asdict(o) for o in outcomes],
            }, indent=2, default=str))
        print(f"\n==> Summary [{args.label}]")
        print(f"  N: {agg['n']}")
        print(f"  MRR: {agg['mrr']:.4f}")
        print(f"  P@1: {agg['p_at_1']:.4f} ({agg['p_at_1_count']}/{agg['n']})")
        print(f"  P@5 (mean): {agg['p_at_5_mean']:.4f}")
        print(f"  NDCG@10 (mean): {agg['ndcg_at_10_mean']:.4f}")
        print(f"  not in top-10: {agg['not_in_top_10']}")


if __name__ == "__main__":
    main()

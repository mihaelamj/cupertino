#!/usr/bin/env python3
"""
Phase 1 extended harness — multi-corpus paired-comparison.

Sibling of `search-quality-phase1.py` (Class A + B canonical lookup,
50 queries). This script adds two more independent corpora so we can
cross-validate the v1.2.0 > v1.1.0 claim across query shapes that
exercise different code paths in the ranker:

- **CANONICAL_LOOKUP_V2** (Class A + B, ~30 queries, NO overlap with
  `search-quality-phase1.py`'s CANONICAL_QUERIES corpus). Confirms
  that the v1.1.0 → v1.2.0 delta isn't a quirk of the first corpus.
- **DEPRECATION_PAIRS** (Class C, 30 (modern, legacy) pairs). Tests
  whether the ranker correctly favours the modern Swift form over
  the legacy NS-prefixed form. Source: harvested verbatim from the
  existing `docs/audits/search-quality-deprecation-baseline-v1.2.0.md`
  audit's prose table.

Both corpora produce paired comparison MD files matching the existing
versiondiff audit shape so `regen-all.sh`'s glob picks them up.

Reproducibility: same `cupertino search` binary + DB pair. No
randomisation. Two consecutive runs against the same inputs produce
identical metrics (verified for the canonical corpus before this
extension landed).
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


# ============================================================
# CORPUS 1: Canonical lookup V2 (independent of phase1.py's set)
# Class A + B, no overlap with the original 50-query corpus.
# Sourced from Apple framework knowledge; right-answer pattern is
# `apple-docs://<framework>/<concept>($|/...)`.
# ============================================================
CANONICAL_LOOKUP_V2 = [
    # Swift stdlib (different ones from corpus 1)
    ("Range", r"apple-docs://swift/range(/|$)", "A", "stdlib struct"),
    ("Numeric", r"apple-docs://swift/numeric(/|$)", "A", "stdlib protocol"),
    ("Strideable", r"apple-docs://swift/strideable(/|$)", "A", "stdlib protocol"),
    ("Iterator", r"apple-docs://swift/iteratorprotocol(/|$)", "A", "stdlib protocol"),
    ("withUnsafePointer", r"apple-docs://swift/withunsafepointer(.*)?(/|$)", "A", "stdlib function"),
    # Foundation (different ones)
    ("URLComponents", r"apple-docs://foundation/urlcomponents(/|$)", "A", "Foundation struct"),
    ("URLRequest", r"apple-docs://foundation/urlrequest(/|$)", "A", "Foundation struct"),
    ("UUID", r"apple-docs://foundation/uuid(/|$)", "A", "Foundation struct"),
    ("Locale", r"apple-docs://foundation/locale(/|$)", "A", "Foundation struct"),
    ("Calendar", r"apple-docs://foundation/calendar(/|$)", "A", "Foundation struct"),
    ("TimeZone", r"apple-docs://foundation/timezone(/|$)", "A", "Foundation struct"),
    # SwiftUI (different)
    ("VStack", r"apple-docs://swiftui/vstack(/|$)", "A", "SwiftUI"),
    ("HStack", r"apple-docs://swiftui/hstack(/|$)", "A", "SwiftUI"),
    ("ZStack", r"apple-docs://swiftui/zstack(/|$)", "A", "SwiftUI"),
    ("Picker", r"apple-docs://swiftui/picker(/|$)", "A", "SwiftUI"),
    ("Image", r"apple-docs://swiftui/image(/|$)", "A", "SwiftUI"),
    # UIKit (different)
    ("UIImage", r"apple-docs://uikit/uiimage(/|$)", "A", "UIKit"),
    ("UILabel", r"apple-docs://uikit/uilabel(/|$)", "A", "UIKit"),
    ("UIButton", r"apple-docs://uikit/uibutton(/|$)", "A", "UIKit"),
    # AppKit (different)
    ("NSButton", r"apple-docs://appkit/nsbutton(/|$)", "A", "AppKit"),
    # Combine (different)
    ("PassthroughSubject", r"apple-docs://combine/passthroughsubject(/|$)", "A", "Combine"),
    ("CurrentValueSubject", r"apple-docs://combine/currentvaluesubject(/|$)", "A", "Combine"),
    # Concurrency (different)
    ("AsyncStream", r"apple-docs://swift/asyncstream(/|$)", "A", "Concurrency"),
    ("Continuation", r"apple-docs://swift/(checked|unsafe|asyncthrowingstream/)?continuation(/|$)", "A", "Concurrency (accepts CheckedContinuation, UnsafeContinuation, AsyncThrowingStream.Continuation)"),
    # Frameworks (different roots)
    ("CoreGraphics", r"apple-docs://coregraphics(/|$)", "B", "framework root"),
    ("CoreImage", r"apple-docs://coreimage(/|$)", "B", "framework root"),
    ("AVFoundation", r"apple-docs://avfoundation(/|$)", "B", "framework root"),
    ("MetricKit", r"apple-docs://metrickit(/|$)", "B", "framework root"),
    ("OSLog", r"apple-docs://os(/|$)", "B", "framework root (os module → Logger)"),
    ("CryptoKit", r"apple-docs://cryptokit(/|$)", "B", "framework root"),
]


# ============================================================
# CORPUS 2: Deprecation pairs (Class C)
# 30 (modern_query, modern_uri_regex, legacy_uri_regex) triples
# harvested verbatim from the existing
# docs/audits/search-quality-deprecation-baseline-v1.2.0.md prose:
# - Foundation value-type vs NS-class (27 pairs)
# - Swift stdlib vs NS-class (3 pairs)
# Outcome per pair: did modern rank above legacy in top-10?
# ============================================================
DEPRECATION_PAIRS = [
    # query, modern_uri_regex, legacy_uri_regex
    ("URL", r"apple-docs://foundation/url(/|$)", r"apple-docs://foundation/nsurl(/|$)"),
    ("NSURL", r"apple-docs://foundation/nsurl(/|$)", r"apple-docs://foundation/url(/|$)"),  # reverse-order check
    ("Data", r"apple-docs://foundation/data(/|$)", r"apple-docs://foundation/nsdata(/|$)"),
    ("Date", r"apple-docs://foundation/date(/|$)", r"apple-docs://foundation/nsdate(/|$)"),
    ("UUID", r"apple-docs://foundation/uuid(/|$)", r"apple-docs://foundation/nsuuid(/|$)"),
    ("URLSession", r"apple-docs://foundation/urlsession(/|$)", r"apple-docs://foundation/nsurlsession(/|$)"),
    ("FileManager", r"apple-docs://foundation/filemanager(/|$)", r"apple-docs://foundation/nsfilemanager(/|$)"),
    ("DateFormatter", r"apple-docs://foundation/dateformatter(/|$)", r"apple-docs://foundation/nsdateformatter(/|$)"),
    ("Bundle", r"apple-docs://foundation/bundle(/|$)", r"apple-docs://foundation/nsbundle(/|$)"),
    ("Calendar", r"apple-docs://foundation/calendar(/|$)", r"apple-docs://foundation/nscalendar(/|$)"),
    ("TimeZone", r"apple-docs://foundation/timezone(/|$)", r"apple-docs://foundation/nstimezone(/|$)"),
    ("Locale", r"apple-docs://foundation/locale(/|$)", r"apple-docs://foundation/nslocale(/|$)"),
    ("Predicate", r"apple-docs://foundation/predicate(/|$)", r"apple-docs://foundation/nspredicate(/|$)"),
    ("AttributedString", r"apple-docs://foundation/attributedstring(/|$)", r"apple-docs://foundation/nsattributedstring(/|$)"),
    ("Measurement", r"apple-docs://foundation/measurement(/|$)", r"apple-docs://foundation/nsmeasurement(/|$)"),
    ("URLRequest", r"apple-docs://foundation/urlrequest(/|$)", r"apple-docs://foundation/nsurlrequest(/|$)"),
    ("URLComponents", r"apple-docs://foundation/urlcomponents(/|$)", r"apple-docs://foundation/nsurlcomponents(/|$)"),
    ("DateComponents", r"apple-docs://foundation/datecomponents(/|$)", r"apple-docs://foundation/nsdatecomponents(/|$)"),
    ("DateInterval", r"apple-docs://foundation/dateinterval(/|$)", r"apple-docs://foundation/nsdateinterval(/|$)"),
    ("Decimal", r"apple-docs://foundation/decimal(/|$)", r"apple-docs://foundation/nsdecimalnumber(/|$)"),
    ("IndexSet", r"apple-docs://foundation/indexset(/|$)", r"apple-docs://foundation/nsindexset(/|$)"),
    ("IndexPath", r"apple-docs://foundation/indexpath(/|$)", r"apple-docs://foundation/nsindexpath(/|$)"),
    ("CharacterSet", r"apple-docs://foundation/characterset(/|$)", r"apple-docs://foundation/nscharacterset(/|$)"),
    ("PersonNameComponents", r"apple-docs://foundation/personnamecomponents(/|$)", r"apple-docs://foundation/nspersonnamecomponents(/|$)"),
    ("PersonNameComponentsFormatter", r"apple-docs://foundation/personnamecomponentsformatter(/|$)", r"apple-docs://foundation/nspersonnamecomponentsformatter(/|$)"),
    ("OperationQueue", r"apple-docs://foundation/operationqueue(/|$)", r"apple-docs://foundation/nsoperationqueue(/|$)"),
    ("Notification", r"apple-docs://foundation/notification(/|$)", r"apple-docs://foundation/nsnotification(/|$)"),
    # Swift stdlib vs NS-class (3 pairs)
    ("String", r"apple-docs://swift/string(/|$)", r"apple-docs://foundation/nsstring(/|$)"),
    ("Array", r"apple-docs://swift/array(/|$)", r"apple-docs://foundation/nsarray(/|$)"),
    ("Dictionary", r"apple-docs://swift/dictionary(/|$)", r"apple-docs://foundation/nsdictionary(/|$)"),
]


def run_cupertino_search(binary: str, search_db: str, query: str, limit: int = 10) -> list:
    cmd = [binary, "search", "--search-db", search_db, "--format", "json", "--limit", str(limit), query]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return []
    if proc.returncode != 0:
        return []
    out = proc.stdout.strip()
    if not out:
        return []
    # Strip v1.2.0's ISO 8601 stdout prefix.
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
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("candidates", "results", "items"):
            if key in data and isinstance(data[key], list):
                return data[key]
    return []


def first_match_rank(uris: list, pattern: str) -> Optional[int]:
    rx = re.compile(pattern, re.IGNORECASE)
    for i, uri in enumerate(uris, start=1):
        if rx.search(uri or ""):
            return i
    return None


# ============================================================
# Canonical-lookup harness (reuses phase1.py's scoring shape)
# ============================================================
@dataclass
class CanonicalOutcome:
    query: str
    pattern: str
    qclass: str
    notes: str
    first_relevant_rank: Optional[int]
    rr: float
    p_at_1: int
    p_at_5: float
    ndcg_at_10: float
    top_uris: list


def score_canonical(binary: str, db: str, q: str, pat: str, qc: str, notes: str) -> CanonicalOutcome:
    rows = run_cupertino_search(binary, db, q, limit=10)
    uris = [r.get("identifier") or r.get("uri", "") for r in rows][:10]
    rx = re.compile(pat, re.IGNORECASE)
    first_rank = None
    matches_in_top_5 = 0
    dcg = 0.0
    for i, uri in enumerate(uris, start=1):
        if rx.search(uri):
            if first_rank is None:
                first_rank = i
            if i <= 5:
                matches_in_top_5 += 1
            dcg += 1.0 / math.log2(i + 1)
    rr = (1.0 / first_rank) if first_rank else 0.0
    return CanonicalOutcome(q, pat, qc, notes, first_rank, rr, 1 if first_rank == 1 else 0,
                             matches_in_top_5 / 5.0, dcg / 1.0, uris)


# ============================================================
# Deprecation harness
# ============================================================
@dataclass
class DeprecationOutcome:
    query: str
    modern_pattern: str
    legacy_pattern: str
    modern_rank: Optional[int]
    legacy_rank: Optional[int]
    outcome: str  # "modern_wins", "legacy_wins", "both_missing", "modern_only", "legacy_only", "tied"


def score_deprecation(binary: str, db: str, q: str, modern_pat: str, legacy_pat: str) -> DeprecationOutcome:
    rows = run_cupertino_search(binary, db, q, limit=10)
    uris = [r.get("identifier") or r.get("uri", "") for r in rows][:10]
    modern_rank = first_match_rank(uris, modern_pat)
    legacy_rank = first_match_rank(uris, legacy_pat)
    if modern_rank is None and legacy_rank is None:
        outcome = "both_missing"
    elif modern_rank is not None and legacy_rank is None:
        outcome = "modern_only"
    elif modern_rank is None and legacy_rank is not None:
        outcome = "legacy_only"
    elif modern_rank == legacy_rank:
        outcome = "tied"
    elif modern_rank < legacy_rank:
        outcome = "modern_wins"
    else:
        outcome = "legacy_wins"
    return DeprecationOutcome(q, modern_pat, legacy_pat, modern_rank, legacy_rank, outcome)


# ============================================================
# Stats
# ============================================================
def wilcoxon_signed_rank_one_sided(deltas: list) -> dict:
    nz = [d for d in deltas if d != 0.0]
    n = len(nz)
    if n == 0:
        return {"W_plus": 0, "p_two_sided": 1.0, "p_one_sided_b_gt_a": 1.0, "n_nonzero": 0}
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
    mean = n * (n + 1) / 4
    var = n * (n + 1) * (2 * n + 1) / 24
    if var == 0:
        return {"W_plus": w_plus, "p_two_sided": 1.0, "p_one_sided_b_gt_a": 1.0, "n_nonzero": n}
    z = (w_plus - mean) / math.sqrt(var)
    p_one = 0.5 * (1 - math.erf(z / math.sqrt(2)))
    p_two = 2 * min(p_one, 1 - p_one)
    return {"W_plus": w_plus, "W_minus": w_minus, "p_two_sided": p_two,
            "p_one_sided_b_gt_a": p_one, "n_nonzero": n, "z": z}


def mcnemar_p_two_sided(b: int, c: int) -> float:
    n = b + c
    if n == 0:
        return 1.0
    from math import comb
    m = min(b, c)
    tail = sum(comb(n, k) for k in range(0, m + 1)) / (2 ** n)
    return min(2 * tail, 1.0)


def aggregate_canonical(outcomes: list) -> dict:
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


def paired_canonical_compare(a_outs: list, b_outs: list) -> dict:
    buckets = {"added": [], "removed": [], "fixed": [], "degraded": [], "unchanged_rank1": [], "both_suboptimal": []}
    deltas = []
    a_r1 = b_r1 = both_r1 = 0
    for a, b in zip(a_outs, b_outs):
        a_top = a.first_relevant_rank is not None
        b_top = b.first_relevant_rank is not None
        a1 = a.first_relevant_rank == 1
        b1 = b.first_relevant_rank == 1
        if a1: a_r1 += 1
        if b1: b_r1 += 1
        if a1 and b1: both_r1 += 1
        deltas.append(b.rr - a.rr)
        if (not a_top) and b1:
            buckets["added"].append(a.query)
        elif a1 and (not b1):
            buckets["removed"].append(a.query)
        elif a_top and (not a1) and b1:
            buckets["fixed"].append(a.query)
        elif a1 and b1:
            buckets["unchanged_rank1"].append(a.query)
        elif a.first_relevant_rank and b.first_relevant_rank and b.first_relevant_rank > a.first_relevant_rank:
            buckets["degraded"].append(f"{a.query} (rank {a.first_relevant_rank} → rank {b.first_relevant_rank})")
        elif not a1 and not b1:
            buckets["both_suboptimal"].append(a.query)
    a_only = a_r1 - both_r1
    b_only = b_r1 - both_r1
    neither = len(a_outs) - both_r1 - a_only - b_only
    return {
        "buckets": buckets,
        "mcnemar": {"both_rank1": both_r1, "a_only_rank1": a_only, "b_only_rank1": b_only,
                    "neither_rank1": neither, "p_two_sided": mcnemar_p_two_sided(a_only, b_only)},
        "wilcoxon": wilcoxon_signed_rank_one_sided(deltas),
    }


def paired_deprecation_compare(a_outs: list, b_outs: list) -> dict:
    # Count outcomes per arm
    def counts(outs):
        c = {"modern_wins": 0, "legacy_wins": 0, "both_missing": 0,
             "modern_only": 0, "legacy_only": 0, "tied": 0}
        for o in outs:
            c[o.outcome] += 1
        return c

    a_c = counts(a_outs)
    b_c = counts(b_outs)

    # Per-pair transitions: did the query's "modern_wins" status change between arms?
    transitions = {"a_lose_b_win": [], "a_win_b_lose": [], "both_win": [], "both_lose": [], "other": []}
    for a, b in zip(a_outs, b_outs):
        a_win = a.outcome in ("modern_wins", "modern_only")
        b_win = b.outcome in ("modern_wins", "modern_only")
        if a_win and b_win:
            transitions["both_win"].append(a.query)
        elif not a_win and b_win:
            transitions["a_lose_b_win"].append(a.query)
        elif a_win and not b_win:
            transitions["a_win_b_lose"].append(a.query)
        else:
            transitions["both_lose"].append(a.query)
    return {"arm_a_counts": a_c, "arm_b_counts": b_c, "transitions": transitions}


# ============================================================
# Markdown writers
# ============================================================
def write_canonical_md(out_path: Path, corpus_name: str, arm_a_label: str, arm_b_label: str,
                       a_agg: dict, b_agg: dict, paired: dict, a_meta: dict, b_meta: dict,
                       version_a: str, version_b: str):
    b = paired["buckets"]; mc = paired["mcnemar"]; w = paired["wilcoxon"]
    delta_mrr = b_agg["mrr"] - a_agg["mrr"]
    delta_p1 = b_agg["p_at_1"] - a_agg["p_at_1"]
    rank1_added_or_fixed = len(b["added"]) + len(b["fixed"])
    rank1_removed = len(b["removed"])
    status = "Strong" if (rank1_removed == 0 and delta_mrr > 0) else ("Mixed" if delta_mrr > 0 else "Weak")
    headline = f"+{rank1_added_or_fixed} / {a_agg['n']} queries newly rank-1"

    def fmt_list(xs, fallback="—"):
        return ", ".join(f"`{q}`" for q in xs) if xs else fallback

    md = f"""# Search-quality version diff: {version_a} → {version_b} ({corpus_name})

**Date:** 2026-05-21
**Status:** {status}
**Headline:** {headline}
**Corpus:** {corpus_name} — independent of `search-quality-versiondiff-v1.1.0-to-v1.2.0.md`'s 50-query corpus (zero overlap, different queries chosen to cross-validate)
**Arm A:** {arm_a_label} — `{a_meta.get('binary','?')}` × `{a_meta.get('db','?')}` ({a_meta.get('schema','?')}, {a_meta.get('docs','?')} docs)
**Arm B:** {arm_b_label} — `{b_meta.get('binary','?')}` × `{b_meta.get('db','?')}` ({b_meta.get('schema','?')}, {b_meta.get('docs','?')} docs)
**Methodology:** `docs/design/search-quality-eval.md` Phase 1 (Class A + B, paired-comparison mode)
**Harness:** `scripts/eval/search-quality-phase1-extended.py`
**Universal rule:** `../private/mihaela-agents/Rules/universal/search-quality-eval.md`

This is a cross-validation corpus. The v1.1.0 → v1.2.0 claim ("v1.2.0 is better") is being independently re-verified with a different fixed query set so the result isn't a quirk of the first corpus. The two corpora share zero queries.

---

## Aggregate

| Metric | {arm_a_label} | {arm_b_label} | Delta |
|---|---|---|---|
| N queries | {a_agg['n']} | {b_agg['n']} | — |
| **MRR** | **{a_agg['mrr']:.4f}** | **{b_agg['mrr']:.4f}** | **{delta_mrr:+.4f}** |
| P@1 | {a_agg['p_at_1']:.4f} ({a_agg['p_at_1_count']} / {a_agg['n']}) | {b_agg['p_at_1']:.4f} ({b_agg['p_at_1_count']} / {b_agg['n']}) | {delta_p1:+.4f} |
| P@5 (mean) | {a_agg['p_at_5_mean']:.4f} | {b_agg['p_at_5_mean']:.4f} | {b_agg['p_at_5_mean']-a_agg['p_at_5_mean']:+.4f} |
| NDCG@10 | {a_agg['ndcg_at_10_mean']:.4f} | {b_agg['ndcg_at_10_mean']:.4f} | {b_agg['ndcg_at_10_mean']-a_agg['ndcg_at_10_mean']:+.4f} |

**Headline:** {rank1_added_or_fixed} / {a_agg['n']} queries newly rank-1 in {version_b}; {rank1_removed} regression.

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

- McNemar exact (binomial), two-sided p = **{mc['p_two_sided']:.6f}**

---

## Buckets

| Bucket | Count | Queries |
|---|---|---|
| **Added** | **{len(b['added'])}** | {fmt_list(b['added'])} |
| **Removed** | **{len(b['removed'])}** | {fmt_list(b['removed'])} |
| **Fixed** | **{len(b['fixed'])}** | {fmt_list(b['fixed'])} |
| **Degraded** | **{len(b['degraded'])}** | {fmt_list(b['degraded'])} |
| Unchanged (both rank-1) | {len(b['unchanged_rank1'])} | — |
| Both still suboptimal | {len(b['both_suboptimal'])} | {fmt_list(b['both_suboptimal'])} |

---

## Cross-validation note

If this audit's headline + significance numbers agree directionally with `search-quality-versiondiff-v1.1.0-to-v1.2.0.md`'s (the original 50-query corpus), the v1.2.0 > v1.1.0 claim is robust to corpus choice. If they disagree, we have a corpus-dependent result and need to investigate.
"""
    out_path.write_text(md)


def write_deprecation_md(out_path: Path, arm_a_label: str, arm_b_label: str,
                         paired: dict, a_meta: dict, b_meta: dict,
                         version_a: str, version_b: str):
    a_c = paired["arm_a_counts"]
    b_c = paired["arm_b_counts"]
    t = paired["transitions"]
    n = sum(a_c.values())
    a_modern_win_rate = (a_c["modern_wins"] + a_c["modern_only"]) / n
    b_modern_win_rate = (b_c["modern_wins"] + b_c["modern_only"]) / n
    delta = b_modern_win_rate - a_modern_win_rate
    status = "Strong" if delta > 0 and not t["a_win_b_lose"] else ("Mixed" if delta >= 0 else "Weak")
    headline = f"modern-wins rate {a_modern_win_rate:.2%} → {b_modern_win_rate:.2%}"

    md = f"""# Search-quality version diff: {version_a} → {version_b} (deprecation pairs)

**Date:** 2026-05-21
**Status:** {status}
**Headline:** {headline}
**Corpus:** 30 (modern, legacy) Foundation + Swift-stdlib pairs harvested from `docs/audits/search-quality-deprecation-baseline-v1.2.0.md`
**Arm A:** {arm_a_label} — `{a_meta.get('binary','?')}` × `{a_meta.get('db','?')}` ({a_meta.get('schema','?')}, {a_meta.get('docs','?')} docs)
**Arm B:** {arm_b_label} — `{b_meta.get('binary','?')}` × `{b_meta.get('db','?')}` ({b_meta.get('schema','?')}, {b_meta.get('docs','?')} docs)
**Methodology:** `docs/design/search-quality-eval.md` Phase 1.1 (Class C deprecation-aware, paired-comparison mode)
**Harness:** `scripts/eval/search-quality-phase1-extended.py`

For each (query, modern_uri, legacy_uri) triple: run `cupertino search "<query>" --limit 10`, classify the outcome as `modern_wins` (modern rank < legacy rank), `legacy_wins`, `tied`, `modern_only` (only modern in top-10), `legacy_only`, or `both_missing`. The Class C concern is that the ranker should prefer the modern Swift form on every pair; an agent grounded on `cupertino search "URL"` should land on `apple-docs://foundation/url` (Swift struct), not `apple-docs://foundation/nsurl` (legacy ObjC class).

---

## Aggregate

| Outcome | {arm_a_label} | {arm_b_label} | Delta |
|---|---|---|---|
| modern wins | {a_c['modern_wins']} | {b_c['modern_wins']} | {b_c['modern_wins']-a_c['modern_wins']:+d} |
| modern only (in top-10) | {a_c['modern_only']} | {b_c['modern_only']} | {b_c['modern_only']-a_c['modern_only']:+d} |
| **modern preferred (wins + only)** | **{a_c['modern_wins']+a_c['modern_only']} / {n}** | **{b_c['modern_wins']+b_c['modern_only']} / {n}** | **{b_c['modern_wins']+b_c['modern_only']-a_c['modern_wins']-a_c['modern_only']:+d}** |
| legacy wins | {a_c['legacy_wins']} | {b_c['legacy_wins']} | {b_c['legacy_wins']-a_c['legacy_wins']:+d} |
| legacy only | {a_c['legacy_only']} | {b_c['legacy_only']} | {b_c['legacy_only']-a_c['legacy_only']:+d} |
| tied | {a_c['tied']} | {b_c['tied']} | {b_c['tied']-a_c['tied']:+d} |
| both missing | {a_c['both_missing']} | {b_c['both_missing']} | {b_c['both_missing']-a_c['both_missing']:+d} |

**Headline:** modern-preferred rate {a_modern_win_rate:.2%} → {b_modern_win_rate:.2%} (Δ {delta:+.2%}).

---

## Per-query transitions

| Transition | Count | Queries |
|---|---|---|
| A loses → B wins (improvement) | {len(t['a_lose_b_win'])} | {', '.join(f'`{q}`' for q in t['a_lose_b_win']) if t['a_lose_b_win'] else '—'} |
| A wins → B loses (regression) | {len(t['a_win_b_lose'])} | {', '.join(f'`{q}`' for q in t['a_win_b_lose']) if t['a_win_b_lose'] else '—'} |
| Both win (concordant +) | {len(t['both_win'])} | — |
| Both lose (concordant −) | {len(t['both_lose'])} | {', '.join(f'`{q}`' for q in t['both_lose']) if t['both_lose'] else '—'} |

A zero "regression" column with a positive "improvement" column is the clean-win shape.
"""
    out_path.write_text(md)


def db_stat(p: str) -> dict:
    import sqlite3
    conn = sqlite3.connect(p)
    v = conn.execute("PRAGMA user_version;").fetchone()[0]
    n = conn.execute("SELECT COUNT(*) FROM docs_metadata;").fetchone()[0]
    conn.close()
    return {"schema": f"v{v}", "docs": f"{n:,}"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm-a-binary", required=True)
    ap.add_argument("--arm-a-search-db", required=True)
    ap.add_argument("--arm-a-label", default="A")
    ap.add_argument("--arm-a-version", default="A")
    ap.add_argument("--arm-b-binary", required=True)
    ap.add_argument("--arm-b-search-db", required=True)
    ap.add_argument("--arm-b-label", default="B")
    ap.add_argument("--arm-b-version", default="B")
    ap.add_argument("--corpus", required=True, choices=["canonical-v2", "deprecation"])
    ap.add_argument("--md-out", required=True)
    ap.add_argument("--json-out")
    args = ap.parse_args()

    a_meta = {"binary": args.arm_a_binary, "db": args.arm_a_search_db, **db_stat(args.arm_a_search_db)}
    b_meta = {"binary": args.arm_b_binary, "db": args.arm_b_search_db, **db_stat(args.arm_b_search_db)}

    if args.corpus == "canonical-v2":
        n = len(CANONICAL_LOOKUP_V2)
        print(f"==> Arm A: {args.arm_a_label}", file=sys.stderr)
        a_outs = []
        for i, (q, pat, qc, notes) in enumerate(CANONICAL_LOOKUP_V2, 1):
            o = score_canonical(args.arm_a_binary, args.arm_a_search_db, q, pat, qc, notes)
            a_outs.append(o)
            print(f"  [A] {i:2}/{n}  {q:<28}  rank={o.first_relevant_rank}  rr={o.rr:.4f}", file=sys.stderr)
        print(f"==> Arm B: {args.arm_b_label}", file=sys.stderr)
        b_outs = []
        for i, (q, pat, qc, notes) in enumerate(CANONICAL_LOOKUP_V2, 1):
            o = score_canonical(args.arm_b_binary, args.arm_b_search_db, q, pat, qc, notes)
            b_outs.append(o)
            print(f"  [B] {i:2}/{n}  {q:<28}  rank={o.first_relevant_rank}  rr={o.rr:.4f}", file=sys.stderr)
        a_agg = aggregate_canonical(a_outs)
        b_agg = aggregate_canonical(b_outs)
        paired = paired_canonical_compare(a_outs, b_outs)
        write_canonical_md(
            Path(args.md_out), "canonical-lookup-V2 (independent corpus)",
            args.arm_a_label, args.arm_b_label, a_agg, b_agg, paired, a_meta, b_meta,
            args.arm_a_version, args.arm_b_version,
        )
        if args.json_out:
            Path(args.json_out).write_text(json.dumps({
                "corpus": "canonical-v2",
                "arm_a": {"label": args.arm_a_label, "meta": a_meta, "agg": a_agg, "outcomes": [asdict(o) for o in a_outs]},
                "arm_b": {"label": args.arm_b_label, "meta": b_meta, "agg": b_agg, "outcomes": [asdict(o) for o in b_outs]},
                "paired": paired,
            }, indent=2, default=str))
        print(f"\n==> Summary [canonical-v2]")
        print(f"  Arm A MRR: {a_agg['mrr']:.4f}   P@1: {a_agg['p_at_1']:.4f}")
        print(f"  Arm B MRR: {b_agg['mrr']:.4f}   P@1: {b_agg['p_at_1']:.4f}")
        print(f"  Delta MRR: {b_agg['mrr'] - a_agg['mrr']:+.4f}")
        print(f"  McNemar two-sided p: {paired['mcnemar']['p_two_sided']:.6f}")
        print(f"  Wilcoxon one-sided (B > A) p: {paired['wilcoxon']['p_one_sided_b_gt_a']:.6f}")

    elif args.corpus == "deprecation":
        n = len(DEPRECATION_PAIRS)
        print(f"==> Arm A: {args.arm_a_label}", file=sys.stderr)
        a_outs = []
        for i, (q, modern_pat, legacy_pat) in enumerate(DEPRECATION_PAIRS, 1):
            o = score_deprecation(args.arm_a_binary, args.arm_a_search_db, q, modern_pat, legacy_pat)
            a_outs.append(o)
            print(f"  [A] {i:2}/{n}  {q:<28}  modern={o.modern_rank} legacy={o.legacy_rank}  outcome={o.outcome}", file=sys.stderr)
        print(f"==> Arm B: {args.arm_b_label}", file=sys.stderr)
        b_outs = []
        for i, (q, modern_pat, legacy_pat) in enumerate(DEPRECATION_PAIRS, 1):
            o = score_deprecation(args.arm_b_binary, args.arm_b_search_db, q, modern_pat, legacy_pat)
            b_outs.append(o)
            print(f"  [B] {i:2}/{n}  {q:<28}  modern={o.modern_rank} legacy={o.legacy_rank}  outcome={o.outcome}", file=sys.stderr)
        paired = paired_deprecation_compare(a_outs, b_outs)
        write_deprecation_md(
            Path(args.md_out), args.arm_a_label, args.arm_b_label,
            paired, a_meta, b_meta, args.arm_a_version, args.arm_b_version,
        )
        if args.json_out:
            Path(args.json_out).write_text(json.dumps({
                "corpus": "deprecation",
                "arm_a": {"label": args.arm_a_label, "meta": a_meta, "outcomes": [asdict(o) for o in a_outs]},
                "arm_b": {"label": args.arm_b_label, "meta": b_meta, "outcomes": [asdict(o) for o in b_outs]},
                "paired": paired,
            }, indent=2, default=str))
        a_modern = paired["arm_a_counts"]["modern_wins"] + paired["arm_a_counts"]["modern_only"]
        b_modern = paired["arm_b_counts"]["modern_wins"] + paired["arm_b_counts"]["modern_only"]
        print(f"\n==> Summary [deprecation]")
        print(f"  Arm A modern-preferred: {a_modern}/{n}")
        print(f"  Arm B modern-preferred: {b_modern}/{n}")
        print(f"  Delta: {b_modern - a_modern:+d}")
        print(f"  Improvements (A lose → B win): {len(paired['transitions']['a_lose_b_win'])}")
        print(f"  Regressions (A win → B lose):  {len(paired['transitions']['a_win_b_lose'])}")


if __name__ == "__main__":
    main()

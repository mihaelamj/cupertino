"""Shared eval-harness library for cupertino's query batteries.

Carries the boilerplate every phase needs: result dataclass, aggregate
metrics, McNemar + Wilcoxon paired tests, paired-comparison bucketing,
JSON output writer, db stat probe, generic argparse + main runner.

Per-phase scripts (search-quality-phase1.py, phase2, phase3, ...) own:
- their fixture corpus
- their `score_query` function (calls the right CLI command + parses
  the right output format + scores against the fixture's expected
  shape)
- optionally a phase-specific Markdown writer for the paired-mode
  audit

The standard contract this library implements is documented at
`docs/audits/eval-harness-standard-v1.0.md`.
"""
from __future__ import annotations

import argparse
import json
import math
import sqlite3
import statistics
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Optional


# MARK: Result dataclass


@dataclass
class QueryOutcome:
    """Per-query result row produced by a phase's `score_query` callback.

    Fields are shared across every phase; phase-specific extras go in
    `extra` so the JSON output schema stays stable.

    Field semantics:
    - `query`: human-readable query id (e.g. the search string, or the
      symbol name for inheritance)
    - `pattern`: the fixture's right-answer specifier (e.g. a regex
      for URI matching, or an expected ancestor list serialised)
    - `qclass`: Class A / B / C / D per the design doc
    - `notes`: free-text notes from the fixture
    - `first_relevant_rank`: 1-indexed rank of the first relevant
      result; None if no relevant result in top 10
    - `rr`: reciprocal rank (1 / first_relevant_rank); 0 if no match
    - `p_at_1`: 1 if rank 1 matches, else 0
    - `p_at_5`: fraction of top-5 that match
    - `ndcg_at_10`: standard NDCG@10 with gain=1 per match
    - `top_uris`: first N raw result identifiers for audit

    Phases that need extra per-result payload should subclass
    `QueryOutcome` and pass the subclass through their `score_fn`; the
    `run_main` JSON serializer uses `dataclasses.asdict` which picks
    up subclass fields automatically.
    """
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


# MARK: Aggregate metrics


def aggregate(outcomes: list) -> dict:
    """Single-arm aggregate: N, P@1, P@5, MRR, NDCG@10, not-in-top-10."""
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


# MARK: Paired statistical tests


def wilcoxon_signed_rank_one_sided(deltas: list) -> dict:
    """Paired Wilcoxon signed-rank, one-sided (test that arm B > arm A).
    `deltas` is the per-query (RR_B - RR_A) vector. Zero deltas are
    discarded per the standard convention. Returns W+, two-sided p,
    one-sided p, N_nonzero. Uses a normal approximation since N is
    typically >= 10."""
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
    return {
        "W_plus": w_plus, "W_minus": w_minus,
        "p_two_sided": p_two, "p_one_sided_b_gt_a": p_one,
        "n_nonzero": n, "z": z,
    }


def mcnemar_p_two_sided(b: int, c: int) -> float:
    """Exact McNemar (binomial) two-sided p. `b` = was-rank-1 in A,
    not-in-B; `c` = was-not-rank-1 in A, is-rank-1-in-B. Discordant
    pairs only."""
    n = b + c
    if n == 0:
        return 1.0
    m = min(b, c)
    from math import comb
    tail = sum(comb(n, k) for k in range(0, m + 1)) / (2 ** n)
    return min(2 * tail, 1.0)


def paired_compare(arm_a_outcomes: list, arm_b_outcomes: list) -> dict:
    """Paired-arm comparison. Buckets every query into one of: added,
    removed, fixed, degraded, unchanged_rank1, both_suboptimal. Runs
    McNemar on the rank-1 outcome + Wilcoxon on per-query RR."""
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
                f"{a.query} (rank {a.first_relevant_rank} to rank {b.first_relevant_rank})"
            )
        elif not a1 and not b1 and not (b.first_relevant_rank and a.first_relevant_rank and b.first_relevant_rank < a.first_relevant_rank):
            buckets["both_suboptimal"].append(a.query)
    a_only = a_rank1 - both_rank1
    b_only = b_rank1 - both_rank1
    neither = len(arm_a_outcomes) - both_rank1 - a_only - b_only
    return {
        "buckets": buckets,
        "mcnemar": {
            "both_rank1": both_rank1,
            "a_only_rank1": a_only,
            "b_only_rank1": b_only,
            "neither_rank1": neither,
            "p_two_sided": mcnemar_p_two_sided(a_only, b_only),
        },
        "wilcoxon": wilcoxon_signed_rank_one_sided(deltas),
    }


# MARK: DB metadata probe


def db_stat(db_path: str) -> dict:
    """Read schema version + document count from a search.db for the
    audit-MD header. Read-only sqlite3 connection."""
    conn = sqlite3.connect(db_path)
    try:
        v = conn.execute("PRAGMA user_version;").fetchone()[0]
        n = conn.execute("SELECT COUNT(*) FROM docs_metadata;").fetchone()[0]
    finally:
        conn.close()
    return {"schema": f"v{v}", "docs": f"{n:,}"}


# MARK: Argparse contract


def make_argparser(phase_name: str) -> argparse.ArgumentParser:
    """Build the canonical argparse for a phase harness. Every phase
    uses the same flags so wrapping shell scripts / CI matrices can
    invoke any phase with a uniform shape."""
    ap = argparse.ArgumentParser(description=f"{phase_name} query battery (single-arm or paired-arm).")
    ap.add_argument("--binary", help="single-arm: cupertino binary path")
    ap.add_argument("--search-db", help="single-arm: search.db path")
    ap.add_argument("--label", default="single", help="single-arm: arm label")
    ap.add_argument("--version", default="single", help="single-arm: cupertino version label for the audit doc")
    ap.add_argument("--arm-a-binary")
    ap.add_argument("--arm-a-search-db")
    ap.add_argument("--arm-a-label", default="A")
    ap.add_argument("--arm-a-version", default="A")
    ap.add_argument("--arm-b-binary")
    ap.add_argument("--arm-b-search-db")
    ap.add_argument("--arm-b-label", default="B")
    ap.add_argument("--arm-b-version", default="B")
    ap.add_argument("--out", help="JSON results dump path")
    ap.add_argument("--md-out", help="paired-mode markdown audit output path")
    ap.add_argument("--smoke", action="store_true", help="run only 1 fixture (CI smoke mode)")
    return ap


# MARK: Generic main runner


def run_main(
    args: argparse.Namespace,
    *,
    corpus: list,
    score_fn: Callable,
    md_writer: Optional[Callable] = None,
    phase_name: str = "phase",
):
    """Single-arm or paired-arm execution driven by the standard
    argparse Namespace. `corpus` is an opaque list whose elements are
    passed individually to `score_fn(binary, search_db, fixture) ->
    QueryOutcome`. If `--smoke` is set, only the first fixture runs.
    The optional `md_writer(out_path, ...)` emits a paired-mode audit
    Markdown file when `--md-out` is set in paired mode."""

    if args.smoke and corpus:
        corpus = corpus[:1]

    def run_arm(binary: str, db: str, label: str) -> tuple:
        outcomes = []
        n = len(corpus)
        for i, fixture in enumerate(corpus, start=1):
            outcome = score_fn(binary, db, fixture)
            outcomes.append(outcome)
            print(f"  [{label}] {i:2}/{n}  {outcome.query:<28}  rank={outcome.first_relevant_rank}  rr={outcome.rr:.4f}", file=sys.stderr)
        return outcomes, aggregate(outcomes)

    paired_mode = bool(args.arm_a_binary and args.arm_b_binary)

    if paired_mode:
        print(f"==> Arm A: {args.arm_a_label}", file=sys.stderr)
        arm_a_outcomes, arm_a_agg = run_arm(args.arm_a_binary, args.arm_a_search_db, "A")
        print(f"==> Arm B: {args.arm_b_label}", file=sys.stderr)
        arm_b_outcomes, arm_b_agg = run_arm(args.arm_b_binary, args.arm_b_search_db, "B")
        paired = paired_compare(arm_a_outcomes, arm_b_outcomes)

        arm_a_meta = {"binary": args.arm_a_binary, "db": args.arm_a_search_db, **db_stat(args.arm_a_search_db)}
        arm_b_meta = {"binary": args.arm_b_binary, "db": args.arm_b_search_db, **db_stat(args.arm_b_search_db)}

        if args.out:
            Path(args.out).write_text(json.dumps({
                "arm_a": {"label": args.arm_a_label, "meta": arm_a_meta, "agg": arm_a_agg, "outcomes": [asdict(o) for o in arm_a_outcomes]},
                "arm_b": {"label": args.arm_b_label, "meta": arm_b_meta, "agg": arm_b_agg, "outcomes": [asdict(o) for o in arm_b_outcomes]},
                "paired": paired,
            }, indent=2, default=str))
            print(f"==> JSON dump: {args.out}", file=sys.stderr)

        if args.md_out and md_writer:
            md_writer(
                Path(args.md_out),
                arm_a_label=args.arm_a_label, arm_b_label=args.arm_b_label,
                arm_a_agg=arm_a_agg, arm_b_agg=arm_b_agg, paired=paired,
                arm_a_meta=arm_a_meta, arm_b_meta=arm_b_meta,
                version_a=args.arm_a_version, version_b=args.arm_b_version,
            )
            print(f"==> Markdown audit: {args.md_out}", file=sys.stderr)

        print(f"\n==> Summary")
        print(f"  Arm A MRR: {arm_a_agg['mrr']:.4f}   P@1: {arm_a_agg['p_at_1']:.4f}")
        print(f"  Arm B MRR: {arm_b_agg['mrr']:.4f}   P@1: {arm_b_agg['p_at_1']:.4f}")
        print(f"  Delta MRR: {arm_b_agg['mrr'] - arm_a_agg['mrr']:+.4f}")
        print(f"  McNemar two-sided p: {paired['mcnemar']['p_two_sided']:.6f}")
        print(f"  Wilcoxon one-sided (B > A) p: {paired['wilcoxon']['p_one_sided_b_gt_a']:.6f}")
    else:
        if not args.binary or not args.search_db:
            print(f"error: single-arm mode needs --binary AND --search-db (or use paired-arm with --arm-a-* and --arm-b-* flags)", file=sys.stderr)
            sys.exit(2)
        outcomes, agg = run_arm(args.binary, args.search_db, args.label)
        if args.out:
            Path(args.out).write_text(json.dumps({
                "label": args.label,
                "version": args.version,
                "agg": agg,
                "outcomes": [asdict(o) for o in outcomes],
            }, indent=2, default=str))
        print(f"\n==> Summary [{args.label}]")
        print(f"  N: {agg['n']}")
        print(f"  MRR: {agg['mrr']:.4f}")
        print(f"  P@1: {agg['p_at_1']:.4f} ({agg['p_at_1_count']}/{agg['n']})")
        print(f"  P@5 (mean): {agg['p_at_5_mean']:.4f}")
        print(f"  NDCG@10 (mean): {agg['ndcg_at_10_mean']:.4f}")
        print(f"  not in top-10: {agg['not_in_top_10']}")

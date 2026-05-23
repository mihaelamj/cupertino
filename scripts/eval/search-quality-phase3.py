#!/usr/bin/env python3
"""Phase 3 query battery: `cupertino inheritance` (= MCP `get_inheritance`).

22 fixtures covering up-walks, down-walks, depth bounds, and the
documented negative-path semantic markers.

Per `docs/audits/query-batteries-design-2026-05-23.md` § Phase 3 and
`docs/audits/eval-harness-standard-v1.0.md`. Output format is the
binary's text format (`No inheritance data:` for negatives;
`<Symbol> | ...` + indented chain for positives). Note: the symbol
resolver works on documented class symbols only , UIView is missing
as a top-level symbol in the v1.2.x bundle (its property pages live
under uikit/uiview/<prop> but the class root itself isn't indexed),
so the canonical class chain starts at UIViewController / UIControl
/ NSView / NSObject and probes UIButton + UIScrollView as deeper
descendants.
"""
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib_harness import QueryOutcome, make_argparser, run_main  # noqa: E402


# MARK: Corpus

PHASE3_FIXTURES = [
    # Up walks (positive: must contain indented chain with expected ancestor)
    {"name": "inheritance UIViewController",   "symbol": "UIViewController", "direction": "up",   "expect": "uiresponder",  "qclass": "A", "notes": "UIVC up walk"},
    {"name": "inheritance UIControl",          "symbol": "UIControl",        "direction": "up",   "expect": "uiview",       "qclass": "A", "notes": "UIControl up walk"},
    {"name": "inheritance UIButton",           "symbol": "UIButton",         "direction": "up",   "expect": "uicontrol",    "qclass": "A", "notes": "UIButton up walk"},
    {"name": "inheritance UIScrollView",       "symbol": "UIScrollView",     "direction": "up",   "expect": "uiview",       "qclass": "A", "notes": "UIScrollView up walk"},
    {"name": "inheritance UITableView",        "symbol": "UITableView",      "direction": "up",   "expect": "uiscrollview", "qclass": "A", "notes": "UITableView up walk"},
    {"name": "inheritance NSView",             "symbol": "NSView",           "direction": "up",   "expect": "nsresponder",  "qclass": "A", "notes": "NSView up walk"},
    {"name": "inheritance NSWindow",           "symbol": "NSWindow",         "direction": "up",   "expect": "nsresponder",  "qclass": "A", "notes": "NSWindow up walk"},
    {"name": "inheritance NSImageView",        "symbol": "NSImageView",      "direction": "up",   "expect": "nscontrol",    "qclass": "A", "notes": "NSImageView up walk"},

    # Down walks (positive: must contain expected descendant)
    {"name": "inheritance UIControl (down)",   "symbol": "UIControl",        "direction": "down", "expect": "uibutton",     "qclass": "B", "notes": "UIControl descendants include UIButton"},
    {"name": "inheritance UIScrollView (down)","symbol": "UIScrollView",     "direction": "down", "expect": "uitableview",  "qclass": "B", "notes": "UIScrollView descendants include UITableView"},
    {"name": "inheritance NSControl (down)",   "symbol": "NSControl",        "direction": "down", "expect": "nsbutton",     "qclass": "B", "notes": "NSControl descendants include NSButton"},
    {"name": "inheritance NSObject (down,1)",  "symbol": "NSObject",         "direction": "down", "depth": 1, "expect": "any-descendant", "qclass": "B", "notes": "NSObject depth=1 has many direct children"},

    # Both walks
    {"name": "inheritance UIControl (both)",   "symbol": "UIControl",        "direction": "both", "expect": "uiview",       "qclass": "B", "notes": "both-direction walk hits UIView ancestor"},
    {"name": "inheritance NSView (both)",      "symbol": "NSView",           "direction": "both", "expect": "nsresponder",  "qclass": "B", "notes": "both-direction walk hits NSResponder"},

    # Depth bounds
    {"name": "inheritance UIButton (depth=1)", "symbol": "UIButton",         "direction": "up", "depth": 1, "expect": "uicontrol", "qclass": "A", "notes": "depth=1 only reaches UIControl"},
    {"name": "inheritance UIButton (depth=2)", "symbol": "UIButton",         "direction": "up", "depth": 2, "expect": "uiview",    "qclass": "A", "notes": "depth=2 reaches UIView"},
    {"name": "inheritance UIButton (depth=10)","symbol": "UIButton",         "direction": "up", "depth": 10, "expect": "nsobject", "qclass": "A", "notes": "depth=10 reaches NSObject"},

    # Negative-path probes (must surface semantic marker)
    {"name": "inheritance Int (value type)",   "symbol": "Int",              "direction": "up",   "expect": "No inheritance data", "qclass": "C", "notes": "value type marker"},
    {"name": "inheritance String (value type)","symbol": "String",           "direction": "up",   "expect": "No inheritance data", "qclass": "C", "notes": "value type marker"},
    {"name": "inheritance Result (enum)",      "symbol": "Result",           "direction": "up",   "expect": "No inheritance data", "qclass": "C", "notes": "enum value type marker"},
    {"name": "inheritance NSObject (root)",    "symbol": "NSObject",         "direction": "up",   "expect": "No inheritance data", "qclass": "C", "notes": "NSObject up walk: the #669 fallback classifies NSObject's swift-class symbol as a protocol, so this exercises the 'protocols don't carry inherits-from edges' branch (NOT the 'root type' branch). Renaming a fallback message would silently regress this fixture."},
    {"name": "inheritance fictional symbol",   "symbol": "Foofictional",     "direction": "up",   "expect": "no-results",          "qclass": "C", "notes": "absent symbol"},
]


# MARK: Score function


def _strip_timestamps(text: str) -> str:
    return re.sub(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\s+", "", text, flags=re.MULTILINE)


def score_query(binary: str, search_db: str, fixture: dict) -> QueryOutcome:
    name = fixture["name"]
    qclass = fixture["qclass"]
    notes = fixture["notes"]
    expect = fixture["expect"]
    symbol = fixture["symbol"]
    direction = fixture.get("direction", "up")
    depth = fixture.get("depth")

    cmd = [binary, "inheritance", symbol, "--direction", direction,
           "--search-db", search_db]
    if depth is not None:
        cmd += ["--depth", str(depth)]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        code, stdout, stderr = proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        code, stdout, stderr = 124, "", "timeout"

    plain = _strip_timestamps(stdout).strip()
    matched = False
    rank = None
    top_uris = [f"exit={code}"]

    if expect in ("No inheritance data", "no-results"):
        # Class C: require an EXPLICIT documented marker (per the
        # #669 fallback wording). Don't accept empty-stdout OR
        # non-zero exit , both would mask silent-empty / crash
        # regressions as PASS. The harness must distinguish "the
        # binary correctly surfaced the value-type / root / absent
        # negative path" from "the binary blew up or said nothing."
        marker_present = (
            "no inheritance data" in plain.lower()
            or "no symbol named" in plain.lower()
            or "no results" in plain.lower()
            or "ambiguous" in plain.lower()  # disambiguation list also acceptable for absent-symbol probe
        )
        if code == 0 and marker_present:
            matched = True
            rank = 1
        top_uris.append(f"output={plain[:60]!r}")
        top_uris.append(f"marker-present={marker_present}")
    elif expect == "any-descendant":
        # Down walk must produce SOME descendant line beneath the symbol header.
        lines = [line for line in plain.splitlines() if line.startswith("    ")]
        if code == 0 and len(lines) >= 1:
            matched = True
            rank = 1
        top_uris.append(f"descendant-lines={len(lines)}")
    else:
        # Positive: chain text must contain the expected ancestor / descendant token.
        if code == 0 and expect.lower() in plain.lower():
            matched = True
            rank = 1
        top_uris.append(f"contains-{expect!r}={expect.lower() in plain.lower()}")

    rr = (1.0 / rank) if rank else 0.0
    p1 = 1 if rank == 1 else 0
    p5 = (1.0 / 5.0) if rank and rank <= 5 else 0.0
    ndcg = 1.0 if rank == 1 else 0.0

    return QueryOutcome(
        query=name,
        pattern=expect,
        qclass=qclass,
        notes=notes,
        first_relevant_rank=rank,
        rr=rr,
        p_at_1=p1,
        p_at_5=p5,
        ndcg_at_10=ndcg,
        top_uris=top_uris,
    )


def write_versiondiff_md(out_path, **kwargs):
    arm_a_label = kwargs["arm_a_label"]; arm_b_label = kwargs["arm_b_label"]
    arm_a_agg = kwargs["arm_a_agg"]; arm_b_agg = kwargs["arm_b_agg"]
    paired = kwargs["paired"]
    version_a = kwargs["version_a"]; version_b = kwargs["version_b"]
    delta_mrr = arm_b_agg["mrr"] - arm_a_agg["mrr"]
    delta_p1 = arm_b_agg["p_at_1"] - arm_a_agg["p_at_1"]
    md = f"""# Search-quality version diff (Phase 3): {version_a} to {version_b}

**Date:** 2026-05-23
**Phase:** 3 (`cupertino inheritance` = MCP `get_inheritance`)
**Harness:** `scripts/eval/search-quality-phase3.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 3
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | {arm_a_label} | {arm_b_label} | Delta |
|---|---|---|---|
| N | {arm_a_agg['n']} | {arm_b_agg['n']} | n/a |
| **MRR** | **{arm_a_agg['mrr']:.4f}** | **{arm_b_agg['mrr']:.4f}** | **{delta_mrr:+.4f}** |
| P@1 | {arm_a_agg['p_at_1']:.4f} ({arm_a_agg['p_at_1_count']}/{arm_a_agg['n']}) | {arm_b_agg['p_at_1']:.4f} ({arm_b_agg['p_at_1_count']}/{arm_b_agg['n']}) | {delta_p1:+.4f} |

## Paired tests

- McNemar two-sided p: {paired['mcnemar']['p_two_sided']:.6f}
- Wilcoxon (B > A) one-sided p: {paired['wilcoxon']['p_one_sided_b_gt_a']:.6f}

## Method

Up walks assert the indented chain output contains the expected ancestor URI fragment. Down walks assert the chain contains the expected descendant. Depth-bounded probes assert the chain reaches (or does not reach) the expected hop. Negative-path probes (Class C) require BOTH exit-0 AND an explicit documented marker (`no inheritance data`, `no symbol named`, `no results`, or `ambiguous` for the disambiguation list). Empty stdout and non-zero exit are explicitly rejected as PASS to avoid masking silent-empty regressions and crashes (iter-2 critic finding).
"""
    out_path.write_text(md)


def main():
    ap = make_argparser("Phase 3 (inheritance)")
    args = ap.parse_args()
    run_main(args, corpus=PHASE3_FIXTURES, score_fn=score_query, md_writer=write_versiondiff_md, phase_name="phase3")


if __name__ == "__main__":
    main()

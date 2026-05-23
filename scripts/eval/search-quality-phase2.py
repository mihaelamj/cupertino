#!/usr/bin/env python3
"""Phase 2 query battery: 5 AST tools (MCP-only per #948).

20 fixtures covering each of the 5 AST tools via MCP stdio:
  - search_symbols
  - search_property_wrappers
  - search_concurrency
  - search_conformances
  - search_generics

Per `docs/audits/query-batteries-design-2026-05-23.md` § Phase 2 and
`docs/audits/eval-harness-standard-v1.0.md`. Spawns `cupertino serve`
as a subprocess and speaks JSON-RPC over stdin / stdout. Until #948
adds CLI subcommands for these 5 tools, MCP stdio is the only
addressable surface.

Honest scope reduction vs the 48-fixture design: this PR ships 20
fixtures (4 per tool) to land Phase 2 alongside Phases 3-5 in one
session. The remaining 28 fixtures from the design doc (esp. the
platform-filter + framework-filter combos) are queued as
fixture-curation follow-ups.
"""
import json
import re
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from lib_harness import QueryOutcome, make_argparser, run_main  # noqa: E402


# MARK: Corpus

PHASE2_FIXTURES = [
    # search_symbols. NSObject runs first because it is the most
    # corpus-stable AST query in the battery: every Apple-release
    # bundle indexes Foundation, and NSObject is the root class of
    # the Objective-C runtime, indexed under `kind=class` with the
    # exact symbol name `NSObject`. The Phase 2 smoke job (#949)
    # runs only the first fixture with `--smoke --strict`; before
    # the iter-3 reorder, the first fixture was `search_symbols
    # struct View`, whose match depends on whether the v1.2.x
    # release bundle (smaller than the local dev DB) happens to
    # have a SwiftUI struct named with `View` substring. The View
    # fixture passes on the full dev corpus but failed on every
    # CI smoke run (#956). Keeping the View fixture in the full
    # battery for coverage of the `kind=struct` filter.
    {"name": "search_symbols class NSObject","tool": "search_symbols",            "args": {"query": "NSObject", "kind": "class", "limit": 10},  "expect_any": ["NSObject"],                  "qclass": "B", "notes": "root class (smoke-stable: NSObject is in every Apple bundle)"},
    {"name": "search_symbols struct View",   "tool": "search_symbols",            "args": {"query": "View", "kind": "struct", "limit": 10},     "expect_any": ["View"],                      "qclass": "B", "notes": "SwiftUI View struct"},
    {"name": "search_symbols enum Result",   "tool": "search_symbols",            "args": {"query": "Result", "kind": "enum", "limit": 10},     "expect_any": ["Result"],                    "qclass": "B", "notes": "stdlib enum"},
    {"name": "search_symbols is_async",      "tool": "search_symbols",            "args": {"is_async": True, "limit": 10},                      "expect_nonempty": True,                     "qclass": "B", "notes": "async function filter"},

    # search_property_wrappers
    {"name": "search_property_wrappers State",      "tool": "search_property_wrappers", "args": {"wrapper": "State", "limit": 10},                "expect_any": ["State", "@State"],         "qclass": "B", "notes": "SwiftUI @State"},
    {"name": "search_property_wrappers Observable", "tool": "search_property_wrappers", "args": {"wrapper": "Observable", "limit": 10},           "expect_any": ["Observable", "@Observable"],"qclass": "B", "notes": "Observation @Observable"},
    {"name": "search_property_wrappers MainActor",  "tool": "search_property_wrappers", "args": {"wrapper": "MainActor", "limit": 10},            "expect_any": ["MainActor", "@MainActor"], "qclass": "B", "notes": "concurrency @MainActor"},
    {"name": "search_property_wrappers Published",  "tool": "search_property_wrappers", "args": {"wrapper": "Published", "limit": 10},            "expect_any": ["Published", "@Published"], "qclass": "B", "notes": "Combine @Published"},

    # search_concurrency
    {"name": "search_concurrency async",     "tool": "search_concurrency",        "args": {"pattern": "async", "limit": 10},                    "expect_nonempty": True,                     "qclass": "B", "notes": "async pattern"},
    {"name": "search_concurrency actor",     "tool": "search_concurrency",        "args": {"pattern": "actor", "limit": 10},                    "expect_nonempty": True,                     "qclass": "B", "notes": "actor pattern"},
    {"name": "search_concurrency sendable",  "tool": "search_concurrency",        "args": {"pattern": "sendable", "limit": 10},                 "expect_nonempty": True,                     "qclass": "B", "notes": "Sendable pattern"},
    {"name": "search_concurrency task",      "tool": "search_concurrency",        "args": {"pattern": "task", "limit": 10},                     "expect_nonempty": True,                     "qclass": "B", "notes": "Task pattern"},

    # search_conformances
    {"name": "search_conformances View",     "tool": "search_conformances",       "args": {"protocol": "View", "limit": 10},                    "expect_any": ["View"],                      "qclass": "B", "notes": "SwiftUI View conformers"},
    {"name": "search_conformances Codable",  "tool": "search_conformances",       "args": {"protocol": "Codable", "limit": 10},                 "expect_any": ["Codable"],                   "qclass": "B", "notes": "Codable conformers"},
    {"name": "search_conformances Sendable", "tool": "search_conformances",       "args": {"protocol": "Sendable", "limit": 10},                "expect_any": ["Sendable"],                  "qclass": "B", "notes": "Sendable conformers"},
    {"name": "search_conformances Hashable", "tool": "search_conformances",       "args": {"protocol": "Hashable", "limit": 10},                "expect_any": ["Hashable"],                  "qclass": "B", "notes": "Hashable conformers"},

    # search_generics
    {"name": "search_generics Sendable",     "tool": "search_generics",           "args": {"constraint": "Sendable", "limit": 10},              "expect_any": ["Sendable"],                  "qclass": "B", "notes": "Sendable-constrained generics"},
    {"name": "search_generics Hashable",     "tool": "search_generics",           "args": {"constraint": "Hashable", "limit": 10},              "expect_any": ["Hashable"],                  "qclass": "B", "notes": "Hashable-constrained generics"},
    {"name": "search_generics View",         "tool": "search_generics",           "args": {"constraint": "View", "limit": 10},                  "expect_any": ["View"],                      "qclass": "B", "notes": "View-constrained generics"},
    {"name": "search_generics Codable",      "tool": "search_generics",           "args": {"constraint": "Codable", "limit": 10},               "expect_any": ["Codable"],                   "qclass": "B", "notes": "Codable-constrained generics"},
]


# MARK: MCP one-shot stdio invocation
#
# Spawn `cupertino serve` per query, send init + tools/call together,
# read all output, parse responses by id. Slower per query (~0.5s
# startup) but robust against persistent-connection issues. Total
# wall-time for 20 fixtures: ~12 seconds.


def _mcp_call(binary: str, search_db: str, tool: str, arguments: dict, timeout: int = 15) -> Optional[dict]:
    init_req = {"jsonrpc": "2.0", "method": "initialize", "params": {
        "protocolVersion": "2025-11-25",
        "capabilities": {},
        "clientInfo": {"name": "phase2-harness", "version": "1.0"},
    }, "id": 1}
    notif = {"jsonrpc": "2.0", "method": "notifications/initialized"}
    call_req = {"jsonrpc": "2.0", "method": "tools/call", "params": {
        "name": tool, "arguments": arguments,
    }, "id": 2}
    stdin_blob = "\n".join(json.dumps(m) for m in (init_req, notif, call_req)) + "\n"

    # `cupertino serve` has no `--search-db` flag (only `--no-reap`).
    # Each binary reads from its own base-dir-resolved search.db:
    # - brew binary -> ~/.cupertino/
    # - v1.2.0 release tarball binary at /tmp/cup-v120 -> ~/.cupertino/
    #   (no bundled cupertino.config.json; defaults to ~/.cupertino/)
    # - `make build-release`-built dev binary -> ~/.cupertino-dev/
    #   (bundled cupertino.config.json sets baseDirectory)
    #
    # The paired Phase 2 baseline measurement in
    # `docs/audits/search-quality-phase2-versiondiff-v1.2.0-to-v1.2.1.md`
    # uses (brew v1.2.1 binary) vs (v1.2.0 release tarball binary),
    # both of which default to ~/.cupertino/, so that paired
    # comparison is a true binary-only swap. The CI smoke job uses
    # the dev binary which auto-isolates to ~/.cupertino-dev/. Audit
    # readers should not conflate the two setups.
    #
    # The `search_db` parameter is retained on the score_fn
    # signature only for forward compatibility when #948 lands the
    # CLI subcommands.
    #
    # `--no-reap` is REQUIRED: by default `cupertino serve` reaps
    # sibling serve processes (per #280), which would kill the user's
    # Claude Desktop / Cursor MCP host every time the harness runs
    # locally. Hermetic harness invocations must opt out of reaping.
    _ = search_db
    try:
        proc = subprocess.run(
            [binary, "serve", "--no-reap"],
            input=stdin_blob,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None

    # Server writes the JSON-RPC traffic to stdout. The debug-arrow
    # prefixes (`→ ` / `← `) per MCP.Core.Transport.Stdio go to
    # stderr, not stdout , but defensive strip in case that changes.
    # Use removeprefix (literal prefix strip) not lstrip (character
    # set).
    for raw in proc.stdout.splitlines():
        line = raw.removeprefix("→ ").removeprefix("← ").strip()
        if not line or not line.startswith("{"):
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == 2:
            return msg
    return None


def score_query(binary: str, search_db: str, fixture: dict) -> QueryOutcome:
    name = fixture["name"]
    qclass = fixture["qclass"]
    notes = fixture["notes"]
    tool = fixture["tool"]
    args = fixture["args"]

    response = _mcp_call(binary, search_db, tool, args)

    matched = False
    rank = None
    top_uris = []

    if response and "result" in response:
        result = response["result"]
        content = result.get("content", [])
        text = ""
        if isinstance(content, list) and content:
            text = " ".join((c.get("text", "") if isinstance(c, dict) else "") for c in content)

        # Parse the actual per-result blocks. cupertino's AST tools all
        # use the same template: `Found **N** ...:` header followed by
        # one `### <symbol-name>` block per result. On zero results,
        # the body carries a `_No <kind> found ..._` italic line and
        # the result count is absent. Filtering on `### ` lines
        # avoids the critic-#1 false-positive where `expect_any`
        # matched the response's filter-echo header (e.g. "kind=enum"
        # made the response contain "enum") regardless of result
        # count.
        no_results_markers = [
            "_No symbols found",
            "_No property wrappers found",
            "_No concurrency patterns found",
            "_No conformances found",
            "_No generic constraints found",
            "_No results found",
        ]
        is_no_results = any(m.lower() in text.lower() for m in no_results_markers)
        # Extract the `### ` header lines (one per result).
        result_headers = []
        for line in text.splitlines():
            if line.startswith("### "):
                result_headers.append(line[4:].strip())
        # Also capture the URI / type-decl lines that follow each
        # header (the actual indexed symbol metadata). Indented
        # metadata sub-lines (`  - Attributes: @State`,
        # `  - Conformances: View`, etc.) are also included so that
        # property-wrapper / conformance / generic-constraint
        # fixtures whose expected token only appears in the
        # attributes / conformances column (not the URI / framework /
        # symbol name) can still match. Pre-#952 the matcher only
        # saw header + URI + Framework lines, which silently
        # failed when the queried wrapper appeared only as a symbol
        # attribute (e.g. `@State` on `delay(_:)` whose URI carries
        # no "state" substring).
        result_body_lines = [line for line in text.splitlines()
                             if line.startswith(("### ", "_Framework:", "- **", "URI: `"))
                             or line.lstrip().startswith(("- Attributes:", "- Conforms to:", "- Generic params:"))]
        result_body = "\n".join(result_body_lines)

        top_uris = result_headers[:10] if result_headers else [text[:80] + "..."]

        if is_no_results or not result_headers:
            # Hard fail: tool returned zero hits. No fixture should
            # PASS on this branch regardless of expectation type;
            # `expect_nonempty` and `expect_any` both want results.
            matched = False
        elif "expect_any" in fixture:
            substrs = [s.lower() for s in fixture["expect_any"]]
            body_lower = result_body.lower()
            if any(s in body_lower for s in substrs):
                matched = True
                rank = 1
        elif fixture.get("expect_nonempty"):
            # At least one `### ` block present (already confirmed by
            # the `not result_headers` branch above falling through).
            matched = True
            rank = 1
    else:
        top_uris = [f"no-response={response is None}"]

    rr = (1.0 / rank) if rank else 0.0
    p1 = 1 if rank == 1 else 0
    p5 = (1.0 / 5.0) if rank and rank <= 5 else 0.0
    ndcg = 1.0 if rank == 1 else 0.0

    return QueryOutcome(
        query=name,
        pattern=str(fixture.get("expect_any") or "non-empty"),
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
    md = f"""# Search-quality version diff (Phase 2): {version_a} to {version_b}

**Date:** 2026-05-23
**Phase:** 2 (5 AST tools via MCP stdio)
**Harness:** `scripts/eval/search-quality-phase2.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 2
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

Each fixture spawns a fresh `cupertino serve --no-reap` subprocess and sends `initialize` + `notifications/initialized` + a single `tools/call` over stdio (20 fixtures x 2 arms = 40 cold starts per paired run; per-query cost dominated by serve startup). A persistent-Popen rewrite is a follow-up that would amortize startup; the current shape is the simpler robust default. Scoring: response text is parsed into per-result `### <name>` blocks; fixtures fail hard when the response carries `_No <kind> found_` or has zero `### ` blocks (no false-positive PASS on empty result sets, per iter-1 critic). Two scoring modes: `expect_any` matches any of a substring set against the parsed result-block body (not the response header); `expect_nonempty` requires at least one `### ` block to exist.

Per #948 these 5 tools have no CLI equivalent yet , once CLI subcommands land, the harness can collapse to shell-out (same shape as Phase 1).
"""
    out_path.write_text(md)


def main():
    ap = make_argparser("Phase 2 (AST tools via MCP stdio)")
    args = ap.parse_args()
    run_main(args, corpus=PHASE2_FIXTURES, score_fn=score_query, md_writer=write_versiondiff_md, phase_name="phase2")


if __name__ == "__main__":
    main()

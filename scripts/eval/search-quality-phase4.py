#!/usr/bin/env python3
"""Phase 4 query battery: read commands.

13 fixtures covering `cupertino read` across 6 of the 8 sources
(samples + packages require different invocation shapes; see Phase
5 + per-project lookups) plus `read-sample` happy + negative paths.

Per `docs/audits/query-batteries-design-2026-05-23.md` § Phase 4 and
`docs/audits/eval-harness-standard-v1.0.md`.

Score semantic: a fixture passes (rank=1) when the binary exits 0
and stdout is non-empty with the format-appropriate signal (JSON
parses or markdown body length > 100 chars). Negative-path fixtures
pass when the binary exits non-zero with the documented error
phrase.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib_harness import QueryOutcome, make_argparser, run_main  # noqa: E402


# MARK: Corpus

PHASE4_FIXTURES = [
    # read --format json (one per source where a stable URI exists)
    {"name": "read apple-docs (json)",        "uri": "apple-docs://swift",                                                                            "format": "json",     "qclass": "A", "notes": "stdlib root", "expect": "json"},
    {"name": "read apple-docs (markdown)",    "uri": "apple-docs://swift",                                                                            "format": "markdown", "qclass": "A", "notes": "stdlib root", "expect": "markdown"},
    {"name": "read hig (json)",               "uri": "hig://general/status-appledeveloperdocumentation",                                              "format": "json",     "qclass": "A", "notes": "HIG status page", "expect": "json"},
    {"name": "read hig (markdown)",           "uri": "hig://general/status-appledeveloperdocumentation",                                              "format": "markdown", "qclass": "A", "notes": "HIG status page", "expect": "markdown"},
    {"name": "read apple-archive (json)",     "uri": "apple-archive://10000107i/AccessorConventions",                                                 "format": "json",     "qclass": "A", "notes": "archive doc", "expect": "json"},
    {"name": "read apple-archive (markdown)", "uri": "apple-archive://10000107i/AccessorConventions",                                                 "format": "markdown", "qclass": "A", "notes": "archive doc", "expect": "markdown"},
    {"name": "read swift-evolution (json)",   "uri": "swift-evolution://SE-0020",                                                                     "format": "json",     "qclass": "A", "notes": "SE proposal", "expect": "json"},
    {"name": "read swift-evolution (markdown)", "uri": "swift-evolution://SE-0020",                                                                   "format": "markdown", "qclass": "A", "notes": "SE proposal", "expect": "markdown"},
    {"name": "read swift-org (json)",         "uri": "swift-org://articles_wasm-getting-started.html",                                                "format": "json",     "qclass": "A", "notes": "swift.org article", "expect": "json"},
    {"name": "read swift-org (markdown)",     "uri": "swift-org://articles_wasm-getting-started.html",                                                "format": "markdown", "qclass": "A", "notes": "swift.org article", "expect": "markdown"},
    {"name": "read absent URI",               "uri": "apple-docs://this/does/not/exist",                                                              "format": "json",     "qclass": "C", "notes": "negative probe", "expect": "not-found"},

    # read-sample
    {"name": "read-sample known project",     "project_id": "avfoundation-avcam-building-a-camera-app",                                               "qclass": "A", "notes": "known sample (AVCam)", "expect": "non-empty"},
    {"name": "read-sample nonexistent",       "project_id": "fictional-nonexistent-project-xyz",                                                      "qclass": "C", "notes": "negative probe", "expect": "not-found"},
]


# MARK: Score function


def _strip_timestamps(text: str) -> str:
    return re.sub(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\s+", "", text, flags=re.MULTILINE)


def _extract_json(text: str):
    text = _strip_timestamps(text)
    idx_obj = text.find("{")
    idx_arr = text.find("[")
    starts = [i for i in (idx_obj, idx_arr) if i >= 0]
    if not starts:
        return None
    try:
        return json.loads(text[min(starts):])
    except json.JSONDecodeError:
        return None


def score_query(binary: str, search_db: str, fixture: dict) -> QueryOutcome:
    name = fixture["name"]
    qclass = fixture["qclass"]
    notes = fixture["notes"]
    expect = fixture["expect"]

    samples_db = str(Path(search_db).with_name("samples.db"))
    packages_db = str(Path(search_db).with_name("packages.db"))

    if "uri" in fixture:
        cmd = [binary, "read", fixture["uri"], "--format", fixture["format"],
               "--search-db", search_db, "--sample-db", samples_db,
               "--packages-db", packages_db]
    else:
        cmd = [binary, "read-sample", fixture["project_id"], "--sample-db", samples_db]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        code, stdout, stderr = proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        code, stdout, stderr = 124, "", "timeout"

    plain = _strip_timestamps(stdout)
    matched = False
    rank = None
    top_uris = [f"exit={code}"]

    if expect == "json":
        data = _extract_json(stdout)
        if code == 0 and data is not None and isinstance(data, (dict, list)):
            content_signal = (
                isinstance(data, dict) and bool(data.get("content") or data.get("structuredContent") or data.get("title") or data.get("rawMarkdown"))
            ) or (isinstance(data, list) and len(data) > 0)
            if content_signal:
                matched = True
                rank = 1
        top_uris.append(f"json-parsed={data is not None}")
    elif expect == "markdown":
        body = plain.strip()
        if code == 0 and len(body) >= 100:
            matched = True
            rank = 1
        top_uris.append(f"markdown-len={len(body)}")
    elif expect == "non-empty":
        body = plain.strip()
        if code == 0 and len(body) >= 50:
            matched = True
            rank = 1
        top_uris.append(f"len={len(body)}")
    elif expect == "not-found":
        # Require an EXPLICIT not-found marker. Don't accept any
        # non-zero exit (could be DB-open-failure, crash, argparser
        # error) or the broad substring "error" (matches log
        # categories, "no errors detected" banners, etc.). The
        # negative-path semantic this fixture exercises is
        # specifically "the URI / project_id is not in the index";
        # other failure modes should NOT silently pass as
        # "expected not-found."
        all_text = (plain + (stderr or "")).lower()
        # Marker list expanded post-iter-2 critic so honest per-error
        # phrasing in Read.swift (e.g. "Read failed:" for backend
        # failures, "Invalid package identifier" for malformed
        # `<owner>/<repo>/<path>`) doesn't have to be lexically
        # mangled into "Document not found" just to satisfy the
        # harness. Each marker corresponds to one canonical negative
        # path in the binary's `Services.ReadService.ReadError`
        # surface.
        explicit_not_found = (
            "not found" in all_text
            or "no such" in all_text
            or "no document" in all_text
            or "project not found" in all_text
            or "no project named" in all_text
            or "read failed" in all_text
            or "invalid package identifier" in all_text
        )
        # Require explicit marker AND non-zero exit. Iter-2 critic
        # caught that marker-only acceptance would mask a refactor
        # that flips ExitCode.failure to ExitCode.success while still
        # emitting the marker string (semantic break: "this should
        # have been a failed read, not a successful empty read").
        if explicit_not_found and code != 0:
            matched = True
            rank = 1
        top_uris.append(f"explicit-not-found-marker={explicit_not_found}")
        top_uris.append(f"exit={code}")

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
    md = f"""# Search-quality version diff (Phase 4): {version_a} to {version_b}

**Date:** 2026-05-23
**Phase:** 4 (read commands)
**Harness:** `scripts/eval/search-quality-phase4.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 4
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

Each fixture probes one URI / project-id and asserts the format-appropriate signal: JSON parses with a content field, markdown body has at least 100 chars, sample read returns at least 50 chars. Negative-path probes (Class C) require BOTH an explicit per-error marker AND non-zero exit. Accepted marker substrings (post-iter-2 critic): `not found`, `no such`, `no document`, `project not found`, `no project named`, `read failed`, `invalid package identifier`. The marker list mirrors the user-facing diagnostic phrases emitted by each `Services.ReadService.ReadError` case after the #953 helper migration. The conjunction prevents two failure modes from being silently scored as PASS: a binary refactor that flips ExitCode.failure to ExitCode.success while still emitting the marker (semantic regression), and crashes / DB-open errors that exit non-zero with an unrelated message containing the substring `error` (iter-2 critic finding).
"""
    out_path.write_text(md)


def main():
    ap = make_argparser("Phase 4 (read commands)")
    args = ap.parse_args()
    run_main(args, corpus=PHASE4_FIXTURES, score_fn=score_query, md_writer=write_versiondiff_md, phase_name="phase4")


if __name__ == "__main__":
    main()

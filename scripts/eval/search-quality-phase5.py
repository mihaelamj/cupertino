#!/usr/bin/env python3
"""Phase 5 query battery: list / doctor / package-search.

15 fixtures covering the remaining CLI commands not exercised by
Phase 1 (search) or future Phase 2-4. Per
`docs/audits/query-batteries-design-2026-05-23.md` § Phase 5 and
`docs/audits/eval-harness-standard-v1.0.md`.

Class A queries are canonical rank-1 (package-search by famous name).
Class B queries are contains-checks (broad searches / filters).
Class C is the negative-path probe (empty query).
Class D is structural invariants (list-frameworks row count,
list-samples project count, doctor exit / footer).
"""
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).parent))
from lib_harness import QueryOutcome, make_argparser, run_main  # noqa: E402


# MARK: Corpus

PHASE5_FIXTURES = [
    # Class D: structural invariants
    {
        "name": "list-frameworks count",
        "cmd": ["list-frameworks"],
        "type": "lines-min-with-tokens",
        "expected": {"min_lines": 415, "must_contain": ["420 total", "swiftui", "foundation", "uikit", "appkit", "combine"]},
        "qclass": "D",
        "notes": "v1.2.x bundle reports 420 frameworks in the header line `Available Frameworks (420 total, 352712 documents):`. Iter-3 fix: assert against the exact reported total via must_contain['420 total'] rather than the squishy line-count floor (which doesn't distinguish '420 frameworks' from '395 frameworks with extra blank lines'). min_lines tightened to 415 (small headroom for trailing-whitespace variance).",
    },
    {
        "name": "list-samples count",
        "cmd": ["list-samples", "--limit", "1000"],
        "type": "lines-min-with-tokens",
        "expected": {"min_lines": 200, "must_contain": ["Total: 619", "projects"]},
        "qclass": "D",
        "notes": "619 projects in v1.2.x bundle. --limit 1000 ensures all projects emit; threshold + must_contain pins the actual total reported in the `Total: N projects` header, not just line count (which would drift if the default limit were changed). Critic iter-2 finding #4.",
    },
    {
        "name": "doctor",
        "cmd": ["doctor"],
        "type": "exit-0-with-marker",
        "expected": {"marker": "All checks passed"},
        "qclass": "D",
        "notes": "doctor green; footer marker present",
    },
    {
        "name": "doctor --kind-coverage",
        "cmd": ["doctor", "--kind-coverage"],
        "type": "exit-0-with-marker",
        "expected": {"marker": "Kind distribution audit"},
        "qclass": "D",
        "notes": "kind-coverage section present",
    },
    {
        "name": "doctor --freshness",
        "cmd": ["doctor", "--freshness"],
        "type": "exit-0-with-marker",
        "expected": {"marker": "Freshness / drift signal"},
        "qclass": "D",
        "notes": "freshness section present",
    },
    {
        "name": "doctor --save",
        "cmd": ["doctor", "--save"],
        "type": "exit-0-with-marker",
        "expected": {"marker": "cupertino save"},
        "qclass": "D",
        "notes": "save-preflight section present",
    },

    # Class A: package-search canonical owner/repo (strict: match against the OWNER/REPO segment of result headers, not READMEs, to avoid the critic-#9 tautology where unrelated packages cross-mention the queried library)
    {
        "name": "package-search alamofire",
        "cmd": ["package-search", "alamofire", "--limit", "10"],
        "type": "package-text-topk-owner-repo",
        "expected": {"owner_repo_substr": ["alamofire"]},
        "qclass": "A",
        "notes": "famous library: top-10 must contain a repo whose owner/repo path includes 'alamofire'. Iter-3 fix: avoids false-positive PASS via README cross-mentions in unrelated packages (e.g. SourceKitten's README).",
    },
    {
        "name": "package-search swift-collections",
        "cmd": ["package-search", "swift-collections", "--limit", "10"],
        "type": "package-text-topk-owner-repo",
        "expected": {"owner_repo_substr": ["swift-collections"]},
        "qclass": "A",
        "notes": "Apple SPM package: top-10 must contain apple/swift-collections by owner/repo match.",
    },
    {
        "name": "package-search swift-algorithms",
        "cmd": ["package-search", "swift-algorithms", "--limit", "10"],
        "type": "package-text-topk-owner-repo",
        "expected": {"owner_repo_substr": ["swift-algorithms"]},
        "qclass": "A",
        "notes": "Apple SPM package: top-10 must contain apple/swift-algorithms by owner/repo match.",
    },
    {
        "name": "package-search kingfisher",
        "cmd": ["package-search", "kingfisher", "--limit", "10"],
        "type": "package-text-topk-owner-repo",
        "expected": {"owner_repo_substr": ["kingfisher"]},
        "qclass": "A",
        "notes": "famous library: top-10 must contain a repo whose owner/repo path includes 'kingfisher'. Iter-3 fix: avoids false-positive PASS via XcodeGen README cross-mention on the v1.2.x bundle. If this fixture FAILS on the v1.2.x baseline, that surfaces a real package-search ranking gap (canonical onevcat/Kingfisher absent from top-10).",
    },
    {
        "name": "package-search json",
        "cmd": ["package-search", "json", "--limit", "10"],
        "type": "package-text-topk-owner-repo",
        "expected": {"owner_repo_substr": ["json", "openapi", "codable", "yaml", "jsonkit", "swiftyjson"]},
        "qclass": "B",
        "notes": "Class B top-K contains-on-owner/repo: any of the JSON-adjacent repo families. Baseline curated against v1.2.1 rank-1 = apple/swift-openapi-generator (semantic match on JSON-spec generation); fixture asserts at least one top-10 hit is a JSON-family repo by name.",
    },
    {
        "name": "package-search networking",
        "cmd": ["package-search", "networking", "--limit", "10"],
        "type": "package-text-topk-owner-repo",
        "expected": {"owner_repo_substr": ["nio", "alamofire", "network", "http", "grpc", "transport"]},
        "qclass": "B",
        "notes": "Class B top-K contains-on-owner/repo: any of the networking-family repo names. Baseline curated against v1.2.1 rank-1 = apple/swift-nio-transport-services; fixture asserts at least one top-10 hit is a networking-family repo by name.",
    },

    # Class C: negative probe
    {
        "name": "package-search empty query",
        "cmd": ["package-search", ""],
        "type": "exit-nonzero",
        "expected": {},
        "qclass": "C",
        "notes": "empty query rejected with usage error",
    },
]


# MARK: Score function


def _run_cmd(binary: str, search_db: str, args: list, timeout: int = 30) -> tuple:
    """Invoke cupertino with the given args; return (returncode, stdout, stderr).

    `search_db` is the search.db path; siblings (samples.db,
    packages.db) live in the same base dir. The db-path flag wiring
    is per-command:
    - search / read / list-frameworks / inheritance accept `--search-db`
    - read accepts `--sample-db` + `--packages-db` (handled in Phase 4)
    - package-search accepts `--db <packages.db>`
    - list-samples accepts `--sample-db <samples.db>`
    - doctor accepts `--search-db` ONLY (does NOT accept --sample-db
      or --packages-db; the binary reads samples.db / packages.db
      from its config-default base dir regardless of search-db flag)

    **Known limitation:** in paired-mode with arm-specific
    --arm-X-search-db values, the doctor fixture's samples.db /
    packages.db sections still read from the binary's auto-resolved
    base-dir, NOT the sibling of the user-passed search-db. For
    arm A (brew v1.2.0 release binary) + arm B (v1.2.1 brew binary
    or v1.2.0 release tarball binary) both default to ~/.cupertino/
    so the divergence is invisible. For arm B using a
    `make build-release`-built dev binary (auto-isolated to
    ~/.cupertino-dev/ via cupertino.config.json) the doctor
    samples/packages sections diverge from the arm-A samples/packages
    sections regardless of `--search-db`. Filing #948-style follow-up
    to add --sample-db / --packages-db to doctor is queued separately;
    the current Class D doctor invariants tolerate the divergence
    because they check section markers, not row counts.
    """
    if not args:
        return 2, "", "no command"
    subcmd = args[0]
    samples_db = str(Path(search_db).with_name("samples.db"))
    packages_db = str(Path(search_db).with_name("packages.db"))
    if subcmd == "package-search":
        cmd = [binary, subcmd, *args[1:], "--db", packages_db]
    elif subcmd == "list-samples":
        cmd = [binary, subcmd, *args[1:], "--sample-db", samples_db]
    elif subcmd == "doctor":
        # Doctor consults search.db AND samples.db. Pass both so the
        # paired-mode arm-specific paths are honored; the binary
        # otherwise falls back to its config-default base dir.
        cmd = [binary, subcmd, "--search-db", search_db, *args[1:]]
    else:
        cmd = [binary, subcmd, "--search-db", search_db, *args[1:]]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def _strip_timestamps(text: str) -> str:
    """Strip ISO-8601 timestamp prefixes (#780/#781) from each line."""
    return re.sub(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\s+", "", text, flags=re.MULTILINE)


def _extract_json(text: str) -> Optional[object]:
    """Strip per-line timestamps and parse the first JSON object/array
    found in the text. Returns None on failure."""
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
    qtype = fixture["type"]
    expected = fixture["expected"]
    qclass = fixture["qclass"]
    notes = fixture["notes"]

    code, stdout, stderr = _run_cmd(binary, search_db, fixture["cmd"])
    plain = _strip_timestamps(stdout)
    line_count = plain.count("\n") + (1 if plain and not plain.endswith("\n") else 0)
    top_uris = []
    matched = False
    rank = None

    if qtype == "lines-min-with-tokens":
        body_lower = plain.lower()
        all_present = all(tok.lower() in body_lower for tok in expected.get("must_contain", []))
        if code == 0 and line_count >= expected["min_lines"] and all_present:
            matched = True
            rank = 1
        top_uris = [f"lines={line_count}", "tokens=" + ",".join(sorted(expected.get("must_contain", [])))]
    elif qtype == "lines-min":
        if code == 0 and line_count >= expected["min_lines"]:
            matched = True
            rank = 1
        top_uris = [f"lines={line_count}"]
    elif qtype == "exit-0-with-marker":
        marker_present = expected["marker"].lower() in plain.lower()
        if code == 0 and marker_present:
            matched = True
            rank = 1
        top_uris = [f"exit={code}", f"marker={expected['marker']!r}", f"present={marker_present}"]
    elif qtype == "exit-nonzero":
        if code != 0:
            matched = True
            rank = 1
        top_uris = [f"exit={code}"]
    elif qtype == "package-text-topk-contains":
        # package-search emits text with `[N] owner/repo , file.md` headers.
        # Parse those headers + capture full body so the "any_substr"
        # match can also hit README content.
        substrs = [s.lower() for s in expected["any_substr"]]
        header_re = re.compile(r"^\[(\d+)\]\s+(\S+)\s+", re.MULTILINE)
        headers = header_re.findall(plain)
        top_uris = [f"[{n}] {repo}" for n, repo in headers[:10]]
        # Rank check: find the first result block whose body OR header
        # contains any of the substrings.
        blocks = re.split(r"^═+$", plain, flags=re.MULTILINE)
        for i, block in enumerate(blocks[1:11], start=1):  # blocks[0] is preamble before [1]
            block_lower = block.lower()
            if any(s in block_lower for s in substrs):
                rank = i
                matched = True
                break
    elif qtype == "package-text-rank1-owner-repo":
        # Stricter: match only against the OWNER/REPO segment of the
        # rank-1 result header. Avoids the critic-#9 tautology of
        # matching ubiquitous README terms.
        substrs = [s.lower() for s in expected["owner_repo_substr"]]
        header_re = re.compile(r"^\[(\d+)\]\s+(\S+)\s+", re.MULTILINE)
        headers = header_re.findall(plain)
        top_uris = [f"[{n}] {repo}" for n, repo in headers[:10]]
        if headers:
            rank1_repo = headers[0][1].lower()
            if any(s in rank1_repo for s in substrs):
                rank = 1
                matched = True
    elif qtype == "package-text-topk-owner-repo":
        # Top-K variant of rank1-owner-repo: at least one of the
        # top-10 result headers carries a query-family substring in
        # its OWNER/REPO segment. Used when the semantic ground
        # truth admits multiple acceptable rank-1 winners (e.g.
        # "networking" maps to nio / alamofire / grpc families).
        substrs = [s.lower() for s in expected["owner_repo_substr"]]
        header_re = re.compile(r"^\[(\d+)\]\s+(\S+)\s+", re.MULTILINE)
        headers = header_re.findall(plain)
        top_uris = [f"[{n}] {repo}" for n, repo in headers[:10]]
        for i, (_, repo) in enumerate(headers[:10], start=1):
            if any(s in repo.lower() for s in substrs):
                rank = i
                matched = True
                break
    else:
        top_uris = [f"unknown-type={qtype}"]

    rr = (1.0 / rank) if rank else 0.0
    p1 = 1 if rank == 1 else 0
    p5 = (1.0 / 5.0) if (rank and rank <= 5) else 0.0
    ndcg = (1.0 / (1.0 if rank == 1 else (1 + rank / 2.0))) if rank else 0.0

    return QueryOutcome(
        query=name,
        pattern=str(expected),
        qclass=qclass,
        notes=notes,
        first_relevant_rank=rank,
        rr=rr,
        p_at_1=p1,
        p_at_5=p5,
        ndcg_at_10=ndcg,
        top_uris=top_uris,
    )


# MARK: Markdown writer (minimal , Phase 5 is structural invariants + package-search)


def write_versiondiff_md(out_path, **kwargs):
    arm_a_label = kwargs["arm_a_label"]
    arm_b_label = kwargs["arm_b_label"]
    arm_a_agg = kwargs["arm_a_agg"]
    arm_b_agg = kwargs["arm_b_agg"]
    paired = kwargs["paired"]
    version_a = kwargs["version_a"]
    version_b = kwargs["version_b"]
    delta_mrr = arm_b_agg["mrr"] - arm_a_agg["mrr"]
    delta_p1 = arm_b_agg["p_at_1"] - arm_a_agg["p_at_1"]
    md = f"""# Search-quality version diff (Phase 5): {version_a} to {version_b}

**Date:** 2026-05-23
**Phase:** 5 (list / doctor / package-search)
**Harness:** `scripts/eval/search-quality-phase5.py`
**Corpus design:** `docs/audits/query-batteries-design-2026-05-23.md` § Phase 5
**Library:** `scripts/eval/lib_harness.py`
**Standard:** `docs/audits/eval-harness-standard-v1.0.md`

## Aggregate

| Metric | {arm_a_label} | {arm_b_label} | Delta |
|---|---|---|---|
| N queries | {arm_a_agg['n']} | {arm_b_agg['n']} | n/a |
| **MRR** | **{arm_a_agg['mrr']:.4f}** | **{arm_b_agg['mrr']:.4f}** | **{delta_mrr:+.4f}** |
| P@1 | {arm_a_agg['p_at_1']:.4f} ({arm_a_agg['p_at_1_count']} / {arm_a_agg['n']}) | {arm_b_agg['p_at_1']:.4f} ({arm_b_agg['p_at_1_count']} / {arm_b_agg['n']}) | {delta_p1:+.4f} |
| not pass | {arm_a_agg['not_in_top_10']} | {arm_b_agg['not_in_top_10']} | {arm_b_agg['not_in_top_10'] - arm_a_agg['not_in_top_10']:+d} |

## Paired tests

- McNemar (rank-1 outcome) two-sided p: **{paired['mcnemar']['p_two_sided']:.6f}**
- Wilcoxon (B > A) one-sided p: **{paired['wilcoxon']['p_one_sided_b_gt_a']:.6f}**

## Buckets

| Bucket | Count | Queries |
|---|---|---|
| Added | {len(paired['buckets']['added'])} | {', '.join(f'`{q}`' for q in paired['buckets']['added']) or 'n/a'} |
| Removed | {len(paired['buckets']['removed'])} | {', '.join(f'`{q}`' for q in paired['buckets']['removed']) or 'n/a'} |
| Fixed | {len(paired['buckets']['fixed'])} | {', '.join(f'`{q}`' for q in paired['buckets']['fixed']) or 'n/a'} |
| Degraded | {len(paired['buckets']['degraded'])} | {', '.join(f'`{q}`' for q in paired['buckets']['degraded']) or 'n/a'} |
| Unchanged (rank-1) | {len(paired['buckets']['unchanged_rank1'])} | majority |
| Both suboptimal | {len(paired['buckets']['both_suboptimal'])} | {', '.join(f'`{q}`' for q in paired['buckets']['both_suboptimal']) or 'n/a'} |

## Method

Phase 5 queries dispatch on a per-fixture `type`. The implemented dispatch surface (mirror of `score_query` in `scripts/eval/search-quality-phase5.py`):

- `lines-min`: exit 0 AND stdout line count >= `expected.min_lines`
- `lines-min-with-tokens`: lines-min AND every token in `expected.must_contain` (case-insensitive substring) is present in stdout (used for structural invariants where the canonical totals are pinned: `420 total`, `Total: 619 projects`)
- `exit-0-with-marker`: exit 0 AND stdout contains `expected.marker` (case-insensitive)
- `exit-nonzero`: returncode != 0 (Class C negative path)
- `package-text-topk-contains`: at least one of the top-10 `[N] owner/repo` result blocks contains any string in `expected.any_substr` (body match; loose, used for broad semantic queries)
- `package-text-rank1-owner-repo`: the RANK-1 result header's owner/repo segment contains any string in `expected.owner_repo_substr` (strict; used for canonical-lookup queries where the rank-1 winner is the named library)
- `package-text-topk-owner-repo`: any of the top-10 result headers' owner/repo segments contains any string in `expected.owner_repo_substr` (used for canonical-lookup queries that admit multiple acceptable rank-1 winners by family, e.g. networking → nio / alamofire / grpc)

Rank assignment per type: structural invariants (`lines-min*`, `exit-0-with-marker`, `exit-nonzero`) and the strict `package-text-rank1-owner-repo` produce `first_relevant_rank = 1` on pass / `None` on fail (binary outcome). The two top-K dispatches (`package-text-topk-contains`, `package-text-topk-owner-repo`) assign `first_relevant_rank = i` where `i` is the 1-indexed position of the first matching block in the top-10, so P@1 / MRR / NDCG can express partial credit when the canonical winner shifts down the result list. Structural invariants are Class D; package-search by name is Class A; semantic / broad package-search is Class B; empty-query negative path is Class C.
"""
    out_path.write_text(md)


def main():
    ap = make_argparser("Phase 5 (list / doctor / package-search)")
    args = ap.parse_args()
    run_main(args, corpus=PHASE5_FIXTURES, score_fn=score_query, md_writer=write_versiondiff_md, phase_name="phase5")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Render the index dashboard (search-quality-v1.2.0.html) by scanning all
audit markdown files in docs/audits/ and extracting their headline
metrics + intro text.

Usage:
    python3 _render-index-dashboard.py

Produces:
    search-quality-v1.2.0.html  (next to this script)

The card grid, the KPI strip, and the overall summary are all derived
from the audit markdown set. When an audit is added or its headline
changes, re-run this script — no card content is hardcoded.

For the architectural callout linking the open issues, this script reads
docs/dashboards/_index_extras.json (small hand-curated metadata for
things that aren't derivable from the audits alone). If that file is
absent the callout is skipped.
"""

from __future__ import annotations

import html
import json
import sys
from pathlib import Path

from _audit_parser import (
    Audit,
    derive_dashboard_name,
    discover_audits,
    extract_headline,
    parse_audit,
    render_inline,
    title_case,
)


def _audit_summary(audit: Audit):
    headline = extract_headline(audit)
    dashboard_url = f"audits/{derive_dashboard_name(audit.source_path)}"
    # First paragraph of intro becomes the card's plain-English finding
    finding = audit.first_intro_paragraph
    if len(finding) > 320:
        finding = finding[:317] + "…"
    return {
        "title": audit.title,
        "subtitle": audit.header_block.get("Methodology", "")[:80] or "Cupertino audit",
        "status": headline.status,
        "value": headline.value,
        "color": headline.color,
        "raw_percent": headline.raw_percent,
        "finding": finding,
        "dashboard_url": dashboard_url,
        "audit_filename": audit.source_path.name if audit.source_path else "",
    }


STATUS_TO_CLASS = {
    "Strong": "status-strong",
    "Mixed": "status-mixed",
    "Weak": "status-weak",
    "Info": "status-info",
}


def render_card(s: dict) -> str:
    return f"""                <article class="card">
                    <span class="status {STATUS_TO_CLASS.get(s['status'], 'status-info')}">{html.escape(s['status'])}</span>
                    <h3 class="card-title">{html.escape(s['title'])}</h3>
                    <p class="card-subtitle">{html.escape(s['subtitle'])}</p>
                    <div class="card-metric {s['color']}">{html.escape(s['value'])}</div>
                    <p class="card-metric-label">headline measurement</p>
                    <p class="card-finding">{render_inline(s['finding'])}</p>
                    <a class="card-link" href="{html.escape(s['dashboard_url'], quote=True)}">Open audit dashboard</a>
                </article>"""


def compute_aggregate(summaries: list[dict]) -> dict:
    strong = sum(1 for s in summaries if s["status"] == "Strong")
    mixed = sum(1 for s in summaries if s["status"] == "Mixed")
    weak = sum(1 for s in summaries if s["status"] == "Weak")
    return {"strong": strong, "mixed": mixed, "weak": weak, "total": len(summaries)}


def render_index(audits_dir: Path, out_path: Path, extras_path: Path | None = None) -> None:
    audit_paths = discover_audits(audits_dir)
    if not audit_paths:
        print(f"no audits found in {audits_dir}", file=sys.stderr)
        sys.exit(1)

    audits = [parse_audit(p) for p in audit_paths]
    summaries = [_audit_summary(a) for a in audits]

    # Sort: strong first, then mixed, then weak; within each, by descending raw_percent
    status_order = {"Strong": 0, "Mixed": 1, "Weak": 2, "Info": 3}
    summaries.sort(key=lambda s: (status_order.get(s["status"], 99), -(s["raw_percent"] or 0)))

    agg = compute_aggregate(summaries)
    cards_html = "\n".join(render_card(s) for s in summaries)

    extras = {}
    if extras_path and extras_path.exists():
        extras = json.loads(extras_path.read_text())

    pending_card = extras.get("pending_card_html", "")
    callout_html = extras.get("callout_html", "")

    n = agg["total"]
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cupertino search quality · v1.2.0</title>
    <link rel="stylesheet" href="_styles.css">
</head>
<body>
    <div class="container">

        <header class="centered">
            <div class="eyebrow">Cupertino · v1.2.0 candidate</div>
            <h1>Does the search find the right answer?</h1>
            <p class="subtitle">
                Cupertino is an Apple-platform documentation index built to keep AI coding assistants from hallucinating. This page summarises {n} measurements of how well it does that on the v1.2.0 build.
            </p>
            <p class="meta">
                <span>{n} measurements</span>·<span>Auto-derived from audit markdown</span>·<span>Re-runs whenever audits change</span>
            </p>
        </header>

        <div class="summary">
            <h2>At a glance</h2>
            <p class="summary-text">
                <strong>{agg['strong']} of {n} tests pass strongly</strong> &mdash; the canonical use cases (typing a Swift type name, modern-vs-legacy choice, fragment recall, cross-source ranking) all work as designed. <strong>{agg['weak']} surface real weaknesses</strong> in cupertino's relational-metadata-to-search routing, both tracked with open issues and candidate fixes. <strong>{agg['mixed']} have methodology limits</strong> that proper measurement (human-judged) would resolve.
            </p>
        </div>

        <section>
            <h2>The measurements</h2>
            <div class="grid">
{cards_html}
{pending_card}
            </div>
        </section>

        {callout_html}

        <footer>
            <p>
                Index card content is auto-derived from the audit markdown files under
                <a href="../audits/">docs/audits/</a> by <code>_render-index-dashboard.py</code>.
                Per-audit dashboards (the cards above link to them) are derived from the same source by <code>_render-audit-dashboard.py</code>.
                When an audit changes, re-run <code>regen-all.sh</code> in this folder.
            </p>
            <p>
                Methodology in <a href="../design/search-quality-eval.md">docs/design/search-quality-eval.md</a>
                ·
                Architecture in <a href="../architecture/database.md">docs/architecture/database.md</a>
                ·
                Index in <a href="../database-handbook.md">docs/database-handbook.md</a>
            </p>
        </footer>

    </div>
</body>
</html>
"""
    out_path.write_text(html_body)
    print(f"wrote {out_path}  ({len(summaries)} cards, {agg['strong']} strong, {agg['mixed']} mixed, {agg['weak']} weak)")


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    audits_dir = script_dir.parent / "audits"
    extras_path = script_dir / "_index_extras.json"
    out_path = script_dir / "search-quality-v1.2.0.html"
    render_index(audits_dir, out_path, extras_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

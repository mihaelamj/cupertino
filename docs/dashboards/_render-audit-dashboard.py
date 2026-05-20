#!/usr/bin/env python3
"""
Render one per-audit dashboard HTML from an audit markdown file.

Usage:
    python3 _render-audit-dashboard.py <audit.md>

Produces:
    audits/<derived-name>.html

The audit markdown is the single source of truth. Nothing is hardcoded
per-audit; when the audit changes, re-run this script and the dashboard
refreshes. See `_audit_parser.py` for parsing and headline extraction.
"""

from __future__ import annotations

import html
import sys
from pathlib import Path

from _audit_parser import (
    Audit,
    derive_dashboard_name,
    extract_headline,
    md_to_html,
    parse_audit,
    render_inline,
    title_case,
)


STATUS_TO_CLASS = {
    "Strong": "status-strong",
    "Mixed": "status-mixed",
    "Weak": "status-weak",
    "Info": "status-info",
}


def render(audit: Audit) -> str:
    headline = extract_headline(audit)
    status_class = STATUS_TO_CLASS.get(headline.status, "status-info")
    subtitle = audit.header_block.get("Methodology", "Cupertino search-quality audit")
    if len(subtitle) > 100:
        subtitle = subtitle[:97] + "…"
    rel_audit = f"../../audits/{audit.source_path.name}" if audit.source_path else ""

    sections_html: list[str] = []
    for sec_name in audit.sections_order:
        body_md = audit.sections[sec_name]
        sections_html.append(
            f'<section><h2>{html.escape(title_case(sec_name))}</h2>{md_to_html(body_md)}</section>'
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{html.escape(audit.title)} · cupertino search quality</title>
    <link rel="stylesheet" href="../_styles.css">
</head>
<body>
    <div class="container">

        <a class="back-link" href="../search-quality-v1.2.0.html">Back to dashboard</a>

        <header>
            <div class="eyebrow">{html.escape(subtitle)}</div>
            <h1>{html.escape(audit.title)}</h1>
            <p class="subtitle">{render_inline(audit.first_intro_paragraph)}</p>
            <p class="meta">
                <span>Measured {html.escape(audit.date)}</span>·<span class="status {status_class}" style="margin: 0 8px;">{html.escape(headline.status)}</span>
            </p>
        </header>

        <div class="kpi-strip">
            <div class="kpi">
                <div class="kpi-label">Headline result</div>
                <div class="kpi-value {headline.color}">{html.escape(headline.value)}</div>
                <div class="kpi-desc">Auto-extracted from the audit's first measured section. Full data below.</div>
            </div>
        </div>

        {"".join(sections_html)}

        <footer>
            <p>
                Generated from <a href="{rel_audit}">{rel_audit}</a> by <code>_render-audit-dashboard.py</code>.
                Re-run after editing the audit; nothing here is hardcoded per-audit.
            </p>
            <p>
                Part of <a href="../search-quality-v1.2.0.html">cupertino search-quality dashboards</a>.
                Methodology in <a href="../../design/search-quality-eval.md">docs/design/search-quality-eval.md</a>.
            </p>
        </footer>

    </div>
</body>
</html>
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <audit.md>", file=sys.stderr)
        return 2
    audit_path = Path(sys.argv[1]).resolve()
    if not audit_path.exists():
        print(f"error: {audit_path} not found", file=sys.stderr)
        return 1
    audit = parse_audit(audit_path)
    out_path = Path(__file__).resolve().parent / "audits" / derive_dashboard_name(audit_path)
    out_path.parent.mkdir(exist_ok=True)
    out_path.write_text(render(audit))
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

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
import json
import sys
from pathlib import Path

from _audit_parser import (
    Audit,
    SOURCE_META,
    derive_dashboard_name,
    extract_headline,
    find_cited_sources,
    first_metric_link,
    linkify_metrics,
    md_to_html,
    parse_audit,
    render_inline,
    title_case,
)
from _charts import (
    BarMetric,
    COLORS,
    DonutSlice,
    SlopePoint,
    bar_compare_metrics,
    bucket_donut,
    rank_slope,
)


# Mermaid bootstrap — kept in sync with the same constant in
# `_render-doc.py`. Injected only when a rendered page contains a
# `<pre class="mermaid">` block. Without this script tag, Mermaid
# source ends up styled as a code block and never converts to SVG.
# `_render-doc.py`'s hyphenated filename can't be imported as a
# Python module without importlib gymnastics, so the bootstrap is
# duplicated inline here. If either copy changes, change both.
MERMAID_BOOTSTRAP = '''    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <script>
    (function() {
        if (typeof mermaid === 'undefined') return;
        var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        var apple = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Arial, sans-serif';
        var dark = {
            darkMode: true, background: '#1c1c1e',
            primaryColor: '#2c2c2e', primaryTextColor: '#ffffff', primaryBorderColor: '#48484a',
            secondaryColor: '#1c1c1e', tertiaryColor: '#2c2c2e',
            lineColor: '#aeaeb2', edgeLabelBackground: '#2c2c2e',
            clusterBkg: '#1c1c1e', clusterBorder: '#48484a',
            mainBkg: '#2c2c2e', textColor: '#ffffff', nodeTextColor: '#ffffff',
            fontFamily: apple,
        };
        var light = {
            background: '#ffffff', primaryColor: '#ffffff', primaryTextColor: '#1d1d1f',
            primaryBorderColor: '#d2d2d7', secondaryColor: '#f5f5f7', tertiaryColor: '#ffffff',
            lineColor: '#6e6e73', edgeLabelBackground: '#f5f5f7',
            clusterBkg: '#f5f5f7', clusterBorder: '#d2d2d7',
            mainBkg: '#ffffff', textColor: '#1d1d1f', nodeTextColor: '#1d1d1f',
            fontFamily: apple,
        };
        mermaid.initialize({
            startOnLoad: true, theme: 'base',
            themeVariables: prefersDark ? dark : light,
            fontFamily: apple, securityLevel: 'loose',
            flowchart: { htmlLabels: true, curve: 'basis', useMaxWidth: true },
        });
    })();
    </script>'''


def _render_versiondiff_charts(audit: Audit) -> str:
    """If the audit is a versiondiff with a sibling JSON of per-query
    paired results, render three charts: aggregate bars, four-bucket
    donut, and the per-query rank-slope chart.
    """
    if not audit.source_path:
        return ""
    if "versiondiff" not in audit.source_path.name:
        return ""
    json_path = audit.source_path.with_suffix(".json")
    if not json_path.exists():
        return ""
    data = json.loads(json_path.read_text())

    per_query = data.get("per_query", [])
    if not per_query:
        return ""

    # ---- aggregate bars ----
    n = len(per_query)
    def mean(key_path: list[str]) -> float:
        s = 0.0
        for q in per_query:
            v = q
            for k in key_path:
                v = v[k]
            s += v
        return s / max(1, n)

    mrr_brew = mean(["brew", "mrr"])
    mrr_new = mean(["new", "mrr"])
    p1_brew = mean(["brew", "p1"])
    p1_new = mean(["new", "p1"])
    ndcg_brew = mean(["brew", "ndcg10"])
    ndcg_new = mean(["new", "ndcg10"])

    metrics_chart = bar_compare_metrics(
        [
            BarMetric(name="MRR",       before=mrr_brew,  after=mrr_new,  fmt="{:.4f}"),
            BarMetric(name="P@1",       before=p1_brew,   after=p1_new,   fmt="{:.4f}"),
            BarMetric(name="NDCG@10",   before=ndcg_brew, after=ndcg_new, fmt="{:.4f}"),
        ],
        label_before="v1.0.2 (current release)",
        label_after="v1.2.0 (next release)",
        caption="Average across 50 canonical-lookup queries. Higher is better on every metric. Green delta = improvement; red = regression. The values match the audit's Aggregate table — this is the same data drawn so it can be read at a glance.",
        chart_id="versiondiff-metrics",
    )

    # ---- four-bucket donut ----
    added = removed = fixed = degraded = unchanged_top1 = both_suboptimal = 0
    for q in per_query:
        br = q["brew"]["first_rank"]
        nr = q["new"]["first_rank"]
        if br == 1 and nr == 1:
            unchanged_top1 += 1
        elif br == 1 and nr != 1:
            removed += 1
        elif br != 1 and nr == 1:
            if br is None:
                added += 1
            else:
                fixed += 1
        else:
            if br is None or nr is None or (nr is not None and br is not None and nr > br):
                degraded += 1
            elif nr is not None and br is not None and nr < br:
                fixed += 1
            else:
                both_suboptimal += 1

    donut_chart = bucket_donut(
        [
            DonutSlice("Added",      added,     COLORS["good"],    "Not found before, now rank-1"),
            DonutSlice("Fixed",      fixed,     COLORS["primary"], "Was wrong, now rank-1"),
            DonutSlice("Unchanged",  unchanged_top1, COLORS["neutral"], "Rank-1 in both versions"),
            DonutSlice("Both suboptimal", both_suboptimal, COLORS["warn"], "Neither version returns rank-1"),
            DonutSlice("Degraded",   degraded,  COLORS["bad"],     "Worse than before"),
            DonutSlice("Removed",    removed,   COLORS["bad"],     "Was rank-1, no longer"),
        ],
        total_label="queries",
        caption=f"The {n} canonical queries split into six outcomes. Added + Fixed = improvements; Removed + Degraded = regressions; Unchanged = the rank-1 wins both versions share.",
        chart_id="versiondiff-buckets",
    )

    # ---- per-query rank slope ----
    points = [
        SlopePoint(
            name=q["query"],
            before=q["brew"]["first_rank"],
            after=q["new"]["first_rank"],
        )
        for q in per_query
    ]
    # Sort: most-improved first, then changed, then unchanged
    def sort_key(p: SlopePoint) -> tuple[int, float]:
        b = p.before if p.before is not None else 99
        a = p.after if p.after is not None else 99
        return (a - b, a)
    points.sort(key=sort_key)
    slope_chart = rank_slope(
        points,
        label_before="v1.0.2 rank",
        label_after="v1.2.0 rank",
        caption=f"Each line is one of the {n} queries. Lines sloping up (green) move closer to rank 1; flat lines are unchanged; lines sloping down (red) get worse. Hover any line to see the exact query and ranks.",
        chart_id="versiondiff-slope",
    )

    return (
        '<section class="diff-charts-section">'
        '<h2>What changed, at a glance</h2>'
        '<p class="diff-charts-intro">Same data the tables below show, drawn so you can read it in a few seconds.</p>'
        + metrics_chart
        + donut_chart
        + slope_chart
        + '</section>'
    )


STATUS_TO_CLASS = {
    "Strong": "status-strong",
    "Mixed": "status-mixed",
    "Weak": "status-weak",
    "Info": "status-info",
}


def _section_slug(name: str) -> str:
    import re
    # Strip parenthetical content (e.g. "Four-bucket diff (per #830 https://...)" )
    # before slugifying, otherwise an embedded URL pollutes the slug.
    cleaned = re.sub(r"\([^)]*\)", "", name)
    cleaned = re.sub(r"\[[^\]]*\]", "", cleaned)
    s = re.sub(r"[^a-z0-9]+", "-", cleaned.lower()).strip("-")
    # Cap to a reasonable length
    if len(s) > 60:
        s = s[:60].rstrip("-")
    return s or "section"


def _section_summary(body_md: str, max_chars: int = 220) -> str:
    """First sentence (or first ~220 chars) of a section's body, plain
    text, for the section-card teaser on the main audit page."""
    import re
    # Skip leading metadata lines / lists / tables and find the first
    # prose paragraph
    paragraphs = []
    cur: list[str] = []
    for line in body_md.splitlines():
        if line.strip() and not line.lstrip().startswith(("|", "-", "*", "#", "```")):
            cur.append(line.strip())
        else:
            if cur:
                paragraphs.append(" ".join(cur))
                cur = []
    if cur:
        paragraphs.append(" ".join(cur))
    if not paragraphs:
        return ""
    text = paragraphs[0]
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    if len(text) > max_chars:
        cut = text[:max_chars]
        sentence_end = cut.rfind(". ")
        if sentence_end > 80:
            text = cut[: sentence_end + 1]
        else:
            text = cut.rstrip() + "…"
    return text


def render_section_subpage(
    audit: Audit,
    sec_name: str,
    body_md: str,
    audit_dashboard_name: str,
    audit_title: str,
    prev_sec: str | None,
    next_sec: str | None,
) -> str:
    """One HTML page for a single audit section."""
    body_html = linkify_metrics(md_to_html(body_md), sources_url="../../sources.html")
    pretty_name = title_case(sec_name)
    audit_url = f"../{audit_dashboard_name}"
    prev_html = (
        f'<a class="section-nav-link prev" href="{_section_slug(prev_sec)}.html">← {html.escape(title_case(prev_sec))}</a>'
        if prev_sec else '<span></span>'
    )
    next_html = (
        f'<a class="section-nav-link next" href="{_section_slug(next_sec)}.html">{html.escape(title_case(next_sec))} →</a>'
        if next_sec else '<span></span>'
    )
    mermaid_script = MERMAID_BOOTSTRAP if '<pre class="mermaid">' in body_html else ""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{html.escape(pretty_name)} · {html.escape(audit_title)}</title>
    <link rel="stylesheet" href="../../_styles.css">
</head>
<body class="doc-page">
    <div class="container doc-container">
        <a class="back-link" href="{audit_url}">Back to {html.escape(audit_title)}</a>
        <header class="doc-header">
            <div class="eyebrow">{html.escape(audit_title)}</div>
            <h1>{html.escape(pretty_name)}</h1>
        </header>
        <main class="doc-content section-detail">
            <section class="doc-section">{body_html}</section>
        </main>
        <nav class="section-nav">
            {prev_html}
            {next_html}
        </nav>
        <footer>
            <p><a href="{audit_url}">↑ Back to {html.escape(audit_title)}</a></p>
        </footer>
    </div>
{mermaid_script}
</body>
</html>
"""


def _section_icon_for(sec_name: str) -> str:
    """Pick a small icon based on section name keyword."""
    n = sec_name.lower()
    if "headline" in n or "tldr" in n or "tl;dr" in n:
        return "tint-blue"
    if "aggregate" in n or "result" in n or "summary" in n:
        return "tint-green"
    if "bucket" in n or "diff" in n or "four" in n:
        return "tint-indigo"
    if "mcnemar" in n or "wilcoxon" in n or "test" in n:
        return "tint-orange"
    if "gain" in n or "where" in n:
        return "tint-green"
    if "method" in n or "recap" in n:
        return "tint-blue"
    if "how" in n or "use" in n:
        return "tint-indigo"
    if "not measure" in n or "limit" in n or "caveat" in n:
        return "tint-orange"
    if "source" in n:
        return "tint-indigo"
    return "tint-blue"


def render(audit: Audit) -> str:
    headline = extract_headline(audit)
    status_class = STATUS_TO_CLASS.get(headline.status, "status-info")
    diff_charts_html = _render_versiondiff_charts(audit)
    subtitle = audit.header_block.get("Methodology", "Cupertino search-quality audit")
    if len(subtitle) > 100:
        subtitle = subtitle[:97] + "…"
    rel_audit = f"../../audits/{audit.source_path.name}" if audit.source_path else ""

    # Build section cards (each links to its own subpage) instead of
    # inlining the full prose. We still gather full_body_html for the
    # citation collector + KPI method-link extraction.
    full_body_html_for_citations: list[str] = []
    aggregate_html = ""
    section_cards_html: list[str] = []
    audit_dashboard_name = derive_dashboard_name(audit.source_path) if audit.source_path else "audit.html"
    subpage_dir_name = audit_dashboard_name.replace(".html", "")

    for sec_name in audit.sections_order:
        body_md = audit.sections[sec_name]
        body_html = linkify_metrics(md_to_html(body_md), sources_url="../sources.html")
        if sec_name in ("aggregate", "results", "result", "summary") and not aggregate_html:
            aggregate_html = body_html
        full_body_html_for_citations.append(body_html)

        slug = _section_slug(sec_name)
        summary = _section_summary(body_md)
        icon_tint = _section_icon_for(sec_name)
        section_cards_html.append(
            f'<a class="section-card" href="{subpage_dir_name}/{slug}.html">'
            f'<div class="section-card-icon {icon_tint}">'
            f'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>'
            f'<polyline points="14 2 14 8 20 8"/>'
            f'</svg></div>'
            f'<div class="section-card-body">'
            f'<h3 class="section-card-title">{html.escape(title_case(sec_name))}</h3>'
            f'<p class="section-card-summary">{html.escape(summary)}</p>'
            f'<span class="section-card-cta">Read details →</span>'
            f'</div>'
            f'</a>'
        )

    sections_html_blob = (
        '<section class="section-cards-section">'
        '<h2>Read in detail</h2>'
        '<p class="section-cards-intro">Each card opens its own page. The headline and charts above are all you need at a glance; the cards are for the why and how.</p>'
        f'<div class="section-cards">{"".join(section_cards_html)}</div>'
        '</section>'
    )

    # Derive the KPI-level method link from the Aggregate section (preferred)
    # or the full body fallback.
    method_link = first_metric_link(aggregate_html) or first_metric_link("\n".join(full_body_html_for_citations))
    if method_link:
        method_label, method_anchor = method_link
        meta = SOURCE_META.get(method_anchor, (method_label, ""))
        full_label, cite = meta
        kpi_method_html = (
            '<div class="source-chip">'
            '<span class="source-chip-label">Method &amp; source</span>'
            f'<span class="source-chip-metric"><a href="../sources.html#{method_anchor}">{html.escape(full_label)}</a></span>'
            f'<span class="source-chip-cite"><a href="../sources.html#{method_anchor}">{html.escape(cite)}</a></span>'
            '</div>'
        )
    else:
        kpi_method_html = (
            '<div class="source-chip missing">'
            '<span class="source-chip-label">Method &amp; source</span>'
            '<span class="source-chip-metric"><a href="../sources.html">Browse all citations</a></span>'
            '<span class="source-chip-cite">No metric token detected — see <a href="../sources.html">sources.html</a></span>'
            '</div>'
        )

    # Build the "Sources cited in this measurement" card grid
    cited = find_cited_sources("\n".join(full_body_html_for_citations))
    sources_cards = []
    for anchor, label in cited:
        meta = SOURCE_META.get(anchor, (label, ""))
        title, cite = meta
        sources_cards.append(
            f'<article class="card no-hover">'
            f'<div class="card-icon tint-indigo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div>'
            f'<h3 class="card-title">{html.escape(title)}</h3>'
            f'<p class="card-finding">{html.escape(cite)}</p>'
            f'<a class="card-link" href="../sources.html#{anchor}">Open citation</a>'
            f'</article>'
        )
    sources_section = ""
    if sources_cards:
        sources_section = (
            '<section>'
            '<h2>Sources cited in this measurement</h2>'
            '<p style="color: var(--text-secondary); margin-bottom: 20px;">Every metric and method this audit relies on, with a link to the foundational source. Auto-collected from the audit text.</p>'
            f'<div class="grid cols-2">{"".join(sources_cards)}</div>'
            '</section>'
        )

    parent_has_mermaid = '<pre class="mermaid">' in sections_html_blob
    parent_mermaid_script = MERMAID_BOOTSTRAP if parent_has_mermaid else ""
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
                {kpi_method_html}
            </div>
        </div>

        {diff_charts_html}

        {sections_html_blob}

        {sources_section}

        <footer>
            <p>
                Generated from <a href="{rel_audit}">{rel_audit}</a> by <code>_render-audit-dashboard.py</code>.
                Re-run after editing the audit; nothing here is hardcoded per-audit.
            </p>
            <p>
                Part of <a href="../search-quality-v1.2.0.html">cupertino search-quality dashboards</a>.
                Methodology in <a href="../docs/design-search-quality-eval.html">design/search-quality-eval</a>.
            </p>
        </footer>

    </div>

{parent_mermaid_script}
    <div class="chart-tooltip" id="chart-tooltip" role="tooltip" aria-hidden="true"></div>
    <script>
    (function() {{
        var tip = document.getElementById('chart-tooltip');
        if (!tip) return;
        function show(content, x, y) {{
            tip.innerHTML = content;
            tip.style.left = x + 'px';
            tip.style.top = y + 'px';
            tip.classList.add('visible');
        }}
        function hide() {{ tip.classList.remove('visible'); }}
        document.querySelectorAll('.chart-hoverable').forEach(function(el) {{
            el.addEventListener('mouseenter', function(ev) {{
                var content = el.getAttribute('data-tooltip') || '';
                if (!content) return;
                var rect = (ev.currentTarget.getBoundingClientRect && ev.currentTarget.getBoundingClientRect()) || {{ left: ev.clientX, top: ev.clientY, width: 0 }};
                var x = rect.left + rect.width / 2;
                var y = rect.top;
                show(content, x, y);
            }});
            el.addEventListener('mousemove', function(ev) {{
                if (!tip.classList.contains('visible')) return;
                tip.style.left = ev.clientX + 'px';
                tip.style.top = (ev.clientY - 16) + 'px';
            }});
            el.addEventListener('mouseleave', hide);
        }});
    }})();
    </script>
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
    dashboards_dir = Path(__file__).resolve().parent
    audits_dir = dashboards_dir / "audits"
    audits_dir.mkdir(exist_ok=True)

    dashboard_name = derive_dashboard_name(audit_path)
    out_path = audits_dir / dashboard_name
    out_path.write_text(render(audit))
    print(f"wrote {out_path}")

    # Per-section subpages — one HTML page per `## ` section so the main
    # audit page can stay short and link out. Wipe the subpage dir on
    # every run so stale files from earlier slug iterations don't
    # accumulate.
    import shutil
    subpage_dir = audits_dir / dashboard_name.replace(".html", "")
    if subpage_dir.exists():
        shutil.rmtree(subpage_dir)
    subpage_dir.mkdir()
    section_order = audit.sections_order
    for i, sec_name in enumerate(section_order):
        prev_sec = section_order[i - 1] if i > 0 else None
        next_sec = section_order[i + 1] if i + 1 < len(section_order) else None
        sub_html = render_section_subpage(
            audit=audit,
            sec_name=sec_name,
            body_md=audit.sections[sec_name],
            audit_dashboard_name=dashboard_name,
            audit_title=audit.title,
            prev_sec=prev_sec,
            next_sec=next_sec,
        )
        sub_path = subpage_dir / f"{_section_slug(sec_name)}.html"
        sub_path.write_text(sub_html)
    if section_order:
        print(f"  + {len(section_order)} section pages under {subpage_dir.name}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())

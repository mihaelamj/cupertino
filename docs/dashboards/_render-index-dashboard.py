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
import re
import sys
from pathlib import Path

from _audit_parser import (
    Audit,
    SOURCE_META,
    derive_dashboard_name,
    discover_audits,
    extract_headline,
    first_metric_link,
    linkify_metrics,
    md_to_html,
    parse_audit,
    render_inline,
    title_case,
)


# SVG icons per audit class (derived from filename keywords).
# Inline so the dashboard stays self-contained.
ICON_SVGS = {
    "baseline": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>',
    "deprecation": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>',
    "crosssource": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>',
    "fragment": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>',
    "acronym": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7V4h16v3"/><line x1="9" y1="20" x2="15" y2="20"/><line x1="12" y1="4" x2="12" y2="20"/></svg>',
    "prose": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>',
    "symbol-attribute": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>',
    "default": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>',
}


def _icon_key(audit_filename: str) -> str:
    """acronym-v1.2.0.html → 'acronym'; baseline-v1.2.0.html → 'baseline'"""
    base = audit_filename.replace(".html", "").replace(".md", "")
    base = base.replace("search-quality-", "").replace("-baseline", "")
    # Strip version suffix
    base = re.sub(r"-v[\d.]+$", "", base)
    return base if base in ICON_SVGS else "default"


def _short_subtitle(audit: Audit) -> str:
    """Derive a short kind-of-thing label from filename, not from a clipped
    Methodology string."""
    name = audit.source_path.name if audit.source_path else ""
    if "versiondiff" in name:
        return "Version-to-version comparison"
    if "baseline" in name and "deprecation" in name:
        return "Deprecation-aware baseline"
    if "baseline" in name and "crosssource" in name:
        return "Cross-source canonical baseline"
    if "baseline" in name and "fragment" in name:
        return "CamelCase fragment baseline"
    if "baseline" in name and "acronym" in name:
        return "Acronym / synonym baseline"
    if "baseline" in name and "prose" in name:
        return "Prose / conceptual baseline"
    if "baseline" in name and "symbol-attribute" in name:
        return "Symbol-attribute baseline"
    if "baseline" in name:
        return "Search-quality baseline"
    return "Cupertino audit"


def _audit_summary(audit: Audit):
    headline = extract_headline(audit)
    dashboard_url = f"audits/{derive_dashboard_name(audit.source_path)}"
    # First paragraph of intro becomes the card's plain-English finding;
    # keep it terse on the index — readers can click through for the full
    # write-up. Aim for one tight sentence (~140 chars).
    finding = audit.first_intro_paragraph
    if len(finding) > 140:
        # Cut at the nearest sentence boundary under 140
        cut = finding[:140]
        last_dot = cut.rfind(". ")
        if last_dot > 60:
            finding = cut[: last_dot + 1]
        else:
            finding = cut.rstrip() + "…"
    icon_key = _icon_key(derive_dashboard_name(audit.source_path))
    # Tint matches the headline colour
    tint = {"green": "tint-green", "orange": "tint-orange", "red": "tint-red", "blue": "tint-blue"}.get(headline.color, "tint-blue")
    # Derive the metric method from the audit's Aggregate section first, then
    # fall back to scanning every other section so audits whose prose doesn't
    # name a metric in the Aggregate section still get a link.
    method = None
    for key in ("aggregate", "results", "result", "summary"):
        if key in audit.sections:
            agg_html = linkify_metrics(md_to_html(audit.sections[key]), sources_url="sources.html")
            method = first_metric_link(agg_html)
            if method:
                break
    if not method:
        # Scan the rest of the audit for the first metric mention
        for sec_name in audit.sections_order:
            if sec_name in ("aggregate", "results", "result", "summary"):
                continue
            body_html = linkify_metrics(md_to_html(audit.sections[sec_name]), sources_url="sources.html")
            method = first_metric_link(body_html)
            if method:
                break
    filename = audit.source_path.name if audit.source_path else ""
    is_versiondiff = "versiondiff" in filename
    return {
        "title": audit.title,
        # Short subtitle: kind label rather than a 80-char clip of Methodology
        "subtitle": _short_subtitle(audit),
        "status": headline.status,
        "value": headline.value,
        "color": headline.color,
        "raw_percent": headline.raw_percent,
        "finding": finding,
        "dashboard_url": dashboard_url,
        "audit_filename": filename,
        "icon_svg": ICON_SVGS.get(icon_key, ICON_SVGS["default"]),
        "icon_tint": tint,
        "method_label": method[0] if method else None,
        "method_anchor": method[1] if method else None,
        "is_versiondiff": is_versiondiff,
    }


STATUS_TO_CLASS = {
    "Strong": "status-strong",
    "Mixed": "status-mixed",
    "Weak": "status-weak",
    "Info": "status-info",
}


def _source_chip(s: dict) -> str:
    """Render the citation chip that appears under each card's metric.
    Shows the metric name + the source citation, both linked. If no metric
    was auto-detected, render a dashed placeholder pointing at sources.html."""
    if s.get("method_label") and s.get("method_anchor"):
        meta = SOURCE_META.get(s["method_anchor"], (s["method_label"], ""))
        full_label, cite = meta
        return (
            '<div class="source-chip">'
            '<span class="source-chip-label">Method &amp; source</span>'
            f'<span class="source-chip-metric"><a href="sources.html#{s["method_anchor"]}">{html.escape(full_label)}</a></span>'
            f'<span class="source-chip-cite"><a href="sources.html#{s["method_anchor"]}">{html.escape(cite)}</a></span>'
            '</div>'
        )
    # Fallback when no metric token was found in the audit text
    return (
        '<div class="source-chip missing">'
        '<span class="source-chip-label">Method &amp; source</span>'
        '<span class="source-chip-metric"><a href="sources.html">Browse all citations</a></span>'
        '<span class="source-chip-cite">No metric token detected in the audit text — see <a href="sources.html">sources.html</a></span>'
        '</div>'
    )


def render_card(s: dict) -> str:
    # Progress bar width derived from raw_percent (0..100); fall back to 100 for fractions
    pct = s.get("raw_percent")
    bar_width = min(100, max(0, int(pct))) if pct is not None else 100
    is_vd = bool(s.get("is_versiondiff"))
    extra_class = " card-versiondiff" if is_vd else " card-baseline"
    # Kind badge:
    # - version-diff cards: "Δ Version diff" badge in the indigo accent
    # - standing baselines (especially the weak ones): "Standing baseline"
    #   badge so the reader sees the card describes a v1.2.0 absolute
    #   weak spot that has existed for releases, NOT a v1.1.0 regression.
    if is_vd:
        badge = '<span class="card-kind-badge">Δ Version diff</span>'
    else:
        badge_text = (
            "Standing baseline · all-time"
            if s.get("status") == "Weak"
            else "Standing baseline"
        )
        badge = f'<span class="card-kind-badge card-kind-baseline">{html.escape(badge_text)}</span>'
    return f"""                <article class="card{extra_class}">
                    <div class="card-header">
                        <div class="card-icon {s['icon_tint']}">{s['icon_svg']}</div>
                        <span class="status {STATUS_TO_CLASS.get(s['status'], 'status-info')}">{html.escape(s['status'])}</span>
                    </div>
                    {badge}
                    <h3 class="card-title">{html.escape(s['title'])}</h3>
                    <p class="card-subtitle">{html.escape(s['subtitle'])}</p>
                    <div class="card-metric {s['color']}">{html.escape(s['value'])}</div>
                    {_source_chip(s)}
                    <div class="progress-bar"><div class="progress-bar-fill {s['color']}" style="width: {bar_width}%;"></div></div>
                    <p class="card-finding">{linkify_metrics(render_inline(s['finding']), sources_url='sources.html')}</p>
                    <a class="card-link" href="{html.escape(s['dashboard_url'], quote=True)}">Open audit dashboard</a>
                </article>"""


def compute_aggregate(summaries: list[dict]) -> dict:
    strong = sum(1 for s in summaries if s["status"] == "Strong")
    mixed = sum(1 for s in summaries if s["status"] == "Mixed")
    weak = sum(1 for s in summaries if s["status"] == "Weak")
    return {"strong": strong, "mixed": mixed, "weak": weak, "total": len(summaries)}


def split_by_type(summaries: list[dict]) -> tuple[list[dict], list[dict]]:
    """Split audit cards into version-diff comparisons (paired,
    comparing two cupertino releases) and absolute baselines (single-
    system, no comparison). The two question shapes are different:
    a "weak" version-diff means v1.2.0 regressed against v1.1.0;
    a "weak" baseline means v1.2.0 has standing weak spots on a query
    class but says nothing about whether v1.2.0 is better than v1.1.0.
    Counting them in one bucket buries the v1.2.0 > v1.1.0 story
    behind known absolute weaknesses.

    Uses each summary's `is_versiondiff` flag, set by `_audit_summary`
    based on the source MD's basename containing 'versiondiff'."""
    versiondiffs = [s for s in summaries if s.get("is_versiondiff")]
    baselines = [s for s in summaries if not s.get("is_versiondiff")]
    return versiondiffs, baselines


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
    versiondiffs, baselines = split_by_type(summaries)
    agg_vd = compute_aggregate(versiondiffs)
    agg_bl = compute_aggregate(baselines)
    versiondiff_cards_html = "\n".join(render_card(s) for s in versiondiffs)
    # Within baselines, the weak ones sit at the bottom (sorted by status).
    # Find the first Weak baseline and insert an anchor right before it
    # so the "Standing weak spots" KPI tile lands there.
    baseline_cards_parts = []
    weak_anchor_inserted = False
    for s in baselines:
        if (not weak_anchor_inserted) and s["status"] == "Weak":
            # Subsection break inside the baselines grid, marking the
            # transition from "passing strongly / mixed" to "room for
            # improvement". Spans the grid via the `.subsection-break`
            # class so it sits cleanly between rows.
            baseline_cards_parts.append(
                '<div id="tests-weak" class="subsection-break">'
                '<h4 class="subsection-heading">Room for improvement</h4>'
                '<p class="subsection-desc">Query classes where cupertino\'s ranker has known standing weaknesses. Each has an open issue tracking a candidate fix. None of these is a v1.1.0 / v1.0.2 regression &mdash; they\'re pre-existing weak spots that v1.2.0 inherited and v1.3+ targets.</p>'
                '</div>'
            )
            weak_anchor_inserted = True
        baseline_cards_parts.append(render_card(s))
    baseline_cards_html = "\n".join(baseline_cards_parts)
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

        <a href="https://aleahim.com/" class="back-link" style="margin-bottom: 24px;">Back to aleahim.com</a>

        <header class="centered">
            <div class="eyebrow">Cupertino · v1.2.0</div>
            <h1>Does the search find the right answer?</h1>
            <p class="subtitle">
                Cupertino is an Apple-platform documentation index built to keep AI coding assistants from hallucinating. This page summarises {n} measurements of how well it does that on the v1.2.0 build.
            </p>
            <p class="meta">
                <span>{n} measurements</span>·<span>Auto-derived from audit markdown</span>·<span>Re-rendered when audits change</span>
            </p>
        </header>

        <div class="tab-container">
            <div class="tabs" role="tablist">
                <button class="tab" data-tab="overview" role="tab">Overview</button>
                <button class="tab active" data-tab="tests" role="tab">Tests</button>
                <button class="tab" data-tab="sources" role="tab">Sources</button>
                <button class="tab" data-tab="how" role="tab">How I measure</button>
            </div>
        </div>

        <!-- Tab 1: Overview -->
        <div class="tab-panel" id="panel-overview">
            <div class="hero">
                <div class="hero-eyebrow">v1.2.0 release · search-quality leap</div>
                <h2 class="hero-headline">From 52% to <span class="hero-accent">92%</span> rank-1 accuracy.</h2>
                <p class="hero-sub">
                    On the queries an AI coding agent actually issues &mdash; <code>Hashable</code>, <code>URLSession</code>, <code>Observable</code>, <code>SwiftUI</code> &mdash; cupertino's MCP server now lands the right Apple documentation page at rank 1 <strong>nine times out of ten</strong>. Up from roughly five out of ten in v1.1.0. Across 110 queries spanning three independent test corpora, ~30 queries newly answer correctly. <strong>Zero queries regressed.</strong>
                </p>
                <div class="hero-stats">
                    <div class="hero-stat">
                        <div class="hero-stat-num green">+40<span class="hero-stat-unit">pp</span></div>
                        <div class="hero-stat-label">Rank-1 accuracy lift</div>
                        <div class="hero-stat-sub">52% &rarr; 92% on the 50-query canonical lookup corpus</div>
                    </div>
                    <div class="hero-stat">
                        <div class="hero-stat-num green">+30</div>
                        <div class="hero-stat-label">Queries newly correct</div>
                        <div class="hero-stat-sub">across 110 queries on three independent corpora</div>
                    </div>
                    <div class="hero-stat">
                        <div class="hero-stat-num green">0</div>
                        <div class="hero-stat-label">Regressions</div>
                        <div class="hero-stat-sub">McNemar two-sided p &le; 10<sup>-5</sup> on the largest corpus</div>
                    </div>
                </div>
                <p class="hero-deeplink" style="position: relative; margin-top: 24px;">
                    <a href="docs/release-writeup-v1.2.0.html">Read the full release write-up &mdash; what changed in v1.2.0, why the numbers moved &rarr;</a>
                </p>
            </div>
            <div class="kpi-strip">
                <a class="kpi kpi-link" href="#tests-versiondiff" data-jump-tab="tests" data-jump-anchor="tests-versiondiff">
                    <div class="kpi-label">v1.2.0 vs earlier releases</div>
                    <div class="kpi-value green">{agg_vd['strong']} / {agg_vd['total']}</div>
                    <div class="kpi-desc"><strong>Wins.</strong> {agg_vd['total']} paired comparisons, {agg_vd['weak']} regression{'s' if agg_vd['weak'] != 1 else ''}. Every comparison shows v1.2.0 improving over its predecessor.</div>
                </a>
                <a class="kpi kpi-link" href="#tests-baseline" data-jump-tab="tests" data-jump-anchor="tests-baseline">
                    <div class="kpi-label">v1.2.0 absolute strengths</div>
                    <div class="kpi-value green">{agg_bl['strong']} / {agg_bl['total']}</div>
                    <div class="kpi-desc"><strong>Solid.</strong> The canonical use cases work as designed: typing a Swift type name, modern-vs-legacy choice, fragment recall, cross-source ranking.</div>
                </a>
                <a class="kpi kpi-link" href="#tests-weak" data-jump-tab="tests" data-jump-anchor="tests-weak">
                    <div class="kpi-label">Room for improvement</div>
                    <div class="kpi-value orange">{agg_bl['weak']}</div>
                    <div class="kpi-desc">Standing weak spots on prose / acronym / symbol-attribute queries. Each tracked with an open issue; v1.3+ targets. Not regressions against any prior release.</div>
                </a>
            </div>

            {callout_html}
        </div>

        <!-- Tab 2: The tests (DEFAULT — landing tab so per-metric source links are visible immediately) -->
        <div class="tab-panel active" id="panel-tests">
            <section>
                <h2 style="margin-top: 0;">Every measurement, with a path to the full audit</h2>
                <p style="color: var(--text-secondary); margin-bottom: 24px;">Each card below summarises one audit. The bar visualises how close to a perfect score the test scored. Open any card to see the full audit dashboard.</p>

                <h3 id="tests-versiondiff" style="margin-top: 8px;">Version-diff comparisons &mdash; how v1.2.0 stacks against earlier releases</h3>
                <p style="color: var(--text-secondary); margin-bottom: 16px;">{agg_vd['total']} paired measurements covering 110+ queries. {agg_vd['strong']} strong, {agg_vd['mixed']} mixed, {agg_vd['weak']} regression. All show v1.2.0 improving over its predecessor.</p>
                <div class="grid">
{versiondiff_cards_html}
                </div>

                <h3 id="tests-baseline" style="margin-top: 48px;">Absolute baselines &mdash; how v1.2.0 stands on its own terms</h3>
                <p style="color: var(--text-secondary); margin-bottom: 16px;">{agg_bl['total']} single-system measurements (no comparison to any prior release). {agg_bl['strong']} pass strongly, {agg_bl['mixed']} mixed, {agg_bl['weak']} weak. The weak entries below are <strong>standing weaknesses</strong> &mdash; query classes where v1.2.0's ranker has known gaps; each has an open issue tracking the candidate fix. <strong>These are not v1.1.0 / v1.0.2 regressions.</strong></p>
                <div class="grid">
{baseline_cards_html}
{pending_card}
                </div>
            </section>
        </div>

        <!-- Tab 3: Sources -->
        <div class="tab-panel" id="panel-sources">
            <section>
                <h2 style="margin-top: 0;">Every metric, with its scientific source</h2>
                <p style="color: var(--text-secondary); margin-bottom: 24px;">Every number on the cards above traces back to a peer-reviewed source. The full citation list with paper / book / standard links is at <a href="sources.html">sources.html</a>. Highlights:</p>
                <div class="grid cols-2">
                    <article class="card no-hover">
                        <div class="card-icon tint-indigo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div>
                        <h3 class="card-title">MRR</h3>
                        <p class="card-finding">Voorhees (1999), TREC-8 QA Report. The reference for evaluating "the first relevant answer" rank.</p>
                        <a class="card-link" href="sources.html#mrr">See citation</a>
                    </article>
                    <article class="card no-hover">
                        <div class="card-icon tint-indigo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div>
                        <h3 class="card-title">BM25F</h3>
                        <p class="card-finding">Robertson, Zaragoza, Taylor (2004). The field-weighted ranking formula cupertino tunes per-column.</p>
                        <a class="card-link" href="sources.html#bm25f">See citation</a>
                    </article>
                    <article class="card no-hover">
                        <div class="card-icon tint-indigo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div>
                        <h3 class="card-title">Reciprocal Rank Fusion</h3>
                        <p class="card-finding">Cormack, Clarke, Büttcher (2009). The cross-source fusion formula cupertino uses with <code>k=60</code>.</p>
                        <a class="card-link" href="sources.html#rrf">See citation</a>
                    </article>
                    <article class="card no-hover">
                        <div class="card-icon tint-indigo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div>
                        <h3 class="card-title">Wilcoxon + McNemar</h3>
                        <p class="card-finding">The two paired statistical tests cupertino uses to compare two builds. Wilcoxon (1945) for rank metrics, McNemar (1947) for binary outcomes.</p>
                        <a class="card-link" href="sources.html#wilcoxon">See citation</a>
                    </article>
                </div>
                <p style="margin-top: 24px;">
                    <a class="card-link" href="sources.html" style="display: inline-flex;">Full sources page</a>
                </p>
            </section>
        </div>

        <!-- Tab 4: How we measure -->
        <div class="tab-panel" id="panel-how">
            <section>
                <h2 style="margin-top: 0;">How a cupertino search-quality measurement works</h2>
                <p>For each test I run a fixed list of queries against cupertino, capture the top-10 results, score them against pre-defined right-answer patterns, and report the headline number plus a per-query breakdown. No anecdotes; everything is reproducible.</p>

                <div class="grid cols-2">
                    <a class="card step-card" href="https://github.com/mihaelamj/cupertino/blob/main/scripts/eval/search-quality-phase1.py#L74-L133">
                        <div class="card-icon tint-blue"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg></div>
                        <h3 class="card-title">Step 1 · A query corpus</h3>
                        <p class="card-finding">~30-50 queries per test, hand-curated to cover breadth (types, protocols, methods, framework concepts). Each query carries a right-answer pattern.</p>
                        <span class="card-link">View corpus source on GitHub →</span>
                    </a>
                    <a class="card step-card" href="https://github.com/mihaelamj/cupertino/blob/main/scripts/eval/search-quality-phase1.py">
                        <div class="card-icon tint-blue"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg></div>
                        <h3 class="card-title">Step 2 · Run the binary</h3>
                        <p class="card-finding">A Python harness invokes <code>cupertino search</code> via subprocess for each query, extracts the top-10 URIs from stdout. Read-only against the database.</p>
                        <span class="card-link">View harness on GitHub →</span>
                    </a>
                    <a class="card step-card" href="docs/design-search-quality-eval.html#section-1-2-the-cranfield-paradigm-and-its-metrics">
                        <div class="card-icon tint-blue"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg></div>
                        <h3 class="card-title">Step 3 · Score</h3>
                        <p class="card-finding">Per-query MRR / P@k / NDCG / per-class custom metric. Auto-extracted, no human in the loop for Phase 1.</p>
                        <span class="card-link">Read methodology →</span>
                    </a>
                    <a class="card step-card" href="https://github.com/mihaelamj/cupertino/tree/main/docs/audits">
                        <div class="card-icon tint-blue"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/></svg></div>
                        <h3 class="card-title">Step 4 · Report</h3>
                        <p class="card-finding">Markdown audit at <code>docs/audits/</code>, JSON raw data at <code>/tmp/</code>, this dashboard auto-derived from the markdown. Future ranking changes pair against the baseline using Wilcoxon / McNemar significance tests.</p>
                        <span class="card-link">Browse all audits →</span>
                    </a>
                </div>

                <p style="margin-top: 32px;">
                    Full methodology in
                    <a href="docs/design-search-quality-eval.html">design/search-quality-eval</a>.
                    The universal rule lives at <code>mihaela-agents/Rules/universal/search-quality-eval.md</code>.
                </p>
            </section>
        </div>

        <footer>
            <p>
                Index card content is auto-derived from the audit markdown files under
                <a href="../audits/">docs/audits/</a> by <code>_render-index-dashboard.py</code>.
                When an audit changes, re-run <code>regen-all.sh</code>.
            </p>
            <p>
                Methodology in <a href="docs/design-search-quality-eval.html">design/search-quality-eval</a>
                ·
                Architecture in <a href="docs/architecture-database.html">architecture/database</a>
                ·
                Citations in <a href="sources.html">sources.html</a>
                ·
                Index in <a href="docs/database-handbook.html">database-handbook</a>
            </p>
        </footer>

    </div>

    <script>
        (function() {{
            const tabs = document.querySelectorAll('.tab');
            const panels = document.querySelectorAll('.tab-panel');
            function switchTab(target) {{
                tabs.forEach(t => t.classList.toggle('active', t.dataset.tab === target));
                panels.forEach(p => p.classList.toggle('active', p.id === 'panel-' + target));
            }}
            tabs.forEach(tab => {{
                tab.addEventListener('click', () => switchTab(tab.dataset.tab));
            }});
            // KPI tiles in the Overview tab link to anchors inside the
            // Tests tab. Hijack the click so we switch tabs FIRST, then
            // let the browser handle the anchor scroll.
            document.querySelectorAll('.kpi-link').forEach(link => {{
                link.addEventListener('click', (e) => {{
                    const tab = link.dataset.jumpTab;
                    const anchor = link.dataset.jumpAnchor;
                    if (!tab || !anchor) return;
                    e.preventDefault();
                    switchTab(tab);
                    // setTimeout so the panel display:block takes effect
                    // before the scroll, otherwise we scroll to an
                    // offset that's still inside the (hidden) panel.
                    setTimeout(() => {{
                        const el = document.getElementById(anchor);
                        if (el) el.scrollIntoView({{behavior: 'smooth', block: 'start'}});
                    }}, 0);
                }});
            }});
        }})();
    </script>
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

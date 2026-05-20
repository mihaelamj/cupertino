#!/usr/bin/env python3
"""
Inline-SVG chart helpers for the cupertino dashboards.

No external deps. Charts emit a single <svg> with embedded <style> so they
work on file:// URLs, on GitHub Pages, and pasted into a blog post. Colours
adapt to light/dark via the dashboard's CSS tokens; the SVGs use
`currentColor` and CSS variable references for theme-awareness.

The charts here are designed to be informationally honest at a glance.
A reader should be able to look for ~3 seconds and know whether the
comparison is a win, a wash, or a regression. No gradient gimmicks, no
3D effects, no tooltips on critical information.

Three chart types are exposed:

- `bar_compare_metrics`  — grouped bars: before vs after for several metrics.
- `bucket_donut`         — donut chart of the four-bucket diff (added /
                           removed / fixed / degraded / unchanged).
- `rank_slope`           — per-query before/after rank slope chart with
                           hover labels.

All three are self-contained <svg>. They render at any width via
`viewBox` + CSS `max-width: 100%`. Hover labels use SVG <title> elements
which every browser surfaces as native tooltips, no JS required.
"""

from __future__ import annotations

import html
from dataclasses import dataclass
from typing import Iterable


# Apple system palette referenced by name where it matches the dashboard.
# Where Mermaid bootstrap uses a CSS var, we use the literal value here so
# the SVG renders correctly when inlined into a markdown blog post that
# doesn't carry our stylesheet.
COLORS = {
    "primary":  "#007AFF",  # apple-blue
    "secondary":"#5856D6",  # apple-indigo
    "good":     "#34C759",  # apple-green
    "warn":     "#FF9500",  # apple-orange
    "bad":      "#FF3B30",  # apple-red
    "neutral":  "#86868b",  # text-tertiary
    "grid":     "#d2d2d7",
    "text":     "#1d1d1f",
    "text2":    "#6e6e73",
    "bg":       "#ffffff",
}


# ---------------------------------------------------------------------------
# Grouped bar: before vs after, multiple metrics
# ---------------------------------------------------------------------------


@dataclass
class BarMetric:
    name: str
    before: float
    after: float
    # Optional pretty-print format for the value labels (e.g. "{:.4f}")
    fmt: str = "{:.4f}"
    # If True, render delta as +N or -N with explicit sign
    show_delta: bool = True


def bar_compare_metrics(
    metrics: list[BarMetric],
    label_before: str = "Before",
    label_after: str = "After",
    caption: str = "",
    chart_id: str = "bar-compare",
) -> str:
    """A grouped vertical bar chart, one cluster per metric.

    Each cluster has two bars (before / after) plus a small delta callout
    above. Y-axis is auto-scaled to the max value across all bars; if all
    metrics are <=1 the axis caps at 1.0 (good default for MRR / P@1).
    """
    if not metrics:
        return ""

    max_val = max(max(m.before, m.after) for m in metrics)
    if max_val <= 1.0:
        y_top = 1.0
    elif max_val <= 2.0:
        y_top = 2.0
    else:
        y_top = (int(max_val) + 1)

    # Layout constants (viewBox units).
    W = 720
    H = 340
    MARGIN_L = 60
    MARGIN_R = 30
    MARGIN_T = 40
    MARGIN_B = 90
    plot_w = W - MARGIN_L - MARGIN_R
    plot_h = H - MARGIN_T - MARGIN_B

    n = len(metrics)
    cluster_w = plot_w / n
    bar_w = cluster_w * 0.32
    gap = cluster_w * 0.08

    def y(v: float) -> float:
        return MARGIN_T + plot_h - (v / y_top) * plot_h

    parts: list[str] = []
    # Y-axis gridlines + labels
    for i in range(5):
        val = y_top * i / 4
        gy = y(val)
        parts.append(
            f'<line x1="{MARGIN_L}" y1="{gy:.1f}" x2="{W - MARGIN_R}" y2="{gy:.1f}" '
            f'class="chart-grid" />'
        )
        parts.append(
            f'<text x="{MARGIN_L - 8}" y="{gy + 4:.1f}" '
            f'class="chart-axis-label" text-anchor="end">{val:.2f}</text>'
        )

    # Bars
    for idx, m in enumerate(metrics):
        cx = MARGIN_L + idx * cluster_w + cluster_w / 2
        bx = cx - bar_w - gap / 2
        ax = cx + gap / 2

        b_top = y(m.before)
        a_top = y(m.after)
        b_h = (MARGIN_T + plot_h) - b_top
        a_h = (MARGIN_T + plot_h) - a_top

        delta = m.after - m.before
        improved = delta > 0.0001
        worsened = delta < -0.0001
        delta_color = COLORS["good"] if improved else (COLORS["bad"] if worsened else COLORS["neutral"])

        # Before bar
        tip_before = (
            f"<b>{html.escape(m.name)}</b><br/>"
            f"<span class='tip-key'>{html.escape(label_before)}</span> "
            f"<span class='tip-val'>{m.fmt.format(m.before)}</span>"
        )
        parts.append(
            f'<rect x="{bx:.1f}" y="{b_top:.1f}" width="{bar_w:.1f}" height="{b_h:.1f}" '
            f'class="chart-bar-before chart-hoverable" rx="4" data-tooltip="{html.escape(tip_before, quote=True)}">'
            f'<title>{html.escape(label_before)} · {html.escape(m.name)}: {m.fmt.format(m.before)}</title>'
            f'</rect>'
        )
        # After bar
        delta_sign = "+" if (m.after - m.before) >= 0 else ""
        tip_after = (
            f"<b>{html.escape(m.name)}</b><br/>"
            f"<span class='tip-key'>{html.escape(label_after)}</span> "
            f"<span class='tip-val'>{m.fmt.format(m.after)}</span><br/>"
            f"<span class='tip-delta'>Delta {delta_sign}{m.fmt.format(m.after - m.before)}</span>"
        )
        parts.append(
            f'<rect x="{ax:.1f}" y="{a_top:.1f}" width="{bar_w:.1f}" height="{a_h:.1f}" '
            f'class="chart-bar-after chart-hoverable" rx="4" data-tooltip="{html.escape(tip_after, quote=True)}">'
            f'<title>{html.escape(label_after)} · {html.escape(m.name)}: {m.fmt.format(m.after)}</title>'
            f'</rect>'
        )
        # Value labels on top of bars
        parts.append(
            f'<text x="{bx + bar_w / 2:.1f}" y="{b_top - 6:.1f}" '
            f'class="chart-bar-value" text-anchor="middle">{m.fmt.format(m.before)}</text>'
        )
        parts.append(
            f'<text x="{ax + bar_w / 2:.1f}" y="{a_top - 6:.1f}" '
            f'class="chart-bar-value" text-anchor="middle">{m.fmt.format(m.after)}</text>'
        )
        # Delta callout above the cluster
        if m.show_delta:
            sign = "+" if delta >= 0 else ""
            parts.append(
                f'<text x="{cx:.1f}" y="{MARGIN_T - 18:.1f}" '
                f'class="chart-delta" text-anchor="middle" fill="{delta_color}">'
                f'{sign}{m.fmt.format(delta)}</text>'
            )
        # Metric name below the cluster
        parts.append(
            f'<text x="{cx:.1f}" y="{H - MARGIN_B + 22:.1f}" '
            f'class="chart-axis-label" text-anchor="middle">{html.escape(m.name)}</text>'
        )

    # X-axis baseline
    parts.append(
        f'<line x1="{MARGIN_L}" y1="{MARGIN_T + plot_h:.1f}" '
        f'x2="{W - MARGIN_R}" y2="{MARGIN_T + plot_h:.1f}" class="chart-axis" />'
    )

    # Legend (bottom)
    legend_y = H - 28
    legend_xs = [MARGIN_L + 20, MARGIN_L + 160]
    parts.append(
        f'<rect x="{legend_xs[0]}" y="{legend_y - 10}" width="14" height="14" '
        f'class="chart-bar-before" rx="3"/>'
        f'<text x="{legend_xs[0] + 22}" y="{legend_y + 1}" class="chart-legend">{html.escape(label_before)}</text>'
        f'<rect x="{legend_xs[1]}" y="{legend_y - 10}" width="14" height="14" '
        f'class="chart-bar-after" rx="3"/>'
        f'<text x="{legend_xs[1] + 22}" y="{legend_y + 1}" class="chart-legend">{html.escape(label_after)}</text>'
    )

    cap_html = ""
    if caption:
        cap_html = f'<figcaption class="chart-caption">{html.escape(caption)}</figcaption>'

    return (
        f'<figure class="chart" id="{html.escape(chart_id)}">'
        f'<svg viewBox="0 0 {W} {H}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="{html.escape(caption or "Comparison chart")}">'
        + "".join(parts)
        + '</svg>'
        + cap_html
        + '</figure>'
    )


# ---------------------------------------------------------------------------
# Donut chart — small categorical breakdown
# ---------------------------------------------------------------------------


@dataclass
class DonutSlice:
    label: str
    value: int
    color: str
    description: str = ""


def bucket_donut(slices: list[DonutSlice], total_label: str = "", caption: str = "", chart_id: str = "donut") -> str:
    """A donut chart with a center label and external annotations.

    Each slice has a <title> for hover; total goes in the center.
    """
    total = sum(s.value for s in slices)
    if total == 0:
        return ""

    W = 720
    H = 360
    cx = 220
    cy = H / 2
    r_outer = 130
    r_inner = 80

    parts: list[str] = []

    # Build pie slices
    import math
    angle = -math.pi / 2  # start at 12 o'clock
    for s in slices:
        if s.value == 0:
            continue
        frac = s.value / total
        a_end = angle + frac * 2 * math.pi
        large = 1 if frac > 0.5 else 0

        x1 = cx + r_outer * math.cos(angle)
        y1 = cy + r_outer * math.sin(angle)
        x2 = cx + r_outer * math.cos(a_end)
        y2 = cy + r_outer * math.sin(a_end)
        xi1 = cx + r_inner * math.cos(angle)
        yi1 = cy + r_inner * math.sin(angle)
        xi2 = cx + r_inner * math.cos(a_end)
        yi2 = cy + r_inner * math.sin(a_end)

        path = (
            f"M {x1:.1f} {y1:.1f} "
            f"A {r_outer} {r_outer} 0 {large} 1 {x2:.1f} {y2:.1f} "
            f"L {xi2:.1f} {yi2:.1f} "
            f"A {r_inner} {r_inner} 0 {large} 0 {xi1:.1f} {yi1:.1f} "
            f"Z"
        )
        pct = frac * 100
        tip = (
            f"<b>{html.escape(s.label)}</b><br/>"
            f"<span class='tip-val'>{s.value} of {total}</span> "
            f"<span class='tip-key'>({pct:.0f}%)</span>"
        )
        if s.description:
            tip += f"<br/><span class='tip-desc'>{html.escape(s.description)}</span>"
        parts.append(
            f'<path d="{path}" fill="{s.color}" opacity="0.92" stroke="var(--bg-card, #ffffff)" stroke-width="2" '
            f'class="chart-hoverable donut-slice" data-tooltip="{html.escape(tip, quote=True)}">'
            f'<title>{html.escape(s.label)}: {s.value} ({pct:.0f}%)</title>'
            f'</path>'
        )
        angle = a_end

    # Center label
    parts.append(
        f'<text x="{cx}" y="{cy - 6}" text-anchor="middle" class="donut-center-num">{total}</text>'
    )
    if total_label:
        parts.append(
            f'<text x="{cx}" y="{cy + 18}" text-anchor="middle" class="donut-center-label">{html.escape(total_label)}</text>'
        )

    # External legend (right side)
    legend_x = 440
    legend_y = 50
    line_h = 50
    for i, s in enumerate(slices):
        pct = (s.value / total * 100) if total else 0
        y = legend_y + i * line_h
        parts.append(
            f'<rect x="{legend_x}" y="{y}" width="14" height="14" rx="3" fill="{s.color}"/>'
            f'<text x="{legend_x + 22}" y="{y + 12}" class="donut-legend-key">{html.escape(s.label)} <tspan class="donut-legend-num">· {s.value} ({pct:.0f}%)</tspan></text>'
        )
        if s.description:
            parts.append(
                f'<text x="{legend_x + 22}" y="{y + 30}" class="donut-legend-desc">{html.escape(s.description)}</text>'
            )

    cap_html = (
        f'<figcaption class="chart-caption">{html.escape(caption)}</figcaption>'
        if caption else ""
    )

    return (
        f'<figure class="chart" id="{html.escape(chart_id)}">'
        f'<svg viewBox="0 0 {W} {H}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="{html.escape(caption or "Bucket breakdown")}">'
        + "".join(parts)
        + '</svg>'
        + cap_html
        + '</figure>'
    )


# ---------------------------------------------------------------------------
# Slope chart — per-item before/after rank movement
# ---------------------------------------------------------------------------


@dataclass
class SlopePoint:
    name: str
    before: float | None  # None means "outside the chart bounds"
    after: float | None


def rank_slope(
    points: list[SlopePoint],
    label_before: str = "Before",
    label_after: str = "After",
    y_top: int = 10,
    inverse_y: bool = True,
    caption: str = "",
    chart_id: str = "slope",
) -> str:
    """Dumbbell chart: one row per CHANGED query, two dots connected by a
    coloured line spanning the rank range. The old two-vertical-anchor
    slope layout stacked all "to rank 1" labels into an unreadable blob;
    the dumbbell gives each query its own row.

    X-axis: rank 1 (left) to `y_top` (right), then a "10+" slot for
    queries that fell outside the top 10. Y-axis: one row per changed
    query, sorted by improvement magnitude. Unchanged queries collapse
    into a single summary row at the bottom.
    """
    if not points:
        return ""

    missing_rank = y_top + 1

    def nrm(r):
        return missing_rank if r is None else float(r)

    changed = [p for p in points if nrm(p.before) != nrm(p.after)]
    unchanged = [p for p in points if nrm(p.before) == nrm(p.after)]
    changed.sort(key=lambda p: (nrm(p.after) - nrm(p.before), p.name))

    row_h = 28
    rows = len(changed) + (1 if unchanged else 0)
    W = 760
    MARGIN_L = 200
    MARGIN_R = 60
    MARGIN_T = 70
    MARGIN_B = 30
    plot_w = W - MARGIN_L - MARGIN_R
    H = MARGIN_T + rows * row_h + MARGIN_B

    def xpos(r):
        return MARGIN_L + (nrm(r) - 1) / (missing_rank - 1) * plot_w

    parts: list[str] = []

    # Top tick marks for ranks 1, 3, 5, 10, 10+
    for tr in [1, 3, 5, 10]:
        tx = xpos(tr)
        parts.append(
            f'<line x1="{tx:.1f}" y1="{MARGIN_T - 8}" x2="{tx:.1f}" y2="{MARGIN_T + rows * row_h:.1f}" class="chart-grid"/>'
        )
        parts.append(
            f'<text x="{tx:.1f}" y="{MARGIN_T - 18:.1f}" class="chart-axis-label" text-anchor="middle">{tr}</text>'
        )
    tx = xpos(None)
    parts.append(
        f'<line x1="{tx:.1f}" y1="{MARGIN_T - 8}" x2="{tx:.1f}" y2="{MARGIN_T + rows * row_h:.1f}" class="chart-grid"/>'
    )
    parts.append(
        f'<text x="{tx:.1f}" y="{MARGIN_T - 18:.1f}" class="chart-axis-label" text-anchor="middle">10+</text>'
    )
    parts.append(
        f'<text x="{MARGIN_L}" y="{MARGIN_T - 42}" class="chart-axis-label" text-anchor="start">'
        f'← better rank · v1.0.2 (○) → v1.2.0 (●) · worse rank →</text>'
    )

    # One row per changed query
    for i, p in enumerate(changed):
        y = MARGIN_T + i * row_h + row_h / 2
        b_x = xpos(p.before)
        a_x = xpos(p.after)
        b_rank = "10+" if p.before is None else str(int(p.before))
        a_rank = "10+" if p.after is None else str(int(p.after))
        improved = nrm(p.after) < nrm(p.before)
        worsened = nrm(p.after) > nrm(p.before)
        color = COLORS["good"] if improved else (COLORS["bad"] if worsened else COLORS["neutral"])
        direction = "improved" if improved else ("regressed" if worsened else "unchanged")

        if i % 2 == 1:
            parts.append(
                f'<rect x="{MARGIN_L - 4}" y="{y - row_h / 2:.1f}" width="{plot_w + 8}" height="{row_h}" class="dumbbell-row-stripe"/>'
            )

        parts.append(
            f'<text x="{MARGIN_L - 12}" y="{y + 4:.1f}" class="slope-name" text-anchor="end">{html.escape(p.name)}</text>'
        )
        tip = (
            f"<b>{html.escape(p.name)}</b><br/>"
            f"<span class='tip-key'>v1.0.2 rank</span> <span class='tip-val'>{b_rank}</span><br/>"
            f"<span class='tip-key'>v1.2.0 rank</span> <span class='tip-val'>{a_rank}</span><br/>"
            f"<span class='tip-delta tip-{direction}'>{direction}</span>"
        )
        lx = min(b_x, a_x)
        rx = max(b_x, a_x)
        parts.append(
            f'<g class="slope-group chart-hoverable" data-tooltip="{html.escape(tip, quote=True)}">'
            f'<line x1="{lx:.1f}" y1="{y:.1f}" x2="{rx:.1f}" y2="{y:.1f}" stroke="{color}" stroke-width="3" opacity="0.85" stroke-linecap="round"/>'
            f'<circle cx="{b_x:.1f}" cy="{y:.1f}" r="6" fill="var(--bg-card, #ffffff)" stroke="{color}" stroke-width="2"/>'
            f'<circle cx="{a_x:.1f}" cy="{y:.1f}" r="6" fill="{color}"/>'
            f'</g>'
        )
        parts.append(
            f'<text x="{b_x:.1f}" y="{y - 11:.1f}" class="dumbbell-rank" text-anchor="middle" fill="{color}" opacity="0.7">{b_rank}</text>'
        )
        parts.append(
            f'<text x="{a_x:.1f}" y="{y - 11:.1f}" class="dumbbell-rank" text-anchor="middle" fill="{color}">{a_rank}</text>'
        )

    if unchanged:
        i = len(changed)
        y = MARGIN_T + i * row_h + row_h / 2
        n_un = len(unchanged)
        all_top1 = all(nrm(p.before) == 1 and nrm(p.after) == 1 for p in unchanged)
        suffix = " (all already at rank 1)" if all_top1 else ""
        parts.append(
            f'<text x="{MARGIN_L - 12}" y="{y + 4:.1f}" class="slope-name slope-name-faint" text-anchor="end">+ {n_un} unchanged{suffix}</text>'
        )
        parts.append(
            f'<line x1="{MARGIN_L}" y1="{y:.1f}" x2="{MARGIN_L + plot_w:.1f}" y2="{y:.1f}" stroke="{COLORS["neutral"]}" stroke-width="1" opacity="0.25" stroke-dasharray="3 4"/>'
        )

    cap_html = (
        f'<figcaption class="chart-caption">{html.escape(caption)}</figcaption>'
        if caption else ""
    )

    return (
        f'<figure class="chart" id="{html.escape(chart_id)}">'
        f'<svg viewBox="0 0 {W} {H}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="{html.escape(caption or "Per-query rank shift")}">'
        + "".join(parts)
        + '</svg>'
        + cap_html
        + '</figure>'
    )

#!/usr/bin/env python3
"""
Render any cupertino markdown doc (design doc, architecture doc, PRINCIPLES,
audit, postmortem, anything) as a styled HTML page.

This is the rich, structure-aware counterpart to the per-audit dashboard
renderer. Design docs are not lists of numbers; they're prose, definitions,
ID'd goals (G1, NG1, F1, ...), requirements tables, blockquotes, and ASCII
diagrams. We light them up with:

  - sticky TOC sidebar (from ## headers)
  - numbered section badges
  - lead-paragraph styling per section
  - definition-row rendering for list items shaped `**ID**: …`
  - pull-quote styling for blockquotes
  - companion-docs cross-link card if the header table lists them
  - sources-cited card grid at the bottom (auto-collected via linkify pass)

Usage:
    python3 _render-doc.py <path/to/doc.md>

Produces:
    docs/<derived-name>.html  (under the dashboards/ folder)
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

from _audit_parser import (
    SOURCE_META,
    find_cited_sources,
    linkify_metrics,
    md_to_html,
)


# Mermaid bootstrap. Injected only when the page actually contains a
# `<pre class="mermaid">` block. Uses the official ESM CDN. Picks light
# vs dark theme from `prefers-color-scheme` so the diagram matches the
# page (the doc pages already react to that media query via CSS tokens).
#
# We render Mermaid eagerly with `mermaid.run()` rather than relying on
# `startOnLoad`, because when this HTML is embedded into a blog post the
# `DOMContentLoaded` event may have already fired by the time the script
# runs.
MERMAID_BOOTSTRAP = """    <script src=\"https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js\"></script>
    <script>
    (function() {
        if (typeof mermaid === 'undefined') {
            console.warn('mermaid failed to load from CDN');
            return;
        }
        var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        var apple = '-apple-system, BlinkMacSystemFont, \"SF Pro Display\", \"SF Pro Text\", \"Helvetica Neue\", Arial, sans-serif';
        var light = {
            background: '#ffffff',
            primaryColor: '#ffffff',
            primaryTextColor: '#1d1d1f',
            primaryBorderColor: '#d2d2d7',
            secondaryColor: '#f5f5f7',
            tertiaryColor: '#ffffff',
            lineColor: '#6e6e73',
            edgeLabelBackground: '#f5f5f7',
            clusterBkg: '#f5f5f7',
            clusterBorder: '#d2d2d7',
            mainBkg: '#ffffff',
            textColor: '#1d1d1f',
            nodeTextColor: '#1d1d1f',
            fontFamily: apple,
        };
        var dark = {
            darkMode: true,
            background: '#1c1c1e',
            primaryColor: '#2c2c2e',
            primaryTextColor: '#ffffff',
            primaryBorderColor: '#48484a',
            secondaryColor: '#1c1c1e',
            tertiaryColor: '#2c2c2e',
            lineColor: '#aeaeb2',
            edgeLabelBackground: '#2c2c2e',
            clusterBkg: '#1c1c1e',
            clusterBorder: '#48484a',
            mainBkg: '#2c2c2e',
            textColor: '#ffffff',
            nodeTextColor: '#ffffff',
            fontFamily: apple,
        };
        mermaid.initialize({
            startOnLoad: true,
            theme: 'base',
            themeVariables: prefersDark ? dark : light,
            fontFamily: apple,
            securityLevel: 'loose',
            flowchart: { htmlLabels: true, curve: 'basis', useMaxWidth: true },
        });
    })();
    </script>"""


# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------


def parse_doc(md: str) -> tuple[str, dict[str, str], str]:
    """Return (title, header_block, body_md).

    Recognises two header forms:
      1. Markdown table at the top:
            | Field | Value |
            |---|---|
            | **Status** | draft |
      2. Inline-style header:
            **Date:** 2026-05-20
            **Methodology:** …
    """
    lines = md.splitlines()
    i = 0
    while i < len(lines) and not lines[i].startswith("# "):
        i += 1
    title = lines[i][2:].strip() if i < len(lines) else "(untitled)"
    i += 1

    header_block: dict[str, str] = {}
    while i < len(lines) and not lines[i].strip():
        i += 1

    # Form 1: table header (Field | Value)
    if i < len(lines) and lines[i].startswith("|"):
        while i < len(lines) and lines[i].startswith("|"):
            if "---" not in lines[i]:
                cells = [c.strip() for c in lines[i].strip("|").split("|")]
                if len(cells) >= 2:
                    key = cells[0].replace("*", "").strip()
                    val = cells[1].strip()
                    if key and key.lower() != "field":
                        header_block[key] = val
            i += 1
        while i < len(lines) and (not lines[i].strip() or lines[i].strip() == "---"):
            i += 1

    # Form 2: inline `**Key:** value` lines
    while i < len(lines):
        line = lines[i]
        m = re.match(r"\*\*([^*]+):\*\*\s*(.*)$", line)
        if m:
            header_block[m.group(1).strip()] = m.group(2).strip()
            i += 1
            continue
        if not line.strip():
            i += 1
            if i < len(lines) and re.match(r"\*\*[^*]+:\*\*", lines[i]):
                continue
            break
        break

    body_md = "\n".join(lines[i:])
    return (title, header_block, body_md)


def split_sections(body_md: str) -> list[tuple[str, str]]:
    """Split body by `## ` headers. Each entry is (header, section_body_md)."""
    sections: list[tuple[str, str]] = []
    lines = body_md.splitlines()
    current_name: str = ""
    current_body: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if current_name or current_body:
                sections.append((current_name, "\n".join(current_body).rstrip()))
            current_name = line[3:].strip()
            current_body = []
        else:
            current_body.append(line)
    if current_name or current_body:
        sections.append((current_name, "\n".join(current_body).rstrip()))
    return sections


# ---------------------------------------------------------------------------
# Section / TOC helpers
# ---------------------------------------------------------------------------


_SECTION_NUM_RE = re.compile(r"^(\d+(?:\.\d+)*)\.?\s+(.+)$")


def split_section_number(header: str) -> tuple[str, str]:
    """`1. Context` → (`1`, `Context`).  `TL;DR` → (`§`, `TL;DR`)."""
    m = _SECTION_NUM_RE.match(header)
    if m:
        return (m.group(1), m.group(2).strip())
    return ("§", header.strip())


def slugify(text: str) -> str:
    out = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return out or "section"


# ---------------------------------------------------------------------------
# Rich rendering passes (run AFTER md_to_html)
# ---------------------------------------------------------------------------


# Match list items that start with a bolded ID followed by `:`. Examples:
#   <li><strong>G1</strong>: A reproducible harness…</li>
#   <li><strong>NG1</strong>: General-purpose LLM evaluation. …</li>
#   <li><strong>F1</strong>: Task corpus of ≥30 Swift coding tasks…</li>
_DEF_LI_RE = re.compile(
    r"<li>\s*<strong>([^<]{1,12})</strong>\s*[:.]?\s*(.*?)</li>",
    re.DOTALL,
)


def transform_definition_lists(html_text: str) -> str:
    """Replace `<ul>` blocks composed entirely of `<li><strong>ID</strong>: ...</li>`
    items with a styled definition list with chip + body rows."""

    def replace_ul(match: re.Match) -> str:
        body = match.group(1)
        items = _DEF_LI_RE.findall(body)
        all_items = re.findall(r"<li>(.*?)</li>", body, flags=re.DOTALL)
        if not items or len(items) != len(all_items):
            return match.group(0)
        rows = []
        for chip, content in items:
            chip_cls = _chip_class_for(chip)
            rows.append(
                f'<div class="def-row">'
                f'<span class="def-chip {chip_cls}">{html.escape(chip)}</span>'
                f'<div class="def-body">{content.strip()}</div>'
                f'</div>'
            )
        return '<div class="def-list">' + "".join(rows) + "</div>"

    return re.sub(r"<ul>(.*?)</ul>", replace_ul, html_text, flags=re.DOTALL)


def _chip_class_for(chip: str) -> str:
    c = chip.strip().upper()
    if c.startswith("NG"):
        return "chip-warn"
    if c.startswith("G"):
        return "chip-good"
    if c.startswith("F"):
        return "chip-info"
    if c.startswith("N"):
        return "chip-neutral"
    if c.startswith("P0"):
        return "chip-good"
    if c.startswith("P1"):
        return "chip-info"
    if c.startswith("P2"):
        return "chip-neutral"
    if c.startswith("R"):
        return "chip-info"
    return "chip-neutral"


def mark_lead_paragraph(section_html: str) -> str:
    """First `<p>` in a section becomes the visual lead."""
    return re.sub(
        r"<p>",
        '<p class="lead">',
        section_html,
        count=1,
    )


# ---------------------------------------------------------------------------
# Section + page assembly
# ---------------------------------------------------------------------------


def render_section(header: str, body_md: str, full_html_accum: list[str]) -> tuple[str, str, str]:
    """Render one `## ` section. Returns (section_html, toc_label, anchor)."""
    section_num, section_title = split_section_number(header)
    anchor = slugify(header)

    body_html = md_to_html(body_md)
    body_html = linkify_metrics(body_html, sources_url="../sources.html")
    body_html = transform_definition_lists(body_html)
    body_html = mark_lead_paragraph(body_html)

    full_html_accum.append(body_html)

    badge_html = (
        f'<span class="section-number-badge">{html.escape(section_num)}</span>'
        if section_num != "§"
        else ""
    )
    section_html = (
        f'<section id="{anchor}" class="doc-section">'
        f'<h2>{badge_html}<span class="section-title">{html.escape(section_title)}</span></h2>'
        f'{body_html}'
        f'</section>'
    )
    return (section_html, header, anchor)


def render_intro(intro_md: str, full_html_accum: list[str]) -> str:
    if not intro_md.strip():
        return ""
    body_html = md_to_html(intro_md)
    body_html = linkify_metrics(body_html, sources_url="../sources.html")
    body_html = transform_definition_lists(body_html)
    body_html = mark_lead_paragraph(body_html)
    full_html_accum.append(body_html)
    return f'<section class="doc-section doc-intro">{body_html}</section>'


def render_header_card(header_block: dict[str, str]) -> str:
    if not header_block:
        return ""
    pills = []
    for key, val in header_block.items():
        val_text = re.sub(r"\*\*([^*]+)\*\*", r"\1", val)
        val_text = re.sub(r"`([^`]+)`", r"\1", val_text)
        val_text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", val_text)
        pills.append(
            f'<div class="meta-row">'
            f'<span class="meta-key">{html.escape(key)}</span>'
            f'<span class="meta-val">{html.escape(val_text)}</span>'
            f'</div>'
        )
    return f'<div class="doc-meta-card">{"".join(pills)}</div>'


def render_companion_card(header_block: dict[str, str]) -> str:
    raw = header_block.get("Companion docs") or header_block.get("Companion") or ""
    if not raw:
        return ""
    items = [s.strip().rstrip(".;") for s in re.split(r";\s*", raw) if s.strip()]
    links = []
    for item in items:
        m = re.match(r"`?([^`\s]+\.md)`?(.*)$", item)
        if m:
            path = m.group(1)
            tail = m.group(2).strip().lstrip("()")
            label = path
            html_target = _doc_md_to_html_url(path)
            links.append(
                f'<a class="companion-link" href="{html_target}">'
                f'<span class="companion-path">{html.escape(label)}</span>'
                + (f'<span class="companion-note">{html.escape(tail)}</span>' if tail else "")
                + '</a>'
            )
        else:
            links.append(f'<span class="companion-note">{html.escape(item)}</span>')
    if not links:
        return ""
    return (
        '<div class="companion-card">'
        '<div class="companion-title">Companion docs</div>'
        f'<div class="companion-grid">{"".join(links)}</div>'
        '</div>'
    )


def _doc_md_to_html_url(md_path: str) -> str:
    """`docs/design/cupertino.md` → `design-cupertino.html`.
    `architecture/database.md` → `architecture-database.html`."""
    p = md_path
    if p.startswith("docs/"):
        p = p[5:]
    p = re.sub(r"\.md$", ".html", p)
    return p.replace("/", "-")


def render_toc(toc_entries: list[tuple[str, str]]) -> str:
    """toc_entries is [(label, anchor), ...]."""
    if not toc_entries:
        return ""
    rows = []
    for label, anchor in toc_entries:
        num, title = split_section_number(label)
        marker = (
            f'<span class="toc-num">{html.escape(num)}</span>'
            if num != "§"
            else '<span class="toc-num toc-num-glyph">§</span>'
        )
        rows.append(
            f'<a class="toc-row" href="#{anchor}">'
            f'{marker}<span class="toc-label">{html.escape(title)}</span>'
            f'</a>'
        )
    return (
        '<aside class="toc-sidebar">'
        '<div class="toc-title">On this page</div>'
        f'<nav class="toc-list">{"".join(rows)}</nav>'
        '</aside>'
    )


def render_sources_block(full_html_text: str) -> str:
    cited = find_cited_sources(full_html_text)
    if not cited:
        return ""
    cards = []
    for anchor, label in cited:
        meta = SOURCE_META.get(anchor, (label, ""))
        ttl, cite = meta
        cards.append(
            '<article class="card no-hover">'
            '<div class="card-icon tint-indigo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div>'
            f'<h3 class="card-title">{html.escape(ttl)}</h3>'
            f'<p class="card-finding">{html.escape(cite)}</p>'
            f'<a class="card-link" href="../sources.html#{anchor}">Open citation</a>'
            '</article>'
        )
    return (
        '<section class="doc-section">'
        '<h2><span class="section-number-badge">§</span><span class="section-title">Sources referenced in this document</span></h2>'
        '<p>Auto-collected from the metric and method mentions in the text above.</p>'
        f'<div class="grid cols-2">{"".join(cards)}</div>'
        '</section>'
    )


# ---------------------------------------------------------------------------
# Output path + main
# ---------------------------------------------------------------------------


def derive_out_name(doc_path: Path, docs_root: Path) -> str:
    try:
        rel = doc_path.relative_to(docs_root).with_suffix("")
    except ValueError:
        rel = Path(doc_path.stem)
    return str(rel).replace("/", "-") + ".html"


def render(doc_path: Path, docs_root: Path, dashboards_dir: Path) -> Path:
    md = doc_path.read_text()
    title, header_block, body_md = parse_doc(md)
    sections = split_sections(body_md)

    full_html_accum: list[str] = []
    section_blocks: list[str] = []
    toc_entries: list[tuple[str, str]] = []

    # Prelude (everything before the first ## ) becomes a non-anchored intro.
    if sections and sections[0][0] == "" and sections[0][1].strip():
        section_blocks.append(render_intro(sections[0][1], full_html_accum))
        sections = sections[1:]
    elif sections and sections[0][0] == "":
        sections = sections[1:]

    for header, body in sections:
        if not header:
            continue
        section_html, label, anchor = render_section(header, body, full_html_accum)
        section_blocks.append(section_html)
        toc_entries.append((label, anchor))

    header_card_html = render_header_card(header_block)
    companion_html = render_companion_card(header_block)
    toc_html = render_toc(toc_entries)
    sources_html = render_sources_block("\n".join(full_html_accum))

    out_name = derive_out_name(doc_path, docs_root)
    out_path = dashboards_dir / "docs" / out_name
    out_path.parent.mkdir(exist_ok=True)

    try:
        rel_parts = doc_path.relative_to(docs_root).parts
        eyebrow = " · ".join(rel_parts[:-1]) or "cupertino docs"
    except ValueError:
        eyebrow = "cupertino docs"
    eyebrow = eyebrow.replace("-", " ").title()

    gh_url = f"https://github.com/mihaelamj/cupertino/blob/main/docs/{doc_path.relative_to(docs_root)}"

    has_mermaid = '<pre class="mermaid">' in "".join(section_blocks)
    mermaid_script = MERMAID_BOOTSTRAP if has_mermaid else ""

    body = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{html.escape(title)} · cupertino docs</title>
    <link rel="stylesheet" href="../_styles.css">
</head>
<body class="doc-page">
    <div class="doc-progress"><div class="doc-progress-bar"></div></div>

    <div class="container doc-container">

        <a class="back-link" href="../search-quality-v1.2.0.html">Back to dashboard</a>

        <header class="doc-header">
            <div class="eyebrow">{html.escape(eyebrow)}</div>
            <h1>{html.escape(title)}</h1>
        </header>

        {header_card_html}

        {companion_html}

        <div class="doc-layout">
            {toc_html}

            <main class="doc-content">
                {"".join(section_blocks)}

                {sources_html}
            </main>
        </div>

        <footer>
            <p>
                Rendered from <a href="{gh_url}" target="_blank" rel="noopener">{html.escape(str(doc_path.relative_to(docs_root)))}</a> by <code>_render-doc.py</code>.
                Re-run after editing the source; nothing here is hardcoded.
            </p>
            <p>
                Methodology in <a href="design-search-quality-eval.html">design/search-quality-eval</a>
                ·
                Architecture in <a href="architecture-database.html">architecture/database</a>
                ·
                Citations in <a href="../sources.html">sources.html</a>
                ·
                Index in <a href="database-handbook.html">database-handbook</a>
            </p>
        </footer>

    </div>

    {mermaid_script}

    <script>
    (function() {{
        // Reading-progress bar
        var bar = document.querySelector('.doc-progress-bar');
        if (bar) {{
            window.addEventListener('scroll', function() {{
                var h = document.documentElement;
                var scrolled = h.scrollTop / Math.max(1, (h.scrollHeight - h.clientHeight));
                bar.style.width = (scrolled * 100).toFixed(2) + '%';
            }}, {{ passive: true }});
        }}

        // TOC active highlight
        var rows = document.querySelectorAll('.toc-row');
        if ('IntersectionObserver' in window && rows.length) {{
            var byHash = {{}};
            rows.forEach(function(r) {{ byHash[r.getAttribute('href')] = r; }});
            var io = new IntersectionObserver(function(entries) {{
                entries.forEach(function(e) {{
                    if (e.isIntersecting) {{
                        rows.forEach(function(r) {{ r.classList.remove('active'); }});
                        var row = byHash['#' + e.target.id];
                        if (row) row.classList.add('active');
                    }}
                }});
            }}, {{ rootMargin: '-25% 0px -65% 0px' }});
            document.querySelectorAll('section.doc-section[id]').forEach(function(s) {{ io.observe(s); }});
        }}
    }})();
    </script>
</body>
</html>
"""
    out_path.write_text(body)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("doc_path", type=Path, help="path to a markdown doc under docs/")
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    dashboards_dir = script_dir
    docs_root = script_dir.parent

    doc_path = args.doc_path.resolve()
    if not doc_path.exists():
        print(f"error: {doc_path} not found", file=sys.stderr)
        return 1

    out = render(doc_path, docs_root, dashboards_dir)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

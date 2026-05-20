#!/usr/bin/env python3
"""
Export a self-contained, single-file version of the index dashboard suitable
for pasting into a blog post (aleahim.com, Substack, Ghost, etc.).

Inlines the shared CSS into a <style> block, rewrites all internal links to
absolute github.com URLs (so the embedded version still reaches the audit
sources, design docs, and per-audit dashboards from inside the blog), and
emits one HTML file that works when pasted into any HTML-supporting blog.

Usage:
    python3 _export-for-blog.py [--out FILE] [--gh-base URL]

Defaults:
    --out      ./search-quality-v1.2.0-blog-embed.html
    --gh-base  https://github.com/mihaelamj/cupertino/blob/main/docs

The output is a fully self-contained HTML page. Drop it into a blog editor's
"Custom HTML" / "Raw HTML" / "HTML block" mode. The dashboard's internal
links (Read full audit, sources page, etc.) point at the cupertino repo on
GitHub so readers can click through.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=None,
                        help="Source HTML to export. Default: search-quality-v1.2.0.html. "
                             "Pass docs/<x>.html (e.g. docs/design-anti-hallucination-eval.html) "
                             "to embed a design doc instead of the index dashboard.")
    parser.add_argument("--out", type=Path, default=None,
                        help="Output path (default: <source-stem>-blog-embed.html next to this script)")
    parser.add_argument("--gh-base", default="https://github.com/mihaelamj/cupertino/blob/main/docs",
                        help="GitHub URL prefix for rewriting relative links")
    parser.add_argument("--gh-pages-base", default=None,
                        help="Optional GitHub Pages URL prefix for sibling dashboards (.html); defaults to --gh-base if omitted")
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    source = (args.source or (script_dir / "search-quality-v1.2.0.html")).resolve()
    if not args.source:
        source = script_dir / "search-quality-v1.2.0.html"
    css = script_dir / "_styles.css"
    out_path = args.out or (script_dir / f"{source.stem}-blog-embed.html")

    if not source.exists():
        print(f"error: {source} not found — run regen-all.sh first", file=sys.stderr)
        return 1
    if not css.exists():
        print(f"error: {css} not found", file=sys.stderr)
        return 1

    html = source.read_text()
    css_content = css.read_text()

    # Detect whether the source page lives one folder deeper (docs/<x>.html).
    # Its relative refs are `../_styles.css`, `../search-quality-v1.2.0.html`,
    # `../sources.html`, sibling docs `<sibling>.html`, etc.
    is_doc_page = source.parent.name == "docs" and source.parent.parent == script_dir

    # 1. Inline the stylesheet (path differs between index dashboard and doc pages)
    if is_doc_page:
        html = re.sub(
            r'<link rel="stylesheet" href="\.\./_styles\.css">',
            f'<style>\n{css_content}\n</style>',
            html,
            count=1,
        )
    else:
        html = re.sub(
            r'<link rel="stylesheet" href="_styles\.css">',
            f'<style>\n{css_content}\n</style>',
            html,
            count=1,
        )

    pages_base = args.gh_pages_base or args.gh_base

    # 2. Rewrite relative links so the embedded page still reaches the
    #    cupertino repo on GitHub.
    rewrites = [
        # Index-dashboard-relative
        (r'href="audits/([^"]+)"', f'href="{pages_base}/dashboards/audits/\\1"'),
        (r'href="sources\.html(#[^"]*)?"', f'href="{pages_base}/dashboards/sources.html\\1"'),
        (r'href="docs/([^"]+)"', f'href="{pages_base}/dashboards/docs/\\1"'),
        # Doc-page-relative (one level deeper)
        (r'href="\.\./audits/([^"]+\.html)"', f'href="{pages_base}/dashboards/audits/\\1"'),
        (r'href="\.\./sources\.html(#[^"]*)?"', f'href="{pages_base}/dashboards/sources.html\\1"'),
        (r'href="\.\./search-quality-v1\.2\.0\.html"', f'href="{pages_base}/dashboards/search-quality-v1.2.0.html"'),
        # Markdown sources on the repo
        (r'href="\.\./audits/([^"]+\.md)"', f'href="{args.gh_base}/audits/\\1"'),
        (r'href="\.\./audits/"', f'href="{args.gh_base}/audits/"'),
        (r'href="\.\./design/([^"]+)"', f'href="{args.gh_base}/design/\\1"'),
        (r'href="\.\./architecture/([^"]+)"', f'href="{args.gh_base}/architecture/\\1"'),
        (r'href="\.\./database-handbook\.md"', f'href="{args.gh_base}/database-handbook.md"'),
        # Sibling doc pages from inside docs/ folder
        # (only rewrite when the source IS a doc page; otherwise leave alone)
    ]
    if is_doc_page:
        rewrites.append((
            r'href="(design-[a-z0-9-]+|architecture-[a-z0-9-]+|database-handbook|PRINCIPLES|ARCHITECTURE)\.html"',
            f'href="{pages_base}/dashboards/docs/\\1.html"',
        ))
    for pat, repl in rewrites:
        html = re.sub(pat, repl, html)

    # 3. Add a small notice at the bottom so the reader knows this is a snapshot
    notice = (
        '<div style="max-width:1180px;margin:24px auto 60px;padding:0 24px;font-size:13px;'
        'color:var(--text-tertiary);text-align:center;line-height:1.6;">'
        'Embedded snapshot — for the live, always-current version see '
        f'<a href="{pages_base}/dashboards/{source.relative_to(script_dir)}">cupertino on GitHub</a>. '
        'Re-export this page when the source updates.'
        '</div>'
    )
    html = html.replace("</body>", notice + "\n</body>")

    # 4. All external links should open in a new tab from a blog context
    html = re.sub(
        r'<a href="(https?://[^"]+)"(?![^>]*target=)',
        r'<a href="\1" target="_blank" rel="noopener"',
        html,
    )

    out_path.write_text(html)
    has_mermaid = '<pre class="mermaid">' in html
    print(f"wrote {out_path}  ({len(html)} bytes)")
    print()
    print("Paste this file's contents into the blog's HTML / 'Custom HTML' block.")
    print(f"External links pointing at the cupertino repo use base: {args.gh_base}")
    if has_mermaid:
        print()
        print("Note: this page contains Mermaid diagrams. The embed includes a")
        print("<script type=\"module\"> tag that loads mermaid from CDN. If the blog")
        print("platform strips script tags from user HTML, the diagrams won't render.")
        print("On aleahim.com (and most personally-controlled blogs) script tags in")
        print("'Custom HTML' blocks are preserved — verify in preview before publishing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

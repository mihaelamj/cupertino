#!/usr/bin/env python3
"""
Shared audit-markdown parser used by both `_render-audit-dashboard.py` and
`_render-index-dashboard.py`. No external dependencies.

The audit markdown is the single source of truth; this module turns it into
a structured object the renderers consume. When the audit content changes,
the renderers re-emit HTML without code edits.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# ============================================================================
# Audit data model
# ============================================================================

@dataclass
class Audit:
    """Parsed audit markdown."""
    title: str = ""
    header_block: dict[str, str] = field(default_factory=dict)
    intro_md: str = ""
    sections: dict[str, str] = field(default_factory=dict)
    sections_order: list[str] = field(default_factory=list)
    source_path: Optional[Path] = None

    @property
    def date(self) -> str:
        return self.header_block.get("Date", "")

    @property
    def first_intro_paragraph(self) -> str:
        if not self.intro_md:
            return ""
        return self.intro_md.split("\n\n")[0].strip()


@dataclass
class Headline:
    """The extracted dashboard-ready summary of an audit."""
    value: str          # "92%", "30 / 30", "0.9467", "—"
    color: str          # "green" | "orange" | "red" | "blue"
    status: str         # "Strong" | "Mixed" | "Weak" | "Info"
    raw_percent: Optional[float]  # for sorting / aggregation; None if unknown


# ============================================================================
# Markdown parsing
# ============================================================================

def parse_audit(audit_path: Path) -> Audit:
    """Split an audit markdown file into title + header block + sections."""
    a = Audit(source_path=audit_path)
    md = audit_path.read_text()
    lines = md.splitlines()
    i = 0

    while i < len(lines) and not lines[i].startswith("# "):
        i += 1
    if i < len(lines):
        a.title = lines[i][2:].strip()
        i += 1

    while i < len(lines) and not lines[i].strip():
        i += 1
    while i < len(lines):
        line = lines[i]
        m = re.match(r"\*\*([^*]+):\*\*\s*(.*)$", line)
        if m:
            a.header_block[m.group(1).strip()] = m.group(2).strip()
            i += 1
        elif not line.strip():
            i += 1
        else:
            break

    intro_lines = []
    while i < len(lines) and not lines[i].startswith("## ") and lines[i].strip() != "---":
        intro_lines.append(lines[i])
        i += 1
    a.intro_md = "\n".join(intro_lines).strip()

    current_section = None
    current_body: list[str] = []
    while i < len(lines):
        line = lines[i]
        if line.startswith("## "):
            if current_section is not None:
                a.sections[current_section.lower()] = "\n".join(current_body).strip()
                a.sections_order.append(current_section.lower())
            current_section = line[3:].strip()
            current_body = []
        elif current_section is not None:
            current_body.append(line)
        i += 1
    if current_section is not None:
        a.sections[current_section.lower()] = "\n".join(current_body).strip()
        a.sections_order.append(current_section.lower())

    return a


# ============================================================================
# Headline extraction
# ============================================================================

def extract_headline(a: Audit) -> Headline:
    """Find the headline metric from the Aggregate (or named-equivalent) section.

    Heuristics in priority order:
      1. Explicit `**Status:**` and `**Headline:**` in audit header block.
      2. First **bold** number in the Aggregate section.
      3. First numeric value in the Aggregate section's table.
      4. Unknown → status=Info, color=blue.

    Status thresholds (when not explicit):
      - >= 80%  → Strong / green
      - 40-79%  → Mixed / orange
      - <  40%  → Weak / red
    """
    if "Status" in a.header_block and a.header_block["Status"] in ("Strong", "Mixed", "Weak"):
        st = a.header_block["Status"]
        color = {"Strong": "green", "Mixed": "orange", "Weak": "red"}[st]
        v = a.header_block.get("Headline", "—")
        pct = _to_percent(v)
        return Headline(value=v, color=color, status=st, raw_percent=pct)

    # Walk all sections looking for an Aggregate-shaped one
    agg_keys = ("aggregate", "results", "result", "summary")
    body = ""
    for k in agg_keys:
        if k in a.sections:
            body = a.sections[k]
            break
    if not body and a.sections_order:
        body = a.sections[a.sections_order[0]]

    value, pct = _scan_for_metric(body)

    if pct is None:
        return Headline(value=value, color="blue", status="Info", raw_percent=None)

    if pct >= 80:
        return Headline(value=value, color="green", status="Strong", raw_percent=pct)
    if pct >= 40:
        return Headline(value=value, color="orange", status="Mixed", raw_percent=pct)
    return Headline(value=value, color="red", status="Weak", raw_percent=pct)


_METRIC_PATTERNS = [
    re.compile(r"\*\*([\d.]+\s*/\s*\d+)\s*\(([\d.]+%)\)\*\*"),       # **46/50 (92%)**
    re.compile(r"\*\*([\d.]+%)\*\*"),                                # **92%**
    re.compile(r"\*\*(\d+\s*/\s*\d+)\*\*"),                           # **30/30**
    re.compile(r"\|\s*\*?\*?(\d+%)\*?\*?\s*\|"),                      # | 92% |
    re.compile(r"\|\s*\*?\*?MRR\s+(0\.[\d]+)\*?\*?\s*\|", re.IGNORECASE),  # | MRR 0.9467 |
    re.compile(r"MRR[:\s=]+(0\.[\d]+)", re.IGNORECASE),               # MRR: 0.9467
    re.compile(r"\|\s*\*?\*?(0\.[\d]+)\*?\*?\s*\|"),                  # | 0.9467 |
]


def _scan_for_metric(text: str) -> tuple[str, Optional[float]]:
    for pat in _METRIC_PATTERNS:
        m = pat.search(text)
        if not m:
            continue
        groups = m.groups()
        if len(groups) == 2:
            value = f"{groups[0]} ({groups[1]})"
            pct = _to_percent(groups[1])
            return value, pct
        value = groups[0]
        pct = _to_percent(value)
        if pct is None and "/" in value:
            try:
                num, den = value.replace(" ", "").split("/")
                pct = (int(num) / int(den)) * 100
            except (ValueError, ZeroDivisionError):
                pass
        return value, pct
    return "—", None


def _to_percent(s: str) -> Optional[float]:
    s = s.strip().strip("*")
    m = re.match(r"^([\d.]+)%$", s)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            return None
    try:
        f = float(s)
        if 0 <= f <= 1:
            return f * 100
        return f
    except ValueError:
        return None


# ============================================================================
# Minimal Markdown → HTML
# ============================================================================

INLINE_PATTERNS = [
    (re.compile(r"\*\*([^*\n]+)\*\*"),  lambda m: f"<strong>{m.group(1)}</strong>"),
    (re.compile(r"(?<![*])\*([^*\n]+)\*(?![*])"), lambda m: f"<em>{m.group(1)}</em>"),
    (re.compile(r"\[([^\]]+)\]\(([^)]+)\)"),
     lambda m: f'<a href="{html.escape(m.group(2), quote=True)}">{m.group(1)}</a>'),
]


def render_inline(text: str) -> str:
    placeholders: list[str] = []
    def stash(m):
        placeholders.append(m.group(0))
        return f"\x00INLINE{len(placeholders)-1}\x00"
    text = re.sub(r"`[^`\n]+`", stash, text)
    text = html.escape(text, quote=False)
    for i, original in enumerate(placeholders):
        content = original[1:-1]  # strip backticks
        text = text.replace(f"\x00INLINE{i}\x00", f"<code>{html.escape(content)}</code>")
    for pat, repl in INLINE_PATTERNS:
        text = pat.sub(repl, text)
    return text


def md_to_html(md: str) -> str:
    lines = md.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("#### "):
            out.append(f"<h4>{render_inline(line[5:])}</h4>")
            i += 1; continue
        if line.startswith("### "):
            out.append(f"<h4>{render_inline(line[4:])}</h4>")
            i += 1; continue
        if line.startswith("## "):
            out.append(f"<h3>{render_inline(line[3:])}</h3>")
            i += 1; continue
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:-]+\|", lines[i + 1]):
            t, n = _parse_table(lines, i)
            out.append(t); i += n; continue
        if re.match(r"^\s*[-*]\s+", line):
            t, n = _parse_list(lines, i, ordered=False)
            out.append(t); i += n; continue
        if re.match(r"^\s*\d+\.\s+", line):
            t, n = _parse_list(lines, i, ordered=True)
            out.append(t); i += n; continue
        if line.startswith("```"):
            t, n = _parse_code_fence(lines, i)
            out.append(t); i += n; continue
        para = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and not _is_block_start(lines[i], lines, i):
            para.append(lines[i]); i += 1
        out.append(f"<p>{render_inline(' '.join(l.strip() for l in para))}</p>")
    return "\n".join(out)


def _is_block_start(line: str, all_lines: list[str], idx: int) -> bool:
    if line.startswith("#"):
        return True
    if line.startswith("|") and idx + 1 < len(all_lines) and re.match(r"^\|[\s:-]+\|", all_lines[idx + 1]):
        return True
    if re.match(r"^\s*[-*]\s+", line) or re.match(r"^\s*\d+\.\s+", line):
        return True
    if line.startswith("```"):
        return True
    return False


def _parse_table(lines: list[str], start: int) -> tuple[str, int]:
    header_cells = [c.strip() for c in lines[start].strip("|").split("|")]
    rows: list[list[str]] = []
    i = start + 2
    while i < len(lines) and lines[i].startswith("|"):
        rows.append([c.strip() for c in lines[i].strip("|").split("|")])
        i += 1
    thead = "<thead><tr>" + "".join(f"<th>{render_inline(c)}</th>" for c in header_cells) + "</tr></thead>"
    body_rows = []
    for row in rows:
        while len(row) < len(header_cells):
            row.append("")
        cells = []
        for c in row:
            cls = ' class="num"' if re.match(r"^-?[\d.,]+%?$|^[-—]$", c) else ""
            cells.append(f"<td{cls}>{render_inline(c)}</td>")
        body_rows.append("<tr>" + "".join(cells) + "</tr>")
    return (f'<table class="data-table">{thead}<tbody>{"".join(body_rows)}</tbody></table>', i - start)


def _parse_list(lines: list[str], start: int, ordered: bool) -> tuple[str, int]:
    tag = "ol" if ordered else "ul"
    pat = re.compile(r"^\s*\d+\.\s+(.*)$" if ordered else r"^\s*[-*]\s+(.*)$")
    items: list[str] = []
    i = start
    while i < len(lines):
        m = pat.match(lines[i])
        if not m:
            break
        items.append(render_inline(m.group(1)))
        i += 1
    return (f"<{tag}>" + "".join(f"<li>{it}</li>" for it in items) + f"</{tag}>", i - start)


def _parse_code_fence(lines: list[str], start: int) -> tuple[str, int]:
    body: list[str] = []
    i = start + 1
    while i < len(lines) and not lines[i].startswith("```"):
        body.append(lines[i]); i += 1
    return (f"<pre><code>{html.escape(chr(10).join(body))}</code></pre>", i - start + 1)


# ============================================================================
# Path conventions
# ============================================================================

# ============================================================================
# Source citation linkification
# ============================================================================
# Wrap every known metric / method mention with a link to the corresponding
# anchor on sources.html. Run after the audit MD has been converted to HTML.
# Order matters: most-specific first (so "Mean Reciprocal Rank" wins over MRR).

METRIC_LINKS = [
    # (regex, anchor)
    (r"\bMean Reciprocal Rank\b",       "mrr"),
    (r"\bMRR\b",                         "mrr"),
    (r"\bNormalized Discounted Cumulative Gain\b", "ndcg"),
    (r"\bNDCG(@\d+)?\b",                "ndcg"),
    (r"\bMean Average Precision\b",     "map"),
    (r"\bMAP\b",                         "map"),
    (r"\bR-Precision\b",                 "r-precision"),
    (r"\bP@\d+\b",                       "precision-at-k"),
    (r"\bPrecision at \d+\b",            "precision-at-k"),
    (r"\bBM25F\b",                       "bm25f"),
    (r"\bBM25\b",                        "bm25"),
    (r"\bReciprocal Rank Fusion\b",      "rrf"),
    (r"\bRRF\b",                         "rrf"),
    (r"\bWilcoxon signed-rank test\b",   "wilcoxon"),
    (r"\bWilcoxon\b",                    "wilcoxon"),
    (r"\bMcNemar(?:'s)?(?: test)?\b",    "mcnemar"),
    (r"\bsign test\b",                   "sign-test"),
    (r"\bbinomial test\b",               "sign-test"),
    (r"\bCohen'?s kappa\b",              "cohens-kappa"),
    (r"\bCranfield(?: paradigm)?\b",     "cranfield"),
    (r"\bTREC pooling\b",                "trec-pooling"),
    (r"\bFTS5\b",                        "fts5"),
    (r"\bPorter stemmer\b",              "porter"),
    (r"\bswift-syntax\b",                "swift-syntax"),
    (r"\bsymbolgraph-extract\b",         "symbolgraph"),
]

_LINKED_TOKEN_RE = re.compile(r"(?:" + "|".join(p for p, _ in METRIC_LINKS) + r")")


def linkify_metrics(html_text: str, sources_url: str = "../sources.html") -> str:
    """Wrap each known metric / method mention with an <a> linking to its
    citation. Skips anything already inside an <a>, <code>, or attribute value.
    Tracks per-doc usage so the audit dashboard can list 'sources cited here'.
    """
    # Tokenise html into chunks; skip <a> and <code> bodies and tags.
    out = []
    i = 0
    skip_until = None
    n = len(html_text)
    while i < n:
        if skip_until and html_text[i:i+len(skip_until)] == skip_until:
            out.append(skip_until)
            i += len(skip_until)
            skip_until = None
            continue
        if skip_until:
            out.append(html_text[i])
            i += 1
            continue
        # Detect <a ... > or <code ... > and skip to closing tag
        if html_text[i] == "<":
            close = html_text.find(">", i)
            if close == -1:
                out.append(html_text[i])
                i += 1
                continue
            tag = html_text[i:close+1]
            out.append(tag)
            tag_name = tag[1:].split()[0].rstrip(">").lower()
            if tag_name in ("a", "code", "pre") and not tag.startswith("</") and not tag.endswith("/>"):
                skip_until = f"</{tag_name}>"
            i = close + 1
            continue
        # Regular text region: find next < to bound it
        nxt = html_text.find("<", i)
        if nxt == -1:
            nxt = n
        region = html_text[i:nxt]
        # Linkify metrics in this region
        def repl(m):
            tok = m.group(0)
            # Find which pattern matched, in order
            for pat, anchor in METRIC_LINKS:
                if re.fullmatch(pat, tok):
                    return f'<a href="{sources_url}#{anchor}">{tok}</a>'
            return tok
        out.append(_LINKED_TOKEN_RE.sub(repl, region))
        i = nxt
    return "".join(out)


def first_metric_link(html_text: str) -> Optional[tuple[str, str]]:
    """Return (label, anchor) of the first metric source link in the HTML, or
    None if no metric was linkified. Used to label the headline KPI with the
    method that produced it."""
    m = re.search(r'<a href="[^"]*#([a-z-]+)">([^<]+)</a>', html_text)
    if not m:
        return None
    return (m.group(2), m.group(1))


def find_cited_sources(html_text: str) -> list[tuple[str, str]]:
    """Walk the linkified HTML and return ordered unique (label, anchor) pairs
    of every source mentioned. Used to render a 'Sources cited' section per
    dashboard."""
    seen: dict[str, str] = {}  # anchor -> first-seen label
    for m in re.finditer(r'<a href="[^"]*#([a-z-]+)">([^<]+)</a>', html_text):
        anchor, label = m.group(1), m.group(2)
        if anchor not in seen:
            seen[anchor] = label
    return list(seen.items())


# Source metadata for the per-audit "Sources cited" cards. Hand-curated since
# this is the only place these labels need to stay short + consistent.
SOURCE_META = {
    "mrr": ("Mean Reciprocal Rank", "Voorhees (1999), TREC-8 QA Report"),
    "ndcg": ("NDCG", "Järvelin & Kekäläinen (2002)"),
    "map": ("Mean Average Precision", "Manning, Raghavan, Schütze (2008) IIR §8.4"),
    "r-precision": ("R-Precision", "Manning, Raghavan, Schütze (2008) IIR §8.4"),
    "precision-at-k": ("P@k (Precision at k)", "Manning, Raghavan, Schütze (2008) IIR §8.4"),
    "bm25": ("BM25", "Robertson & Walker (1994), SIGIR"),
    "bm25f": ("BM25F (field-weighted)", "Robertson, Zaragoza, Taylor (2004), CIKM"),
    "rrf": ("Reciprocal Rank Fusion (k=60)", "Cormack, Clarke, Büttcher (2009), SIGIR"),
    "wilcoxon": ("Wilcoxon signed-rank test", "Wilcoxon (1945), Biometrics Bulletin"),
    "mcnemar": ("McNemar's test", "McNemar (1947), Psychometrika"),
    "sign-test": ("Sign / binomial test", "Conover (1999), Practical Nonparametric Statistics"),
    "cohens-kappa": ("Cohen's kappa", "Cohen (1960)"),
    "cranfield": ("Cranfield paradigm", "Cleverdon (1967), Aslib Proceedings"),
    "trec-pooling": ("TREC pooling", "Sparck Jones & van Rijsbergen (1975); TREC/NIST since 1992"),
    "fts5": ("SQLite FTS5", "SQLite documentation"),
    "porter": ("Porter stemmer", "Porter (1980)"),
    "swift-syntax": ("swift-syntax", "Apple swift-syntax library"),
    "symbolgraph": ("swift symbolgraph-extract", "Apple Swift toolchain"),
}


def derive_dashboard_name(audit_path: Path) -> str:
    """search-quality-acronym-baseline-v1.2.0.md → acronym-v1.2.0.html"""
    name = audit_path.stem
    if name.startswith("search-quality-"):
        name = name[len("search-quality-"):]
    name = name.replace("-baseline", "")
    return f"{name}.html"


def discover_audits(audits_dir: Path) -> list[Path]:
    """Find all search-quality audit markdown files under the given dir."""
    return sorted(audits_dir.glob("search-quality-*-v*.md"))


def title_case(s: str) -> str:
    small = {"a", "an", "the", "of", "in", "on", "to", "for", "and", "or", "but"}
    return " ".join(
        w.lower() if (i > 0 and w.lower() in small) else (w[:1].upper() + w[1:])
        for i, w in enumerate(s.split())
    )

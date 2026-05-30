#!/usr/bin/env python3
"""Generate an HTML "read battery" report from the real cupertino CLI.

For every content source it runs ~10 search queries and reads >= 20 documents,
all through the production read-only query path (#1194), and emits a single
self-contained HTML file with one collapsible <details> per query and per
document showing the actual returned text. Use it to eyeball, exhaustively,
that search + read work across every database.

Coverage (no shortcuts -- all 8 databases):
  docs:     apple-docs, hig, apple-archive, swift-evolution, swift-org, swift-book
  samples:  apple-sample-code   packages: packages
  AST:      search-symbols, search-generics

Configuration (all optional, sensible defaults):
  CUPERTINO_BIN     path to the cupertino binary
                    (default: <repo>/Packages/.build/debug/cupertino)
  CUPERTINO_DB_DIR  directory holding the per-source .db files
                    (default: /Volumes/Code/DeveloperExt/private/cupertino-dbs-2026-05-28)
  CUPERTINO_REPORT  output HTML path (default: /tmp/cupertino-read-battery-report.html)

The binary is pinned to CUPERTINO_DB_DIR via a cupertino.config.json written
next to it, so it never touches the brew install (~/.cupertino). Run:

  python3 scripts/read-battery-report.py && open /tmp/cupertino-read-battery-report.html

Notes / known quirks:
  - `--source hig` emits a {count,query,results:[...]} object; every other docs
    source emits a bare array. This script normalizes both.
"""
import html, json, os, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BIN = os.environ.get("CUPERTINO_BIN") or str(REPO / "Packages/.build/debug/cupertino")
DB_DIR = os.environ.get("CUPERTINO_DB_DIR") or "/Volumes/Code/DeveloperExt/private/cupertino-dbs-2026-05-28"
OUT = os.environ.get("CUPERTINO_REPORT") or "/tmp/cupertino-read-battery-report.html"

DOCS = [
    ("apple-docs", ["view", "data", "string", "async", "protocol", "url", "image", "animation", "error", "color"]),
    ("hig", ["color", "layout", "typography", "navigation", "button", "accessibility", "gesture", "icon", "menu", "sidebar"]),
    ("apple-archive", ["view", "controller", "data", "table", "image", "animation", "thread", "memory", "drawing", "layer"]),
    ("swift-evolution", ["concurrency", "actor", "async", "macro", "protocol", "result", "generics", "ownership", "sendable", "string"]),
    ("swift-org", ["concurrency", "package", "compiler", "macro", "string", "protocol", "testing", "build", "module", "toolchain"]),
    ("swift-book", ["closure", "optional", "protocol", "generic", "enumeration", "structure", "class", "function", "property", "initializer"]),
]
SAMPLE_QUERIES = ["view", "swiftui", "animation", "data", "network", "audio", "camera", "widget", "metal", "map"]
PACKAGE_QUERIES = ["logger", "actor", "async", "client", "server", "json", "http", "test", "macro", "collection"]


def pin_config():
    cfg = Path(BIN).parent / "cupertino.config.json"
    cfg.write_text(json.dumps({"baseDirectory": DB_DIR}) + "\n")


def raw(args):
    try:
        return subprocess.run([BIN] + args, capture_output=True, text=True, timeout=180).stdout
    except Exception as exc:
        return f"<error: {exc}>"


def jsonv(args):
    out = raw(args + ["--format", "json"])
    i = next((k for k, c in enumerate(out) if c in "[{"), None)
    if i is None:
        return None
    try:
        return json.loads(out[i:])
    except Exception:
        return None


def strip_log(text):
    lines = []
    for ln in text.splitlines():
        if not lines and len(ln) >= 4 and ln[:4].isdigit():
            continue
        lines.append(ln)
    return "\n".join(lines).strip()


def det(summary, body, badge=""):
    return f'<details><summary>{badge}{html.escape(summary)}</summary><pre>{html.escape(body)}</pre></details>'


def fmt_docs(rows):
    out = []
    for i, r in enumerate(rows, 1):
        score = r.get("rank") or r.get("score")
        out.append(f"[{i}] {r.get('title', '')}")
        out.append(f"    uri:   {r.get('uri', '')}")
        if r.get("framework"):
            out.append(f"    fwk:   {r.get('framework')}")
        if isinstance(score, (int, float)):
            out.append(f"    score: {score:.4f}")
        if r.get("summary"):
            out.append(f"    {r.get('summary')}")
        out.append("")
    return "\n".join(out) or "(no results)"


P = [f"""<!doctype html><html><head><meta charset="utf-8"><title>cupertino read battery</title>
<style>body{{font:14px -apple-system,Helvetica,Arial,sans-serif;max-width:1000px;margin:2rem auto;padding:0 1rem;color:#222}}
h1{{border-bottom:2px solid #0a84ff}}h2{{margin-top:2rem;color:#0a84ff;border-bottom:1px solid #ddd}}h3{{color:#555}}
details{{border:1px solid #e0e0e0;border-radius:6px;margin:.35rem 0;padding:.3rem .6rem;background:#fafafa}}
summary{{cursor:pointer;font-weight:600}}summary:hover{{color:#0a84ff}}
pre{{white-space:pre-wrap;word-break:break-word;background:#fff;border:1px solid #eee;padding:.6rem;border-radius:4px;max-height:460px;overflow:auto;font:12px ui-monospace,Menlo,monospace}}
.ok{{color:#1a7f37;font-weight:700;margin-right:.4rem}}.fail{{color:#cf222e;font-weight:700;margin-right:.4rem}}.meta{{color:#888}}
table{{border-collapse:collapse}}td,th{{border:1px solid #ddd;padding:.2rem .5rem}}</style></head><body>
<h1>cupertino read battery</h1>
<p>Every query and document below was produced by the real <code>cupertino</code> CLI
(<code>{html.escape(BIN)}</code>) against <code>{html.escape(DB_DIR)}</code>, through the
read-only query path (#1194). Expand any row to see the returned text.</p>"""]


def search_section(source, queries, kind):
    P.append(f"<h2>search --source {html.escape(source)}</h2>")
    items = []
    for q in queries:
        res = jsonv(["search", q, "--source", source, "--limit", "5"])
        if kind == "docs":
            rows = res.get("results", []) if isinstance(res, dict) else (res or [])
            rows = [r for r in rows if isinstance(r, dict)]
            for r in rows:
                if r.get("uri"):
                    items.append((r["uri"], r.get("title", "")))
            P.append(det(f'"{q}"  ->  {len(rows)} results', fmt_docs(rows), f'<span class="meta">[{len(rows)}]</span> '))
        elif kind == "samples":
            files = (res or {}).get("files", []) if isinstance(res, dict) else []
            for f in files:
                items.append((f.get("projectId", ""), f.get("path", "")))
            body = "\n".join(f"[{i + 1}] {f.get('projectId', '')} / {f.get('path', '')}" for i, f in enumerate(files)) or "(no results)"
            P.append(det(f'"{q}"  ->  {len(files)} files', body, f'<span class="meta">[{len(files)}]</span> '))
        else:
            cands = (res or {}).get("candidates", []) if isinstance(res, dict) else []
            for c in cands:
                if c.get("identifier"):
                    items.append(c["identifier"])
            body = "\n".join(f"[{i + 1}] {c.get('identifier', '')}" for i, c in enumerate(cands)) or "(no results)"
            P.append(det(f'"{q}"  ->  {len(cands)} candidates', body, f'<span class="meta">[{len(cands)}]</span> '))
    return items


def read_section(items, source, kind):
    seen = set()
    picked = []
    for it in items:
        key = it
        if key not in seen:
            seen.add(key)
            picked.append(it)
        if len(picked) >= 20:
            break
    ok = 0
    blocks = []
    for it in picked[:20]:
        if kind == "docs":
            uri, title = it
            body = strip_log(raw(["read", uri, "--source", source, "--format", "markdown"]))
            label = f"{uri}  --  {title}"
        elif kind == "samples":
            proj, path = it
            body = strip_log(raw(["read-sample-file", proj, path]))
            label = f"{proj} / {path}"
        else:
            body = strip_log(raw(["read", it, "--source", "packages"]))
            label = it
        good = len(body) > 40 and "not found" not in body.lower()
        ok += 1 if good else 0
        badge = '<span class="ok">OK</span>' if good else '<span class="fail">FAIL</span>'
        blocks.append(det(label, body or "(no output)", badge))
    P.append(f"<h3>reads from {html.escape(source)}: {ok}/{len(picked[:20])} documents (read-only)</h3>")
    P.extend(blocks)


def main():
    pin_config()
    for source, queries in DOCS:
        print(f"docs {source}", file=sys.stderr, flush=True)
        read_section(search_section(source, queries, "docs"), source, "docs")
    print("samples", file=sys.stderr, flush=True)
    read_section(search_section("samples", SAMPLE_QUERIES, "samples"), "samples", "samples")
    print("packages", file=sys.stderr, flush=True)
    read_section(search_section("packages", PACKAGE_QUERIES, "packages"), "packages", "packages")

    print("ast", file=sys.stderr, flush=True)
    P.append("<h2>AST search commands (apple-docs)</h2><table><tr><th>command</th><th>arg</th><th>#results</th></tr>")
    for arg in ["View", "Data", "String", "Color", "URLSession", "Task", "Array", "Codable", "Error", "Image"]:
        r = jsonv(["search-symbols", "--query", arg, "--limit", "5"]) or {}
        P.append(f"<tr><td>search-symbols</td><td>{arg}</td><td>{len(r.get('results', []))}</td></tr>")
    for arg in ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Collection", "Sequence", "Identifiable", "Error", "View"]:
        r = jsonv(["search-generics", "--constraint", arg, "--limit", "5"]) or {}
        P.append(f"<tr><td>search-generics</td><td>{arg}</td><td>{len(r.get('results', []))}</td></tr>")
    P.append("</table></body></html>")

    Path(OUT).write_text("\n".join(P))
    print(f"wrote {OUT}", file=sys.stderr, flush=True)
    print(OUT)


if __name__ == "__main__":
    main()

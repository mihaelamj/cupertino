# Cupertino dashboards

Apple-style HTML dashboards for cupertino's search-quality evaluations.

## What's here

| File | Purpose |
|---|---|
| `search-quality-v1.2.0.html` | **Index dashboard.** Headline KPIs + the seven per-class tests with status / plain-English claims. Starting point for any reader. |
| `audits/<class>-v1.2.0.html` | **Per-audit detail dashboards.** One per measurement. Headline metric, methodology, full per-query data, future directions. Linked from the index dashboard cards. |
| `_styles.css` | **Shared styling.** Apple design tokens (SF Pro fallback, system colors, light/dark mode). Linked from every dashboard. |
| `_audit-dashboard-template.html` | **Template for new audit dashboards.** Copy and fill in. See instructions below. |
| `_render-audit-dashboard.py` | **Generator script.** Given an audit's JSON dump and metadata, emits a populated dashboard HTML. |

## Audience

- **Index dashboard**: anyone, including non-engineers
- **Per-audit dashboards**: anyone who clicks through; written for non-IR-specialists with technical detail one section in
- **The audit markdown source** (under `../audits/`): engineers / maintainers; full statistical detail

## Generating a new audit dashboard

When a new search-quality audit lands at `../audits/<class>-baseline-v<version>.md`:

1. Run the audit's harness to produce a JSON dump (e.g., `/tmp/cupertino-search-eval-<class>-<TS>.json`).
2. Author a small `audits/<class>-v<version>.meta.json` file with the audit-specific framing (headline, status, plain-English question, etc.). Schema documented in `_audit-dashboard-template.html` comment header.
3. Run `python3 _render-audit-dashboard.py audits/<class>-v<version>.meta.json` to produce `audits/<class>-v<version>.html`.
4. Add a link from the index dashboard's card grid in the same PR.
5. Per the handbook's §7 rot rule, add a link to this new dashboard from `../database-handbook.md` §5 in the same PR.

## Why this exists

The audit markdown files under `../audits/` are dense and full of statistical detail. They are the source of truth and remain so. The dashboards translate the same information for readers who want to see the result without reading 200 lines of methodology.

## Design tokens

- Font: SF Pro (Apple system font), fallback stack `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Arial, sans-serif`
- Colors: Apple system palette — `#007AFF` blue, `#34C759` green, `#FF9500` orange, `#FF3B30` red, `#AF52DE` purple
- Light + dark mode via `prefers-color-scheme`
- No JavaScript framework. Vanilla HTML + CSS only, plus tiny inline JS where needed for tabs
- No external assets (no CDN fonts, no remote images). Self-contained; works offline; renders the same on GitHub Pages, file:// URLs, and over HTTP

## Conventions

- Status pills: `Strong` (green), `Mixed` (orange), `Weak` (red), `Coming next` / `Info` (blue)
- Per-class colour stays consistent across the index dashboard and the per-audit dashboard for that class
- Big metric on each dashboard uses the status colour; smaller metrics use the neutral primary text colour

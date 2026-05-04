# --discovery-mode

How the crawler discovers new URLs

## Synopsis

```bash
cupertino fetch --type docs --discovery-mode <auto|json-only|webview-only>
```

## Description

Controls the per-URL fetch strategy. Apple's docs serve both a JSON API and a WKWebView-renderable HTML page; this flag picks which to use.

## Values

| Value | Behaviour |
|---|---|
| `auto` | (default) JSON API primary, WKWebView fallback when JSON 404s |
| `json-only` | JSON only; skip the fallback. Fastest, narrowest discovery |
| `webview-only` | WKWebView for everything. Slowest, broadest discovery, matches pre-2025-11-30 behaviour |

## Default

`auto`

## Example

```bash
cupertino fetch --type docs --discovery-mode json-only
cupertino fetch --type docs --discovery-mode webview-only
```

## Notes

- `auto` is what produced cupertino's two-pass coverage advantage. Every URL gets a chance at both transports.
- `json-only` is useful for fast incremental crawls where you're confident every page has a JSON endpoint.
- `webview-only` is the bypass for situations where Apple's JSON API behaves oddly.

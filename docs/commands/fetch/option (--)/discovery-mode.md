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
| `auto` | (default) JSON API primary, with two augmentation paths: WKWebView fallback when JSON 404s, plus HTML link augmentation on sparse-references pages (v1.0.2+, [#203](https://github.com/mihaelamj/cupertino/issues/203)) |
| `json-only` | JSON only; skip both augmentation paths. Fastest, narrowest discovery |
| `webview-only` | WKWebView for everything. Slowest, broadest discovery, matches pre-2025-11-30 behaviour |

## Default

`auto`

## Example

```bash
cupertino fetch --type docs --discovery-mode json-only
cupertino fetch --type docs --discovery-mode webview-only
```

## Notes

- `auto` is the recommended default. It runs the JSON API first (fast), falls back to WKWebView when JSON returns 404, AND in v1.0.2+ also unions HTML `<a href>` links into the discovery queue when the page's JSON references count is below `htmlLinkAugmentationMaxRefs` (default 10). The heuristic catches URL patterns DocC JSON omits (operator overloads, legacy numeric-IDs, REST sub-paths) without paying the WebView render cost on every page.
- `json-only` is useful for fast incremental crawls where you're confident every page has a JSON endpoint AND you don't need the augmentation. No WebView is ever used; pages without a JSON endpoint are silently skipped.
- `webview-only` is the bypass for situations where Apple's JSON API behaves oddly. Slow, but renders every page through WKWebView so it sees the same DOM a human browser would.

## Configuration-file fields (v1.0.2+)

The HTML link augmentation in `auto` mode is controlled by two `CrawlerConfiguration` fields. There are no CLI flags for these yet; set them in your config JSON if you need to tune them.

| field | type | default | meaning |
|---|---|---|---|
| `htmlLinkAugmentation` | `Bool` | `true` | master switch; `false` disables augmentation entirely |
| `htmlLinkAugmentationMaxRefs` | `Int` | `10` | augmentation runs only when JSON link count `<` this; set `Int.max` to augment every page |

When augmentation runs and adds at least one link, the crawler logs `🔗 HTML augmentation: +N links (page had M JSON refs)`.

See [`fetch` README — HTML link augmentation](../README.md#html-link-augmentation-in---discovery-mode-auto-v102) for the full description.

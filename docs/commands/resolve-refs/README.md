# resolve-refs

Rewrite unresolved `doc://` markers in saved page rawMarkdown

## Synopsis

```bash
cupertino resolve-refs --input <dir> [--use-network] [--use-webview] [--print-unresolved]
```

## Description

`resolve-refs` is a post-process pass over a directory of saved `StructuredDocumentationPage` JSON files (typically produced by a `cupertino fetch --discovery-mode json-only` crawl). It walks every page, harvests a global `identifier → title` map from each page's `sections[].items[]`, and rewrites every `doc://com.apple.<bundle>/...` marker found inside `rawMarkdown` to the human-readable title from the map.

Pure post-process by default: no network calls, no recrawl. Markers that point to pages no other page references are left intact (and reported as unresolved when `--print-unresolved` is set).

`--use-network` and `--use-webview` opt into a second pass that fetches titles for the leftover markers.

Tracked in [#208](https://github.com/mihaelamj/cupertino/issues/208).

## Options

| Option | Description |
|--------|-------------|
| `--input <dir>` (required) | Directory of saved page JSONs (e.g. `~/.cupertino/_docs`) |
| `--use-network` | After harvest+rewrite, fetch titles for the still-unresolved markers via Apple's JSON API. |
| `--use-webview` | When `--use-network` is set, also fall back to WKWebView for markers that the JSON API can't serve. Slow; macOS only. |
| `--print-unresolved` | Print unresolved `doc://` markers (sorted, deduped) to stdout. |

## When to use

The default `cupertino fetch --source apple-docs` writes structured pages where `doc://` markers are already resolved through link discovery. Use `resolve-refs` when:

- A `--discovery-mode json-only` crawl produced pages whose `rawMarkdown` still contains raw `doc://` markers because JSON fetches don't see the rendered HTML the WKWebView pass would have resolved.
- You need to upgrade an older corpus that was crawled before the marker-resolution stage existed.
- You want to enrich a corpus with network-fetched titles without re-crawling.

## Examples

### Pure post-process, no network

```bash
cupertino resolve-refs --input ~/.cupertino/docs
```

### Post-process plus network top-up

```bash
cupertino resolve-refs --input ~/.cupertino/docs --use-network
```

### Aggressive top-up via WKWebView

```bash
cupertino resolve-refs --input ~/.cupertino/docs --use-network --use-webview
```

### Audit which markers remain unresolved

```bash
cupertino resolve-refs --input ~/.cupertino/docs --print-unresolved
```

## See Also

- [fetch](../fetch/) — the upstream command whose `--discovery-mode json-only` output this command rewrites
- [#208](https://github.com/mihaelamj/cupertino/issues/208) — design and motivation

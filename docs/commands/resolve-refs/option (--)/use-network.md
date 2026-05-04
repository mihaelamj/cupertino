# --use-network

After harvest+rewrite, fetch titles for still-unresolved markers via Apple's JSON API

## Synopsis

```bash
cupertino resolve-refs --input <path> --use-network
```

## Description

Second pass after the in-corpus harvest+rewrite. For every `doc://...` marker still unresolved (no other page in the corpus recorded that identifier), fetch Apple's JSON API for the marker's URL and extract its title. Writes back into the corpus pages.

## Default

`false` (post-process only, no network)

## Example

```bash
cupertino resolve-refs --input ~/.cupertino/docs --use-network
```

## Notes

- Slower than the default. Each unresolved marker = one HTTP request to `developer.apple.com`.
- Combine with `--use-webview` to also fall back to WKWebView when JSON API can't serve a marker (slow, macOS only).
- Markers still unresolved after both passes are left intact and surfaced via `--print-unresolved`.

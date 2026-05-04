# --use-webview

Fall back to WKWebView when JSON API can't resolve a marker

## Synopsis

```bash
cupertino resolve-refs --input <path> --use-network --use-webview
```

## Description

Requires `--use-network`. When the JSON API pass returns a 404 / non-JSON response for a marker, render the URL via WKWebView (macOS only) and extract the title from the rendered HTML. Slower than JSON but covers pages that don't have a JSON endpoint.

## Default

`false`

## Example

```bash
cupertino resolve-refs --input ~/.cupertino/docs --use-network --use-webview
```

## Notes

- macOS only — WKWebView isn't available on other platforms.
- Slow. Each fallback render takes seconds; only use when JSON API coverage is insufficient.
- Without `--use-network`, this flag is a no-op.

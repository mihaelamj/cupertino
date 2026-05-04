# --allowed-prefixes

URL prefixes the crawler is allowed to follow (comma-separated)

## Synopsis

```bash
cupertino fetch --type docs --allowed-prefixes <prefix1,prefix2,…>
```

## Description

Acts as a domain/path firewall: links whose URL doesn't start with any of these prefixes are rejected at enqueue time. Keeps the crawl scoped to your intended corpus.

## Default

Auto-derived from `--start-url` when not set — the host + first path segment becomes the implicit prefix.

## Example

```bash
cupertino fetch --type docs --start-url https://developer.apple.com/documentation/swiftui \
  --allowed-prefixes https://developer.apple.com/documentation/
```

## Notes

- Comma-separated, no spaces.
- Case-sensitive on the path (case normalization happens elsewhere — see `URLUtilities.normalize`, #200).
- An empty list (omit the flag) lets the auto-derive take over.

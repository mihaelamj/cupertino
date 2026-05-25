# --start-url

Override the default start URL for the chosen `--source`

## Synopsis

```bash
cupertino fetch --source <type> --start-url <url>
```

## Description

Each web-crawl `--source` (docs, swift, evolution) has a default start URL baked in (`Cupertino.FetchType.defaultURL`). Override here to crawl a different seed.

## Default

Type-dependent. For `--source apple-docs`: `https://developer.apple.com/documentation/`. For `--source swift-org`: swift.org docs root.

## Example

```bash
cupertino fetch --source apple-docs --start-url https://developer.apple.com/documentation/swiftui
```

## Notes

- Only meaningful for web-crawl types (docs, swift, evolution). Direct-fetch types (packages, samples) don't use it.
- The crawler uses this URL to derive `--allowed-prefixes` automatically when the latter isn't set.

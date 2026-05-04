# --start-url

Override the default start URL for the chosen `--type`

## Synopsis

```bash
cupertino fetch --type <type> --start-url <url>
```

## Description

Each web-crawl `--type` (docs, swift, evolution) has a default start URL baked in (`Cupertino.FetchType.defaultURL`). Override here to crawl a different seed.

## Default

Type-dependent. For `--type docs`: `https://developer.apple.com/documentation/`. For `--type swift`: swift.org docs root.

## Example

```bash
cupertino fetch --type docs --start-url https://developer.apple.com/documentation/swiftui
```

## Notes

- Only meaningful for web-crawl types (docs, swift, evolution). Direct-fetch types (packages, samples) don't use it.
- The crawler uses this URL to derive `--allowed-prefixes` automatically when the latter isn't set.

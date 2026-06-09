# --start-url

Override the default start URL for the chosen `--source`

## Synopsis

```bash
cupertino fetch --source <source> --start-url <url>
```

## Description

Each web-crawl `--source` (for example `apple-docs`, `swift-org`, `swift-book`, `swift-evolution`, `hig`, or `apple-archive`) has a default start URL from its source definition. Override here to crawl a different seed.

## Default

Source-dependent. For `--source apple-docs`: `https://developer.apple.com/documentation/`. For `--source swift-org`: swift.org docs root.

## Example

```bash
cupertino fetch --source apple-docs --start-url https://developer.apple.com/documentation/swiftui
```

## Notes

- Only meaningful for web-crawl sources. Direct-fetch sources (`packages`, `samples`, `apple-sample-code`) don't use it.
- The crawler uses this URL to derive `--allowed-prefixes` automatically when the latter isn't set.

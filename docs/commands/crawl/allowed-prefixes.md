# --allowed-prefixes

Allowed URL prefixes (comma-separated)

## Synopsis

```bash
cupertino crawl --allowed-prefixes <prefix1,prefix2,...>
```

## Description

Restricts crawling to URLs that start with the specified prefixes. Auto-detects based on start URL if not specified.

## Examples

### Single Prefix
```bash
cupertino crawl --allowed-prefixes "https://developer.apple.com/documentation/"
```

### Multiple Prefixes
```bash
cupertino crawl --allowed-prefixes "https://developer.apple.com/documentation/,https://developer.apple.com/tutorials/"
```

### Crawl Only SwiftUI Documentation
```bash
cupertino crawl \
  --start-url https://developer.apple.com/documentation/swiftui \
  --allowed-prefixes "https://developer.apple.com/documentation/swiftui"
```

## Auto-Detection

If not specified, prefixes are auto-detected:
- For `https://developer.apple.com/documentation/swift` → `https://developer.apple.com/documentation/`
- For `https://www.swift.org/documentation` → `https://www.swift.org/`

## Notes

- Comma-separated list (no spaces)
- URLs outside these prefixes are ignored
- Prevents crawling unrelated sections of a website
- Use quotes to avoid shell interpretation issues

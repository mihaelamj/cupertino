# --start-url

Start URL to crawl from

## Synopsis

```bash
cupertino crawl --start-url <url>
```

## Description

Specifies the starting URL for the crawl. Overrides the default URL for `--type`.

## Examples

### Crawl from SwiftUI Documentation
```bash
cupertino crawl --start-url https://developer.apple.com/documentation/swiftui
```

### Crawl Specific Swift.org Page
```bash
cupertino crawl --start-url https://www.swift.org/documentation/swift-book
```

### Crawl UIKit
```bash
cupertino crawl --start-url https://developer.apple.com/documentation/uikit
```

## Notes

- Must be a valid HTTP/HTTPS URL
- Crawler will stay within URL prefixes (auto-detected or specified via `--allowed-prefixes`)
- Useful for crawling specific frameworks or sections

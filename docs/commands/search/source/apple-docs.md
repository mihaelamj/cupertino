# apple-docs

Apple Developer Documentation source

## Synopsis

```bash
cupertino search <query> --source apple-docs
```

## Description

Filters search results to only include Apple Developer Documentation. This is the largest documentation source, containing official API documentation for all Apple frameworks.

## Content

- **Framework documentation** (SwiftUI, UIKit, AppKit, Foundation, etc.)
- **API references** (classes, structs, protocols, functions)
- **Programming guides** and conceptual documentation
- **Technology overviews**

## Typical Size

- **13,000+ pages** when fully crawled
- **261 frameworks** indexed
- **~2-3 GB** on disk

## Examples

### Search SwiftUI in Apple Docs
```bash
cupertino search "View" --source apple-docs --framework swiftui
```

### Search All Apple Docs
```bash
cupertino search "URLSession" --source apple-docs
```

### JSON Output
```bash
cupertino search "Observable" --source apple-docs --format json
```

## URI Format

Results use the `apple-docs://` URI scheme:

```
apple-docs://{framework}/{page_path}
```

Examples:
- `apple-docs://swiftui/documentation_swiftui_view`
- `apple-docs://foundation/documentation_foundation_url`

## How to Populate

```bash
# Full crawl (20-24 hours)
cupertino fetch --type docs --max-pages 15000

# Framework-specific crawl
cupertino fetch --type docs \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500

# Build index
cupertino save
```

## Notes

- Crawled from developer.apple.com
- Uses WKWebView for JavaScript rendering
- Change detection for incremental updates
- Most comprehensive Apple API documentation

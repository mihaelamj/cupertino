# Search Sources

Documentation sources that can be searched and filtered

## Overview

The `--source` option filters search results by documentation source. Each source represents a distinct collection of indexed documentation.

## Available Sources

| Source | Description | Typical Count |
|--------|-------------|---------------|
| `apple-docs` | Apple Developer Documentation | 13,000+ pages |
| `swift-evolution` | Swift Evolution proposals | ~430 proposals |
| `swift-org` | Swift.org documentation | ~500 pages |
| `swift-book` | The Swift Programming Language | ~100 pages |
| `packages` | Swift package metadata | 9,600+ packages |
| `apple-sample-code` | Apple sample code projects | ~600 projects |

## Usage

```bash
# Search specific source
cupertino search "async" --source swift-evolution

# Search all sources (default)
cupertino search "async"
```

## Source Details

- [apple-docs](apple-docs.md) - Apple Developer Documentation
- [swift-evolution](swift-evolution.md) - Swift Evolution proposals
- [swift-org](swift-org.md) - Swift.org documentation
- [swift-book](swift-book.md) - The Swift Programming Language book
- [packages](packages.md) - Swift package metadata
- [apple-sample-code](apple-sample-code.md) - Apple sample code projects

## How Sources Are Populated

Sources are populated by the `fetch` command:

| Source | Fetch Command |
|--------|---------------|
| `apple-docs` | `cupertino fetch --type docs` |
| `swift-evolution` | `cupertino fetch --type evolution` |
| `swift-org` | `cupertino fetch --type swift` |
| `swift-book` | `cupertino fetch --type swift` |
| `packages` | Bundled catalog (automatic) |
| `apple-sample-code` | Bundled catalog (automatic) |

## Notes

- Source filtering is case-insensitive
- Invalid source values return no results
- Bundled catalogs are indexed during `cupertino save`
- Use with `--framework` for more specific filtering

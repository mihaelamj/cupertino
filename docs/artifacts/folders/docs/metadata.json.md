# metadata.json - Crawl Metadata File

Tracks crawled pages, content hashes, and enables change detection.

## Location

Created in the output directory of crawl operations:
- `~/.cupertino/docs/metadata.json`
- `~/.cupertino/swift-org/metadata.json`
- `~/.cupertino/swift-evolution/metadata.json`

## Created By

```bash
cupertino crawl --type <docs|swift|evolution>
```

## Purpose

- **Change Detection** - Skip unchanged pages on re-crawl
- **Resume Capability** - Continue interrupted crawls
- **URL Mapping** - Link URLs to local file paths
- **Progress Tracking** - Know what's been crawled

## Structure

```json
{
  "version": "1.0",
  "timestamp": "2025-11-17T10:30:00Z",
  "startURL": "https://developer.apple.com/documentation",
  "pages": {
    "https://developer.apple.com/documentation/swift": {
      "path": "swift/index.md",
      "contentHash": "abc123...",
      "lastCrawled": "2025-11-17T10:31:00Z",
      "framework": "swift"
    },
    "https://developer.apple.com/documentation/swiftui": {
      "path": "swiftui/index.md",
      "contentHash": "def456...",
      "lastCrawled": "2025-11-17T10:32:00Z",
      "framework": "swiftui"
    }
  }
}
```

## Fields

### Top Level
- **version** - Metadata format version
- **timestamp** - When crawl started
- **startURL** - Starting URL of crawl
- **pages** - Dictionary of crawled pages (URL → metadata)

### Per Page
- **path** - Relative file path from output directory
- **contentHash** - SHA-256 hash of content
- **lastCrawled** - When this page was last downloaded
- **framework** - Framework name (if applicable)

## Usage

### Check What's Been Crawled
```bash
# Count pages
jq '.pages | length' metadata.json

# List all frameworks
jq '.pages | to_entries | map(.value.framework) | unique' metadata.json

# Find pages by framework
jq '.pages | to_entries | map(select(.value.framework == "swiftui"))' metadata.json
```

### Resume Crawl
```bash
# Automatically uses metadata.json
cupertino crawl --resume
```

### Force Recrawl (Ignore Metadata)
```bash
# Ignores content hashes, recrawls everything
cupertino crawl --force
```

## Change Detection

When re-crawling:
1. Crawler downloads page
2. Calculates content hash
3. Compares with metadata.json
4. If hash matches → skip writing file (no changes)
5. If hash differs → update file and metadata

## Benefits

- **Faster Re-crawls** - Only download changed pages
- **Resume Support** - Continue from where you left off
- **Idempotent** - Safe to run multiple times
- **URL to File Mapping** - Essential for search index

## Used By

- `cupertino crawl --resume` - Resume functionality
- `cupertino index` - URL mapping for search results
- Change detection on re-crawl

## Notes

- JSON format for easy parsing
- One metadata file per crawl operation
- Can be deleted to force fresh crawl
- Essential for efficient re-crawling

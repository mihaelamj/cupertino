# --source swift-org

Fetch Swift.org documentation

## Synopsis

```bash
cupertino fetch --source swift-org
```

## Description

Crawls and downloads the Swift.org documentation tree from `https://www.swift.org/documentation/`. The Swift Book is no longer co-crawled here; use `cupertino fetch --source swift-book` for `docs.swift.org/swift-book`.

## Data Source

**Swift.org Documentation** - https://www.swift.org/documentation/

## Output

Creates source page files for the Swift.org documentation tree:
- One crawler output file per page
- Directory structure matching the Swift.org documentation crawl
- Metadata tracking in `metadata.json`

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/swift-org` |
| Start URL | `https://www.swift.org/documentation/` |
| Max Pages | 1,000,000 (effectively uncapped, same as `--source apple-docs`) |
| Max Depth | 15 |
| Crawl Method | Web crawl via WKWebView |
| Authentication | Not required |
| Estimated Count | ~500 pages in the v1.3.0 corpus |

## Examples

### Fetch Swift.org Documentation
```bash
cupertino fetch --source swift-org
```

### Fetch with Custom Max Pages
```bash
cupertino fetch --source swift-org --max-pages 500
```

### Resume Interrupted Crawl (automatic)
```bash
# Auto-resumes from metadata.json, no flag needed
cupertino fetch --source swift-org
```

### Discard the Saved Session and Start Over
```bash
cupertino fetch --source swift-org --start-clean
```

### Force Recrawl All Pages
```bash
cupertino fetch --source swift-org --force
```

### Custom Output Directory
```bash
cupertino fetch --source swift-org --output-dir ./swift-docs
```

## Output Structure

```
~/.cupertino/swift-org/
├── metadata.json
├── documentation/
│   └── ...
└── ... (Swift.org documentation pages)
```

## Covered Content

- Swift.org documentation pages
- Server-side Swift guides
- Package manager and language ecosystem pages
- Release and project documentation reachable from the Swift.org documentation root

## Crawl Behavior

1. **Respectful crawling** - 0.05 second default delay between requests
2. **Change detection** - Only re-downloads changed pages (via content hash)
3. **Session persistence** - Can pause and resume crawls
4. **Auto-save** - Progress saved every 100 pages
5. **Error recovery** - Skips failed pages, continues crawling

## Performance

| Metric | Value |
|--------|-------|
| Initial crawl time | 15-30 minutes (~500 pages) |
| Incremental update | Minutes (only changed) |
| Average page size | source-page dependent |
| Total storage | ~10-20 MB |
| Pages per minute | source/network dependent |

## Use Cases

- Offline Swift.org documentation
- Learning Swift programming
- Language feature lookup
- Full-text search of Swift docs
- AI-assisted Swift development
- Swift ecosystem reference

## Notes

- Focuses on Swift.org documentation; the Swift Book has its own source (`swift-book`)
- Does not include API documentation (use `--source apple-docs` for APIs)
- No authentication required
- Compatible with `cupertino save --source swift-org` for search indexing
- Updated with each Swift version release

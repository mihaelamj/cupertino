# --source apple-docs

Fetch Apple Developer Documentation

## Synopsis

```bash
cupertino fetch --source apple-docs
```

## Description

Crawls and downloads Apple's official developer documentation from developer.apple.com. This is the **default fetch source** and captures comprehensive API documentation for all Apple frameworks and platforms.

## Data Source

**Apple Developer Documentation** - https://developer.apple.com/documentation/

## Output

Creates DocC render-JSON files for each documentation page:
- One `.json` file per documentation page
- Framework-grouped directory structure using lowercased framework names
- Metadata tracking in `metadata.json`

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/docs` |
| Start URL | `https://developer.apple.com/documentation/` |
| Max Pages | 1,000,000 (effectively uncapped) |
| Max Depth | 15 |
| Crawl Method | JSON API + WKWebView fallback (`--discovery-mode auto`) |
| Authentication | Not required |
| Estimated Count | ~400,000+ pages on a full crawl (snapshot of v1.0 corpus) |

## Examples

### Fetch Apple Documentation (Default)
```bash
cupertino fetch --source apple-docs
```

### Fetch with Custom Max Pages
```bash
cupertino fetch --source apple-docs --max-pages 5000
```

### Fetch Specific Framework
```bash
cupertino fetch --source apple-docs --start-url https://developer.apple.com/documentation/swiftui
```

### Resume Interrupted Crawl (automatic)
```bash
# Auto-resumes from metadata.json, no flag needed
cupertino fetch --source apple-docs
```

### Discard the Saved Session and Start Over
```bash
cupertino fetch --source apple-docs --start-clean
```

### Force Recrawl All Pages
```bash
cupertino fetch --source apple-docs --force
```

### Custom Output Directory
```bash
cupertino fetch --source apple-docs --output-dir ./my-docs
```

## Output Structure

```
~/.cupertino/docs/
├── metadata.json
├── foundation/
│   ├── documentation_foundation_url.json
│   ├── documentation_foundation_urlsession.json
│   └── ...
├── swiftui/
│   ├── documentation_swiftui_view.json
│   ├── documentation_swiftui_text.json
│   └── ...
├── uikit/
│   ├── documentation_uikit_uiviewcontroller.json
│   ├── documentation_uikit_uitableview.json
│   └── ...
└── ... (all frameworks)
```

## Metadata File

`metadata.json` tracks crawl state and page information:

```json
{
  "version": "1.0",
  "crawlState": {
    "isActive": true,
    "startURL": "https://developer.apple.com/documentation/",
    "outputDirectory": "~/.cupertino/docs",
    "totalPages": 404726,
    "processedPages": 404726,
    "lastCrawled": "2025-11-19T10:30:00Z"
  },
  "pages": {
    "https://developer.apple.com/documentation/swiftui/view": {
      "title": "View",
      "contentHash": "a1b2c3d4...",
      "lastCrawled": "2025-11-19T10:30:00Z",
      "outputPath": "swiftui/documentation_swiftui_view.json"
    }
  }
}
```

## Covered Frameworks

- **SwiftUI** - Modern UI framework
- **UIKit** - Traditional iOS/iPadOS UI
- **AppKit** - macOS UI framework
- **Foundation** - Core data types and utilities
- **Combine** - Reactive programming
- **Core Data** - Object graph persistence
- **Core ML** - Machine learning
- **ARKit** - Augmented reality
- **RealityKit** - 3D rendering
- **SceneKit** - 3D graphics
- **SpriteKit** - 2D games
- **And 200+ more frameworks**

## Crawl Behavior

1. **Respectful crawling** - 0.05 second default delay between requests
2. **Change detection** - Only re-downloads changed pages (via content hash)
3. **Session persistence** - Can pause and resume long crawls
4. **Auto-save** - Progress saved every 100 pages
5. **Error recovery** - Skips failed pages, continues crawling

## Performance

| Metric | Value |
|--------|-------|
| Initial crawl time | 12+ days (~404,000+ pages) |
| Incremental update | Minutes to hours (only changed) |
| Average page size | varies by DocC JSON payload |
| Total storage | several GB for the current full corpus |
| Pages per minute | source/network dependent (with 0.05s default delay) |

## Use Cases

- Offline documentation access
- Full-text search indexing
- AI-assisted development (MCP server)
- Documentation analysis
- Framework coverage tracking
- Change monitoring

## Notes

- **Default fetch source** - `--source apple-docs` can be omitted
- Requires internet connection
- No authentication needed
- DocC pages are preserved as render JSON for indexing
- Preserves documentation structure
- Includes code examples and descriptions
- Compatible with `cupertino save` for search indexing

# --type docs

Fetch Apple Developer Documentation

## Synopsis

```bash
cupertino fetch --type docs
```

## Description

Crawls and downloads Apple's official developer documentation from developer.apple.com. This is the **default fetch type** and captures comprehensive API documentation for all Apple frameworks and platforms.

## Data Source

**Apple Developer Documentation** - https://developer.apple.com/documentation/

## Output

Creates Markdown files for each documentation page:
- One `.md` file per documentation page
- Hierarchical directory structure matching Apple's organization
- Metadata tracking in `metadata.json`

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/docs` |
| Start URL | `https://developer.apple.com/documentation/` |
| Max Pages | 13,000 |
| Max Depth | 15 |
| Crawl Method | Web crawl via WKWebView |
| Authentication | Not required |
| Estimated Count | ~13,000-15,000 pages |

## Examples

### Fetch Apple Documentation (Default)
```bash
cupertino fetch --type docs
```

### Fetch with Custom Max Pages
```bash
cupertino fetch --type docs --max-pages 5000
```

### Fetch Specific Framework
```bash
cupertino fetch --type docs --start-url https://developer.apple.com/documentation/swiftui
```

### Resume Interrupted Crawl
```bash
cupertino fetch --type docs --resume
```

### Force Recrawl All Pages
```bash
cupertino fetch --type docs --force
```

### Custom Output Directory
```bash
cupertino fetch --type docs --output-dir ./my-docs
```

## Output Structure

```
~/.cupertino/docs/
├── metadata.json
├── Foundation/
│   ├── NSString.md
│   ├── NSArray.md
│   └── ...
├── SwiftUI/
│   ├── View.md
│   ├── Text.md
│   └── ...
├── UIKit/
│   ├── UIViewController.md
│   ├── UIView.md
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
    "totalPages": 13842,
    "processedPages": 13842,
    "lastCrawled": "2025-11-19T10:30:00Z"
  },
  "pages": {
    "https://developer.apple.com/documentation/swiftui/view": {
      "title": "View",
      "contentHash": "a1b2c3d4...",
      "lastCrawled": "2025-11-19T10:30:00Z",
      "outputPath": "SwiftUI/View.md"
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

1. **Respectful crawling** - 0.5 second delay between requests
2. **Change detection** - Only re-downloads changed pages (via content hash)
3. **Session persistence** - Can pause and resume long crawls
4. **Auto-save** - Progress saved every 100 pages
5. **Error recovery** - Skips failed pages, continues crawling

## Performance

| Metric | Value |
|--------|-------|
| Initial crawl time | 20-24 hours (13,000 pages) |
| Incremental update | Minutes to hours (only changed) |
| Average page size | 10-50 KB (markdown) |
| Total storage | ~200-300 MB |
| Pages per minute | ~10-12 (with 0.5s delay) |

## Use Cases

- Offline documentation access
- Full-text search indexing
- AI-assisted development (MCP server)
- Documentation analysis
- Framework coverage tracking
- Change monitoring

## Notes

- **Default fetch type** - `--type docs` can be omitted
- Requires internet connection
- No authentication needed
- HTML automatically converted to Markdown
- Preserves documentation structure
- Includes code examples and descriptions
- Compatible with `cupertino save` for search indexing

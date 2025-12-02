# --type archive

Fetch Apple Archive Legacy Programming Guides

## Synopsis

```bash
cupertino fetch --type archive
```

## Description

Downloads legacy Apple programming guides from developer.apple.com/library/archive. These are pre-2016 guides that contain foundational knowledge and deep conceptual explanations not available in modern documentation.

## Data Source

**Apple Developer Archive** - https://developer.apple.com/library/archive/

## Output

Creates Markdown files with YAML front matter:
- Organized by guide ID (TP######)
- Chapter/section structure preserved
- Framework metadata included

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/archive` |
| Source | Apple Developer Archive |
| Fetch Method | Web crawling with WKWebView |
| Authentication | Not required |
| Estimated Size | ~75 pages, 5-10 MB |

## Examples

### Fetch All Essential Guides
```bash
cupertino fetch --type archive
```

### Resume Interrupted Download
```bash
cupertino fetch --type archive --resume
```

### Force Re-download
```bash
cupertino fetch --type archive --force
```

### Custom Output Directory
```bash
cupertino fetch --type archive --output-dir ./archive
```

## Output Structure

```
~/.cupertino/archive/
├── TP40004514/                    # Core Animation Programming Guide
│   ├── CoreAnimationBasics.md
│   ├── SettingUpLayerObjects.md
│   └── ...
├── TP30001066/                    # Quartz 2D Programming Guide
│   ├── dq_overview.md
│   ├── dq_context.md
│   └── ...
├── TP40003577/                    # Core Text Programming Guide
│   └── ...
└── ...                            # ~8 guide folders
```

## Available Guides

| TP ID | Guide Name | Framework |
|-------|------------|-----------|
| TP40004514 | Core Animation Programming Guide | QuartzCore |
| TP30001066 | Quartz 2D Programming Guide | CoreGraphics |
| TP40003577 | Core Text Programming Guide | CoreText |
| TP40002974 | Core Image Programming Guide | CoreImage |
| TP40005533 | Core Audio Overview | CoreAudio |
| TP40006166 | Animation Types and Timing | QuartzCore |
| TP40009492 | Audio Unit Hosting Guide | CoreAudio |
| TP40001185 | Cocoa Fundamentals Guide | Cocoa |

## YAML Front Matter

Each file includes metadata:

```yaml
---
title: "Core Animation Basics"
book: "Core Animation Programming Guide"
framework: "QuartzCore"
chapterId: "TP40004514-CH1"
date: "2015-03-09"
source: apple-archive
---
```

## Framework Synonyms

Archive docs are indexed with synonyms for better search:
- `QuartzCore` also indexed as `CoreAnimation`
- `CoreGraphics` also indexed as `Quartz2D`

## Search Integration

Archive documentation is excluded from search by default:

### Include in Mixed Results
```bash
cupertino search "Core Animation" --include-archive
```

### Search Archive Only
```bash
cupertino search "CALayer" --source apple-archive
```

## Performance

| Metric | Value |
|--------|-------|
| Download time | 5-10 minutes |
| Incremental update | Minutes (only changed) |
| Total storage | ~5-10 MB |
| Pages | ~75 markdown files |

## Use Cases

- Deep dive into framework fundamentals
- Understanding low-level graphics APIs
- Learning Core Animation layer concepts
- Core Graphics/Quartz 2D programming
- Core Text layout and rendering
- Audio programming fundamentals

## Why Archive Documentation?

Modern Apple documentation focuses on API reference but often lacks:
- **Conceptual explanations** - The "why" behind design decisions
- **System architecture** - How components interact
- **Implementation patterns** - Best practices and common approaches
- **Historical context** - Understanding API evolution

Archive guides fill these gaps with comprehensive programming guides.

## Notes

- Content from pre-2016 Apple documentation
- Some APIs may be deprecated but concepts remain valid
- Excluded from default search to prioritize modern docs
- Use `--include-archive` or `--source apple-archive` for search
- Great complement to modern API documentation

# archive/ - Apple Archive Programming Guides

Legacy Apple programming guides from the developer.apple.com/library/archive.

## Location

**Default**: `~/.cupertino/archive/`

## Created By

```bash
cupertino fetch --type archive
```

## Structure

```
~/.cupertino/archive/
├── TP30001066/                     # Quartz 2D Programming Guide
│   ├── dq_overview.md
│   ├── dq_context.md
│   ├── dq_paths.md
│   └── ...
├── TP40004514/                     # Core Animation Programming Guide
│   ├── CoreAnimationBasics.md
│   ├── SettingUpLayerObjects.md
│   └── ...
├── TP40003577/                     # Core Text Programming Guide
│   └── ...
└── ...                             # ~8 guide folders
```

## Contents

### Guide Folders
Each folder is named by Apple's technical publication ID (TP######).

### Markdown Files
- Converted from Apple's HTML documentation
- YAML front matter with metadata
- Full content preserved

### YAML Front Matter Example
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

## Available Guides

| TP ID | Guide Name | Framework |
|-------|-----------|-----------|
| TP30001066 | Quartz 2D Programming Guide | CoreGraphics |
| TP40004514 | Core Animation Programming Guide | QuartzCore |
| TP40003577 | Core Text Programming Guide | CoreText |
| TP40002974 | Core Image Programming Guide | CoreImage |
| TP40005533 | Core Audio Overview | CoreAudio |
| TP40006166 | Animation Types and Timing | QuartzCore |
| TP40009492 | Audio Unit Hosting Guide | CoreAudio |
| TP40001185 | Cocoa Fundamentals Guide | Cocoa |

## Size

- **~75 markdown files**
- **~5-10 MB total**

## Search Behavior

Archive documentation is **excluded from search by default** to prioritize modern documentation.

### Include in Search Results
```bash
cupertino search "Core Animation" --include-archive
```

### Search Archive Only
```bash
cupertino search "CALayer" --source apple-archive
```

### MCP Tool Usage
```json
{
  "query": "Core Animation",
  "include_archive": true
}
```

## Framework Synonyms

Archive docs are indexed with framework synonyms for better discoverability:
- `QuartzCore` also indexed as `CoreAnimation`
- `CoreGraphics` also indexed as `Quartz2D`

## Why Archive?

These guides contain foundational knowledge not available in modern documentation:
- Deep conceptual explanations
- Historical context
- Implementation details
- Patterns still relevant today

## Customizing Selection

Use the TUI to select which guides to crawl:
```bash
cupertino-tui
# Navigate to Archive view (4)
# Select/deselect guides with Space
# Save with 'w'
```

Selection is stored in `~/.cupertino/selected-archive-guides.json`.

## Notes

- Guides are from Apple's pre-2016 documentation archive
- Content may reference older APIs but concepts remain valid
- Great for understanding the "why" behind Apple frameworks
- Modern docs often lack this level of conceptual depth

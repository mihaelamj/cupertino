---
name: cupertino
description: Search and read Apple developer documentation including SwiftUI, UIKit, Foundation, and 300+ frameworks. Use when the user asks about Apple APIs, iOS/macOS development, Swift syntax, or needs to look up Apple documentation.
license: MIT
compatibility: Requires macOS 13+, pre-built database via 'cupertino setup'
metadata:
  author: mihaelamj
  version: "1.0"
allowed-tools: Bash(cupertino:*)
---

# Cupertino - Apple Documentation Search

Search 300,000+ Apple developer documentation pages offline.

## Setup

First-time setup (downloads ~2.4GB database):
```bash
cupertino setup
```

## Commands

### Search Documentation
Search across all sources (apple-docs, samples, hig, swift-evolution, swift-org, swift-book, packages):
```bash
cupertino search "SwiftUI View" --format json
```

Filter by source:
```bash
cupertino search "async await" --source swift-evolution --format json
cupertino search "NavigationStack" --source apple-docs --format json
cupertino search "button styles" --source samples --format json
cupertino search "button guidelines" --source hig --format json
```

Filter by framework:
```bash
cupertino search "@Observable" --framework swiftui --format json
```

### Read a Document
Retrieve full document content by URI:
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format json
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown
```

### List Frameworks
List all indexed frameworks with document counts:
```bash
cupertino list-frameworks --format json
```

### List Sample Projects
Browse indexed Apple sample code projects:
```bash
cupertino list-samples --format json
cupertino list-samples --framework swiftui --format json
```

### Read Sample Code
Read a sample project or specific file:
```bash
cupertino read-sample "foodtrucksampleapp" --format json
cupertino read-sample-file "foodtrucksampleapp" "FoodTruckApp.swift" --format json
```

## Sources

| Source | Description |
|--------|-------------|
| `apple-docs` | Official Apple documentation (301,000+ pages) |
| `swift-evolution` | Swift Evolution proposals |
| `hig` | Human Interface Guidelines |
| `samples` | Apple sample code projects |
| `swift-org` | Swift.org documentation |
| `swift-book` | The Swift Programming Language book |
| `apple-archive` | Legacy guides (Core Animation, Quartz 2D, KVO/KVC) |
| `packages` | Swift package documentation |

## Output Formats

All commands support `--format` with these options:
- `text` - Human-readable output (default for most commands)
- `json` - Structured JSON for parsing
- `markdown` - Formatted markdown

## Example JSON Output

```json
{
  "results": [
    {
      "uri": "apple-docs://swiftui/documentation_swiftui_vstack",
      "title": "VStack",
      "framework": "SwiftUI",
      "summary": "A view that arranges its children vertically",
      "source": "apple-docs"
    }
  ],
  "count": 1,
  "query": "VStack"
}
```

## Tips

- Use `--source` to narrow searches to a specific documentation source
- Use `--framework` to filter by framework (e.g., swiftui, foundation, uikit)
- Use `--limit` to control the number of results returned
- URIs from search results can be used directly with `cupertino read`

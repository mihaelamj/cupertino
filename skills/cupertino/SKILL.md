---
name: cupertino
description: This skill should be used when working with Apple APIs, iOS/macOS/visionOS development, or Swift language questions. Covers searching Apple developer documentation, looking up SwiftUI views, finding UIKit APIs, reading Apple docs, browsing Swift Evolution proposals, checking Human Interface Guidelines, and exploring Apple sample code. Supports 300+ frameworks including SwiftUI, UIKit, Foundation, and Combine via offline search of 300,000+ documentation pages.
allowed-tools: Bash(cupertino *)
---

# Cupertino - Apple Documentation Search

Search 300,000+ Apple developer documentation pages offline.

## Setup

First-time setup (downloads ~2.4GB database):
```bash
cupertino setup
```

## Workflow

To answer questions about Apple APIs, first search for relevant documents, then read the most relevant result:

1. Search: `cupertino search "NavigationStack" --source apple-docs --format json`
2. Read: `cupertino read "<uri-from-results>" --format markdown`

If the database is not set up, run `cupertino setup` first.

## Commands

### Search Documentation
Search across all sources (apple-docs, samples, hig, swift-evolution, swift-org, swift-book, packages):
```bash
cupertino search "SwiftUI View" --format json
cupertino search "SwiftUI View" --format json --limit 5
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
- Legacy archive guides are excluded from search by default; add `--include-archive` to include them

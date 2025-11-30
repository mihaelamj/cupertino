# --format

Output format for document content

## Synopsis

```bash
cupertino read <uri> --format <format>
```

## Description

Controls how the document content is formatted in the output. Different formats are suited for different use cases.

## Values

| Format | Description |
|--------|-------------|
| `json` | Structured JSON object (default) |
| `markdown` | Rendered markdown content |

## Default

`json`

## Examples

### JSON Output (Default)
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view"
```

Output:
```json
{
  "title": "View",
  "kind": "Protocol",
  "module": "SwiftUI",
  "declaration": "protocol View",
  "abstract": "A type that represents part of your app's user interface...",
  "overview": "You create custom views by declaring types that conform to the View protocol...",
  "topics": [...],
  "relationships": {...}
}
```

### Markdown Output
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown
```

Output:
```markdown
---
source: https://developer.apple.com/documentation/SwiftUI/View
crawled: 2025-11-30T21:23:10Z
---

# View

**Protocol**

A type that represents part of your app's user interface...

## Overview

You create custom views by declaring types that conform to the View protocol...
```

## Use Cases

### JSON Format
- AI agent integration (recommended)
- Programmatic processing
- Extracting specific fields with `jq`
- When you need structured data

### Markdown Format
- Human reading
- Documentation export
- Copy-paste to notes
- Saving to files

## Examples with Piping

### Extract Declaration
```bash
cupertino read "apple-docs://swift/documentation_swift_array" --format json | jq '.declaration'
```

### Save to File
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown > view.md
```

## Notes

- JSON output contains the full structured document data
- Markdown includes YAML front matter with source URL and crawl date
- Both formats contain the complete document content
- Use `cupertino search` first to find valid URIs

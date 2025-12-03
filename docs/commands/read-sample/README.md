# read-sample

Read a sample project's README and metadata.

## Synopsis

```bash
cupertino read-sample <project-id> [--format <format>] [--sample-db <path>]
```

## Description

Reads the README and metadata for a sample code project. Shows project title, description, frameworks, file list, and README content.

## Arguments

### project-id (required)

The project identifier (folder name). Use `list-samples` or `search-samples` to find valid project IDs.

## Options

### --format

Output format: `text` (default), `json`, or `markdown`.

### --sample-db

Path to sample index database. Defaults to `~/.cupertino/sample-index.sqlite`.

## Examples

```bash
# Read project README
cupertino read-sample building-a-document-based-app-with-swiftui

# Output as Markdown
cupertino read-sample fruta-building-a-feature-rich-app-with-swiftui --format markdown

# Output as JSON
cupertino read-sample implementing-modern-collection-views --format json
```

## Sample Output

```
Building a Document-Based App with SwiftUI
==========================================

Project ID: building-a-document-based-app-with-swiftui
Frameworks: SwiftUI, UIKit
Files: 12
Size: 45 KB
Apple Developer: https://developer.apple.com/...

Description:
Create, save, and open documents in your app...

README:
# Building a Document-Based App with SwiftUI
...

Files (12 total):
  - ContentView.swift
  - DocumentApp.swift
  ...

Tip: Use 'cupertino read-sample-file building-a-document-based-app-with-swiftui <path>' to view source code
```

## See Also

- [list-samples](../list-samples/) - List all projects
- [search-samples](../search-samples/) - Search projects
- [read-sample-file](../read-sample-file/) - Read source file

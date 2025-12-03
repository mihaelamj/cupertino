# read-sample-file

Read a source file from a sample project.

## Synopsis

```bash
cupertino read-sample-file <project-id> <file-path> [--format <format>] [--sample-db <path>]
```

## Description

Reads the content of a specific source file from a sample code project. Use this to examine implementation details.

## Arguments

### project-id (required)

The project identifier (folder name). Use `list-samples` or `search-samples` to find valid project IDs.

### file-path (required)

The relative path to the file within the project. Use `read-sample` to list available files.

## Options

### --format

Output format: `text` (default), `json`, or `markdown`.

### --sample-db

Path to sample index database. Defaults to `~/.cupertino/sample-index.sqlite`.

## Examples

```bash
# Read a Swift file
cupertino read-sample-file building-a-document-based-app-with-swiftui ContentView.swift

# Read with markdown formatting (syntax highlighted)
cupertino read-sample-file fruta-building-a-feature-rich-app-with-swiftui Shared/Smoothie.swift --format markdown

# Read as JSON
cupertino read-sample-file implementing-modern-collection-views ViewController.swift --format json
```

## Sample Output

```
// File: ContentView.swift
// Project: building-a-document-based-app-with-swiftui
// Size: 1.2 KB

import SwiftUI

struct ContentView: View {
    @Binding var document: MyDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}
```

## See Also

- [read-sample](../read-sample/) - Read project README and file list
- [search-samples](../search-samples/) - Search for files
- [list-samples](../list-samples/) - List all projects

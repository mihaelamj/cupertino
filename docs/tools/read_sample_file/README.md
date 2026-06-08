# read_sample_file

Read a specific source file from a sample code project.

## Synopsis

```json
{
  "name": "read_sample_file",
  "arguments": {
    "project_id": "building-a-document-based-app-with-swiftui",
    "file_path": "DocumentBrowser/ContentView.swift",
    "format": "json"
  }
}
```

## Description

Reads the content of a specific source file from a sample code project. Use this to examine implementation details of Swift, SwiftUI, or other source files.

## Parameters

### project_id (required)

The project identifier (folder name) of the sample.

**Type:** String

### file_path (required)

The relative path to the file within the project.

**Type:** String

**Examples:**
- `"ContentView.swift"`
- `"Sources/App/AppDelegate.swift"`
- `"Shared/Models/DataModel.swift"`

Use `search` (with `source: samples`) to find files within projects.

### format (optional)

Output format. Default: `markdown`; use `json` for a typed GUI-decodable payload.

## Response

Default markdown returns a fenced code block. `format=json` returns source metadata and content:

```json
{
  "projectId": "building-a-document-based-app-with-swiftui",
  "path": "DocumentBrowser/ContentView.swift",
  "filename": "ContentView.swift",
  "folder": "DocumentBrowser",
  "fileExtension": "swift",
  "language": "swift",
  "size": 4096,
  "content": "import SwiftUI\n..."
}
```

## Examples

### Read Swift File

```json
{
  "project_id": "fruta-building-a-feature-rich-app-with-swiftui",
  "file_path": "Shared/Smoothie.swift",
  "format": "json"
}
```

### Read View File

```json
{
  "project_id": "building-a-document-based-app-with-swiftui",
  "file_path": "DocumentBrowser/ContentView.swift"
}
```

## See Also

- `search` (with `source: samples`) - Search sample code
- [list_samples](../list_samples/) - List all projects
- [read_sample](../read_sample/) - Read project README

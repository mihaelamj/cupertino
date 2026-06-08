# read_sample

Read the README of a sample code project.

## Synopsis

```json
{
  "name": "read_sample",
  "arguments": {
    "project_id": "building-a-document-based-app-with-swiftui",
    "format": "json"
  }
}
```

## Description

Reads the README file from a sample code project. The README typically contains project overview, requirements, and usage instructions.

## Parameters

### project_id (required)

The project identifier (folder name) of the sample.

**Type:** String

**Examples:**
- `"building-a-document-based-app-with-swiftui"`
- `"fruta-building-a-feature-rich-app-with-swiftui"`
- `"implementing-modern-collection-views"`

Use `list_samples` or `search` (with `source: samples`) to find project IDs.

### format (optional)

Output format. Default: `markdown`; use `json` for a typed GUI-decodable payload.

## Response

Default markdown returns the README, metadata, and an abbreviated file list. `format=json` returns project metadata and file summaries:

```json
{
  "id": "building-a-document-based-app-with-swiftui",
  "title": "Building a Document-Based App with SwiftUI",
  "description": "...",
  "frameworks": ["swiftui"],
  "readme": "...",
  "webURL": "https://developer.apple.com/...",
  "zipFilename": "sample.zip",
  "fileCount": 12,
  "totalSize": 123456,
  "deploymentTargets": {
    "ios": "17.0"
  },
  "files": [
    {
      "projectId": "building-a-document-based-app-with-swiftui",
      "path": "ContentView.swift",
      "filename": "ContentView.swift",
      "folder": "",
      "fileExtension": "swift",
      "size": 4096
    }
  ]
}
```

## Examples

### Read Project README

```json
{
  "project_id": "building-a-document-based-app-with-swiftui",
  "format": "json"
}
```

## See Also

- `search` (with `source: samples`) - Search sample code
- [list_samples](../list_samples/) - List all projects
- [read_sample_file](../read_sample_file/) - Read specific source file

# list_samples

List all indexed Apple sample code projects.

## Synopsis

```json
{
  "name": "list_samples",
  "arguments": {
    "format": "json"
  }
}
```

## Description

Returns a list of all indexed sample code projects with their titles, descriptions, and frameworks.

## Parameters

None required.

### framework (optional)

Filter projects by framework slug, for example `"swiftui"` or `"uikit"`.

### limit (optional)

Maximum projects to return. Default: `50`.

### format (optional)

Output format. Default: `markdown`; use `json` for a typed GUI-decodable payload.

## Response

Default markdown returns a project table with metadata. `format=json` returns:

```json
{
  "totalProjects": 619,
  "totalFiles": 18928,
  "framework": "swiftui",
  "limit": 50,
  "projects": [
    {
      "id": "building-a-document-based-app-with-swiftui",
      "title": "Building a Document-Based App with SwiftUI",
      "description": "...",
      "frameworks": ["swiftui", "uikit"],
      "fileCount": 12,
      "totalSize": 123456
    }
  ]
}
```

## Examples

### List All Projects

```json
{}
```

### Typed JSON

```json
{
  "framework": "swiftui",
  "format": "json"
}
```

## See Also

- `search` (with `source: samples`) - Search sample code
- [read_sample](../read_sample/) - Read sample README
- [read_sample_file](../read_sample_file/) - Read specific source file

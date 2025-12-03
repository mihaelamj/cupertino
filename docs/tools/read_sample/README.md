# read_sample

Read the README of a sample code project.

## Synopsis

```json
{
  "name": "read_sample",
  "arguments": {
    "project_id": "building-a-document-based-app-with-swiftui"
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

Use `list_samples` or `search_samples` to find project IDs.

## Response

Returns the README content in markdown format.

## Examples

### Read Project README

```json
{
  "project_id": "building-a-document-based-app-with-swiftui"
}
```

## See Also

- [search_samples](../search_samples/) - Search sample code
- [list_samples](../list_samples/) - List all projects
- [read_sample_file](../read_sample_file/) - Read specific source file

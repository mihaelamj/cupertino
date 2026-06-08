# list-documents

List documents in an indexed framework.

## Synopsis

```bash
cupertino list-documents --framework <framework> [--source apple-docs] [--offset <n>] [--limit <n>] [--format <format>]
```

## Description

Lists lightweight document metadata for a framework: `uri`, `title`, and `kind`. The command is intended for browser-style clients that first call `list-frameworks`, then page through documents in one framework before calling `read`.

The command reads the existing per-source database. For the current desktop contract, `--source` defaults to `apple-docs` and resolves `apple-documentation.db` from the configured base directory.

## Options

### --framework

Required. Framework identifier, import name, or display name. Examples: `swiftui`, `SwiftUI`, `Swift UI`.

### --source

Source to browse. Default: `apple-docs`.

### --offset

Zero-based result offset. Default: `0`.

### --limit

Maximum documents to return. Default: `100`, maximum: `500`.

### --format

Output format: `json` (default), `text`, or `markdown` / `md`.

## JSON Response

```json
{
  "source": "apple-docs",
  "framework": "swiftui",
  "offset": 0,
  "limit": 100,
  "total": 6500,
  "documents": [
    {
      "uri": "apple-docs://swiftui/documentation_swiftui_view",
      "title": "View",
      "kind": "protocol"
    }
  ]
}
```

## Examples

```bash
# First discover frameworks
cupertino list-frameworks --format json

# Then page through one framework for app/browser UI
cupertino list-documents --framework swiftui --offset 0 --limit 50 --format json

# Human-readable output
cupertino list-documents --framework foundation --format markdown
```

## See Also

- [list-frameworks](../list-frameworks/) - Discover framework identifiers
- [read](../read/) - Read full document content by URI
- [search](../search/) - Search documentation by keywords

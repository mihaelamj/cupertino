# list-children

List direct children of a document or topic group.

## Synopsis

```bash
cupertino list-children <uri> [--source apple-docs] [--format <format>]
```

## Description

Lists immediate child nodes for an Apple documentation URI. The command is intended for tree and outline browsers that start from a framework root, drill into topic groups, and then read a selected document URI.

Topic headings are represented as synthetic fragment URIs. For example, `cupertino list-children apple-docs://swiftui` can return a `topic-group` child like `apple-docs://swiftui#Essentials`; calling `list-children` on that fragment returns the documents inside the group.

The command reads the existing per-source database. For the current desktop contract, `--source` defaults to `apple-docs` and resolves `apple-documentation.db` from the configured base directory.

## Arguments

### uri

Required. Apple documentation URI or topic-group fragment URI.

Examples:

- `apple-docs://swiftui`
- `apple-docs://swiftui#Essentials`
- `https://developer.apple.com/documentation/swiftui`

## Options

### --source

Source to browse. Default: `apple-docs`.

### --format

Output format: `json` (default), `text`, or `markdown` / `md`.

## JSON Response

```json
{
  "source": "apple-docs",
  "parentURI": "apple-docs://swiftui",
  "children": [
    {
      "uri": "apple-docs://swiftui#Essentials",
      "title": "Essentials",
      "kind": "topic-group",
      "hasChildren": true
    }
  ]
}
```

## Examples

```bash
# List topic groups on a framework root
cupertino list-children apple-docs://swiftui --format json

# Drill into one topic group
cupertino list-children 'apple-docs://swiftui#Essentials' --format json

# Human-readable output
cupertino list-children apple-docs://swiftui --format markdown
```

## See Also

- [list-documents](../list-documents/) - Page documents in a framework
- [read](../read/) - Read full document content by URI
- [search](../search/) - Search documentation by keywords

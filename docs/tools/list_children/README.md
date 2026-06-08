# list_children

List direct children of an Apple documentation URI.

## Synopsis

```json
{
  "name": "list_children",
  "arguments": {
    "uri": "apple-docs://swiftui",
    "source": "apple-docs"
  }
}
```

## Description

Returns immediate child nodes for a document or topic group. This is the MCP sibling of [`cupertino list-children`](../../commands/list-children/), intended for UI clients that browse documentation as a tree before reading a selected document.

Topic headings are returned as `kind: "topic-group"` with fragment URIs, for example `apple-docs://swiftui#Essentials`. Call `list_children` again with that fragment URI to list the documents inside the heading.

The current MCP server wires this tool to the apple-docs index, so `source` defaults to `apple-docs`.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `uri` | Yes | Apple documentation URI or topic-group fragment URI |
| `source` | No | Source to browse. Default: `apple-docs` |

## Response

Returns JSON:

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

## Example

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "list_children",
    "arguments": {
      "uri": "apple-docs://swiftui#Essentials"
    }
  }
}
```

## See Also

- [list_documents](../list_documents/) - Page documents in a framework
- [read_document](../read_document/) - Read full document content by URI
- [search](../search/) - Search documentation by keywords

# list_documents

List documents in a framework with pagination.

## Synopsis

```json
{
  "name": "list_documents",
  "arguments": {
    "framework": "swiftui",
    "source": "apple-docs",
    "offset": 0,
    "limit": 100
  }
}
```

## Description

Returns lightweight document metadata for a framework: `uri`, `title`, and `kind`. This is the MCP sibling of [`cupertino list-documents`](../../commands/list-documents/), intended for UI clients that browse by framework before reading a selected URI.

The current MCP server wires this tool to the apple-docs index, so `source` defaults to `apple-docs`.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `framework` | Yes | Framework identifier, import name, or display name (for example `swiftui` or `SwiftUI`) |
| `source` | No | Source to browse. Default: `apple-docs` |
| `offset` | No | Zero-based result offset. Default: `0` |
| `limit` | No | Maximum documents to return. Default: `100`, maximum: `500` |

## Response

Returns JSON:

```json
{
  "source": "apple-docs",
  "framework": "swiftui",
  "offset": 0,
  "limit": 100,
  "total": 6500,
  "documents": [
    {
      "uri": "apple-docs://swiftui/view",
      "title": "View",
      "kind": "protocol"
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
    "name": "list_documents",
    "arguments": {
      "framework": "swiftui",
      "offset": 0,
      "limit": 50
    }
  }
}
```

## See Also

- [list_frameworks](../list_frameworks/) - Discover available framework names
- [read_document](../read_document/) - Read full document content by URI
- [search](../search/) - Search documentation by keywords

# search_symbols

Search Swift symbols by type and name pattern using AST extraction.

## Synopsis

```json
{
  "name": "search_symbols",
  "arguments": {
    "query": "Manager",
    "kind": "class",
    "is_async": true,
    "framework": "swiftui",
    "limit": 20,
    "format": "json"
  }
}
```

## Description

Searches the symbol index built from SwiftSyntax AST extraction. Finds structs, classes, actors, protocols, functions, and properties by kind and name pattern. Results are ranked by relevance and include document context.

## Parameters

### query (optional)

Symbol name pattern to search for. Supports partial matching.

**Type:** String

**Examples:**
- `"Manager"` - Find symbols containing "Manager"
- `"View"` - Find View-related symbols
- `"fetch"` - Find fetch methods

### kind (optional)

Filter by symbol kind.

**Type:** String

**Values:**
- `"struct"` - Struct declarations
- `"class"` - Class declarations
- `"actor"` - Actor declarations
- `"enum"` - Enum declarations
- `"protocol"` - Protocol declarations
- `"extension"` - Extension declarations
- `"function"` - Function declarations
- `"method"` - Method declarations
- `"property"` - Property declarations
- `"typealias"` - Type alias declarations

### is_async (optional)

Filter to async functions/methods only.

**Type:** Boolean

**Default:** None (returns both sync and async)

### framework (optional)

Filter results to a specific framework.

**Type:** String

**Examples:**
- `"swiftui"` - Only SwiftUI symbols
- `"foundation"` - Only Foundation symbols

### limit (optional)

Maximum number of results to return.

**Type:** Integer

**Default:** 20

**Maximum:** 100

### format (optional)

Output format. Default: `markdown`; use `json` for typed GUI-decodable results.

## Response

Default markdown returns grouped symbol results. `format=json` returns:

```json
{
  "filters": {
    "query": "Manager",
    "kind": "class",
    "is_async": true,
    "framework": "swiftui",
    "limit": 20
  },
  "results": [
    {
      "doc_uri": "apple-docs://swiftui/example",
      "doc_title": "Example",
      "framework": "swiftui",
      "symbol_name": "NetworkManager",
      "symbol_kind": "class",
      "signature": "class NetworkManager",
      "attributes": "@MainActor",
      "conformances": "Sendable",
      "is_async": false,
      "is_public": true
    }
  ]
}
```

## Examples

### Find All Actors

```json
{
  "kind": "actor"
}
```

### Find Async Functions

```json
{
  "is_async": true
}
```

### Find View Structs

```json
{
  "query": "View",
  "kind": "struct"
}
```

### Find Classes in SwiftUI

```json
{
  "kind": "class",
  "framework": "swiftui"
}
```

### Combined Query

```json
{
  "query": "Manager",
  "kind": "class",
  "is_async": true,
  "limit": 10
}
```

## See Also

- [search_property_wrappers](../search_property_wrappers/) - Search by property wrapper usage
- [search_conformances](../search_conformances/) - Search by protocol conformance
- [search_concurrency](../search_concurrency/) - Search concurrency patterns
- `search` - Full-text documentation search

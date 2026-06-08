# search_concurrency

Find Swift concurrency patterns: async/await, actors, Sendable conformances.

## Synopsis

```json
{
  "name": "search_concurrency",
  "arguments": {
    "pattern": "async",
    "framework": "foundation",
    "limit": 20,
    "format": "json"
  }
}
```

## Description

Searches for Swift concurrency patterns in the AST-extracted symbol index. Discover real-world async/await, actor, and Sendable usage in Apple documentation and sample code.

## Parameters

### pattern (required)

Concurrency pattern to search for.

**Type:** String

**Values:**
- `"async"` - Async functions and methods
- `"actor"` - Actor declarations
- `"sendable"` - Sendable conformances
- `"mainactor"` - @MainActor isolated code
- `"task"` - Task-related patterns
- `"asyncsequence"` - AsyncSequence conformances

### framework (optional)

Filter results to a specific framework.

**Type:** String

**Examples:**
- `"foundation"` - Only Foundation samples
- `"swiftui"` - Only SwiftUI samples
- `"swift"` - Only Swift standard library

### limit (optional)

Maximum number of results to return.

**Type:** Integer

**Default:** 20

**Maximum:** 100

### format (optional)

Output format. Default: `markdown`; use `json` for typed GUI-decodable results.

## Response

Default markdown returns grouped concurrency results. `format=json` returns filters plus typed symbol rows:

```json
{
  "filters": {
    "pattern": "async",
    "framework": "foundation",
    "limit": 20
  },
  "results": [
    {
      "doc_uri": "apple-docs://foundation/urlsession",
      "doc_title": "URLSession",
      "framework": "foundation",
      "symbol_name": "data",
      "symbol_kind": "method",
      "signature": "func data(from:) async throws -> (Data, URLResponse)",
      "is_async": true,
      "is_public": true
    }
  ]
}
```

## Examples

### Find Async Functions

```json
{
  "pattern": "async"
}
```

### Find Actor Declarations

```json
{
  "pattern": "actor"
}
```

### Find Sendable Types

```json
{
  "pattern": "sendable"
}
```

### Find @MainActor Code

```json
{
  "pattern": "mainactor"
}
```

### Find Async in Foundation

```json
{
  "pattern": "async",
  "framework": "foundation"
}
```

## Common Use Cases

### Learning Async/Await

```json
{"pattern": "async"}
```

Find real examples of async functions to understand patterns.

### Understanding Actor Isolation

```json
{"pattern": "actor"}
{"pattern": "mainactor"}
```

Find actor declarations and @MainActor usage.

### Finding Thread-Safe Types

```json
{"pattern": "sendable"}
```

Find types that conform to Sendable.

## See Also

- [search_symbols](../search_symbols/) - Search by symbol type and name
- [search_property_wrappers](../search_property_wrappers/) - Search by property wrapper
- [search_conformances](../search_conformances/) - Search by protocol conformance
- `search` - Full-text documentation search

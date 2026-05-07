# search_conformances

Find types by protocol conformance across Apple documentation and sample code.

## Synopsis

```json
{
  "name": "search_conformances",
  "arguments": {
    "protocol": "View",
    "framework": "swiftui",
    "limit": 20
  }
}
```

## Description

Searches the AST-extracted symbol index for types that conform to a specific protocol. Discover how protocols are implemented in Apple's production code.

## Parameters

### protocol (required)

Protocol name to search for conformances.

**Type:** String

**Common protocols:**
- `"View"` - SwiftUI views
- `"Codable"` - Encodable & Decodable
- `"Hashable"` - Hashable types
- `"Equatable"` - Equatable types
- `"Identifiable"` - Types with stable identity
- `"ObservableObject"` - Combine observable objects
- `"Sendable"` - Thread-safe types
- `"AsyncSequence"` - Async sequences
- `"Error"` - Error types
- `"Sequence"` - Sequence types
- `"Collection"` - Collection types

### framework (optional)

Filter results to a specific framework.

**Type:** String

**Examples:**
- `"swiftui"` - Only SwiftUI samples
- `"foundation"` - Only Foundation samples

### limit (optional)

Maximum number of results to return.

**Type:** Integer

**Default:** 20

**Maximum:** 100

## Response

Returns markdown-formatted conformance results:

```markdown
# Conformance Search: View

Found **42** types conforming to View:

## 1. ContentView

- **Document:** Building a SwiftUI App
- **URI:** `samples://swiftui-building...`
- **Type:** struct
- **Line:** 8

```swift
struct ContentView: View {
    var body: some View {
        NavigationStack { ... }
    }
}
```

---

## 2. DetailView
...
```

## Examples

### Find View Conformances

```json
{
  "protocol": "View"
}
```

### Find Codable Types

```json
{
  "protocol": "Codable"
}
```

### Find Sendable Types

```json
{
  "protocol": "Sendable"
}
```

### Find Identifiable Types

```json
{
  "protocol": "Identifiable"
}
```

### Find Views in SwiftUI Framework

```json
{
  "protocol": "View",
  "framework": "swiftui"
}
```

## Common Use Cases

### Learning SwiftUI Patterns

```json
{"protocol": "View"}
```

Find real View implementations to learn SwiftUI patterns.

### Understanding Data Modeling

```json
{"protocol": "Codable"}
{"protocol": "Identifiable"}
{"protocol": "Hashable"}
```

Find how Apple models data in sample apps.

### Finding Error Handling Patterns

```json
{"protocol": "Error"}
```

Find custom error type implementations.

### Finding Observable Patterns

```json
{"protocol": "ObservableObject"}
```

Find pre-Observation ObservableObject implementations.

## See Also

- [search_symbols](../search_symbols/) - Search by symbol type and name
- [search_property_wrappers](../search_property_wrappers/) - Search by property wrapper
- [search_concurrency](../search_concurrency/) - Search concurrency patterns
- `search` (with `source: samples`) - Full-text sample code search

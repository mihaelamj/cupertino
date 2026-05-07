# search_property_wrappers

Find Swift property wrapper usage patterns across documentation and samples.

## Synopsis

```json
{
  "name": "search_property_wrappers",
  "arguments": {
    "wrapper": "Observable",
    "framework": "swiftui",
    "limit": 20
  }
}
```

## Description

Searches for property wrapper usage in the AST-extracted symbol index. Essential for discovering SwiftUI state management patterns and understanding how Apple uses property wrappers in production code.

## Parameters

### wrapper (required)

Property wrapper name to search for. Can include or omit the `@` prefix.

**Type:** String

**Common wrappers:**
- `"State"` or `"@State"` - SwiftUI local state
- `"Binding"` - SwiftUI two-way bindings
- `"StateObject"` - SwiftUI observed object ownership
- `"ObservedObject"` - SwiftUI observed object reference
- `"Observable"` - Swift Observation macro
- `"Environment"` - SwiftUI environment values
- `"EnvironmentObject"` - SwiftUI environment objects
- `"Published"` - Combine published properties
- `"AppStorage"` - UserDefaults-backed storage
- `"MainActor"` - Main actor isolation
- `"Sendable"` - Sendable conformance marker

### framework (optional)

Filter results to a specific framework.

**Type:** String

**Examples:**
- `"swiftui"` - Only SwiftUI samples
- `"combine"` - Only Combine samples

### limit (optional)

Maximum number of results to return.

**Type:** Integer

**Default:** 20

**Maximum:** 100

## Response

Returns markdown-formatted results showing wrapper usage:

```markdown
# Property Wrapper Search: @Observable

Found **8** usages:

## 1. Library.swift

- **Document:** Migrating from ObservableObject to Observable
- **URI:** `samples://swiftui-migrating...`
- **Symbol:** Library (class)
- **Line:** 12

```swift
@Observable final class Library {
    var books: [Book] = []
}
```

---

## 2. Book.swift
...
```

## Examples

### Find @Observable Usage

```json
{
  "wrapper": "Observable"
}
```

### Find @MainActor Usage

```json
{
  "wrapper": "MainActor"
}
```

### Find @State in SwiftUI Samples

```json
{
  "wrapper": "State",
  "framework": "swiftui"
}
```

### Find @Published Properties

```json
{
  "wrapper": "Published",
  "limit": 30
}
```

## Common Use Cases

### Understanding State Management

```json
{"wrapper": "State"}
{"wrapper": "Binding"}
{"wrapper": "StateObject"}
{"wrapper": "ObservedObject"}
```

### Finding Concurrency Patterns

```json
{"wrapper": "MainActor"}
{"wrapper": "Sendable"}
```

### Finding Data Persistence Patterns

```json
{"wrapper": "AppStorage"}
{"wrapper": "SceneStorage"}
```

## See Also

- [search_symbols](../search_symbols/) - Search by symbol type and name
- [search_conformances](../search_conformances/) - Search by protocol conformance
- [search_concurrency](../search_concurrency/) - Search concurrency patterns
- `search` (with `source: samples`) - Full-text sample code search

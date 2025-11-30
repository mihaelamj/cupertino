# list_frameworks

List all available frameworks in the documentation index with document counts.

## Synopsis

```json
{
  "name": "list_frameworks",
  "arguments": {}
}
```

## Description

Returns a list of all frameworks that have been indexed, along with the number of documents in each framework. Useful for discovering what documentation is available and for filtering `search_docs` queries.

## Parameters

None.

## Response

Returns a markdown table of frameworks sorted by document count:

```markdown
# Available Frameworks

Total documents: **22,044**

| Framework | Documents |
|-----------|----------:|
| `swiftui` | 5,853 |
| `swift` | 2,814 |
| `uikit` | 1,906 |
| `appkit` | 1,316 |
| `foundation` | 1,219 |
| `swift-org` | 501 |
| `swift-evolution` | 429 |
| `coregraphics` | 387 |
| `avfoundation` | 356 |
| ... | ... |
```

## Example

### Request

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "list_frameworks",
    "arguments": {}
  }
}
```

### Response Usage

Use the framework names from the response to filter `search_docs` queries:

```json
{
  "name": "search_docs",
  "arguments": {
    "query": "View",
    "framework": "swiftui"
  }
}
```

## Common Frameworks

| Framework | Content |
|-----------|---------|
| `swiftui` | SwiftUI views, modifiers, and layouts |
| `swift` | Swift standard library |
| `uikit` | UIKit for iOS/iPadOS |
| `appkit` | AppKit for macOS |
| `foundation` | Foundation framework |
| `swift-org` | Swift.org documentation |
| `swift-evolution` | Swift Evolution proposals |
| `combine` | Reactive programming |
| `coregraphics` | Core Graphics drawing |
| `avfoundation` | Audio/video |

## Use Cases

### Discover Available Content

Before searching, check what frameworks are indexed:

1. Call `list_frameworks` to see available frameworks
2. Use framework names to filter `search_docs` queries
3. Get more relevant results by narrowing scope

### Verify Index Status

If searches return no results, check if the framework is indexed:

```json
{"name": "list_frameworks", "arguments": {}}
```

If total documents is 0, run `cupertino save` to build the index.

## See Also

- [search_docs](../search_docs/) - Search documentation
- [read_document](../read_document/) - Read document content

# list_frameworks

List frameworks with document counts. Alias for [`list(source, level: 1)`](../list/); kept for
existing clients.

## Synopsis

```json
{
  "name": "list_frameworks",
  "arguments": { "source": "apple-archive" }
}
```

## Description

Returns the frameworks for a source, with the number of documents in each. Useful for discovering
what documentation is available and for filtering `search` queries.

Source-aware (#1311): pass `source` to list THAT source's own frameworks (for example
`apple-archive` lists its 14 archive frameworks, not apple-docs'). With no `source`, it falls back
to the global merged list across every indexed source (the historical behaviour), so callers that
never passed a source are unchanged. For new clients, prefer [`list`](../list/).

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `source` | No | Source whose frameworks to list. Omit for the global merged list (legacy behaviour). |

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

Use the framework names from the response to filter `search` queries:

```json
{
  "name": "search",
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
2. Use framework names to filter `search` queries
3. Get more relevant results by narrowing scope

### Verify Index Status

If searches return no results, check if the framework is indexed:

```json
{"name": "list_frameworks", "arguments": {}}
```

If total documents is 0, run `cupertino setup` to install the pre-built bundle, or `cupertino save --all` if you are rebuilding locally.

## See Also

- `search` - Search documentation
- `search` (with `source: hig`) - Search Human Interface Guidelines
- [read_document](../read_document/) - Read document content

# read_document

Read a document by URI in JSON or Markdown format.

## Synopsis

```json
{
  "name": "read_document",
  "arguments": {
    "uri": "apple-docs://swiftui/documentation_swiftui_view",
    "format": "json"
  }
}
```

## Description

Retrieves the full content of a document from the search index. Use URIs from `search_docs` results. Documents can be returned in JSON (structured) or Markdown (rendered) format.

## Parameters

### uri (required)

Document URI from search results.

**Type:** String

**Format:** `{scheme}://{path}`

**Schemes:**
- `apple-docs://` - Apple Developer documentation
- `swift-evolution://` - Swift Evolution proposals

**Examples:**
- `apple-docs://swiftui/documentation_swiftui_view`
- `apple-docs://swift/documentation_swift_actor`
- `swift-evolution://SE-0001`
- `swift-evolution://SE-0302`

### format (optional)

Output format for the document content.

**Type:** String

**Values:**
- `json` (default) - Full structured document data
- `markdown` - Rendered markdown content

**Recommendation:** Use `json` for AI agents - it provides structured, machine-readable data.

## Response Formats

### JSON Format (default)

Returns the full `StructuredDocumentationPage` as JSON:

```json
{
  "title": "View",
  "kind": "Protocol",
  "module": "SwiftUI",
  "url": "https://developer.apple.com/documentation/swiftui/view",
  "declaration": "protocol View",
  "abstract": "A type that represents part of your app's user interface...",
  "overview": "You create custom views by declaring types that conform to View...",
  "discussion": null,
  "codeExamples": [
    {
      "code": "struct MyView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}",
      "language": "swift",
      "caption": "Creating a simple view"
    }
  ],
  "parameters": [],
  "returnValue": null,
  "conformsTo": ["Sendable"],
  "platforms": [
    {"name": "iOS", "version": "13.0+"},
    {"name": "macOS", "version": "10.15+"}
  ],
  "seeAlso": [...],
  "rawMarkdown": "# View\n\nA type that represents..."
}
```

#### JSON Fields

| Field | Type | Description |
|-------|------|-------------|
| `title` | String | Document title |
| `kind` | String? | Type: Protocol, Structure, Class, Function, etc. |
| `module` | String? | Framework/module name |
| `url` | String? | Original Apple documentation URL |
| `declaration` | String? | Code declaration |
| `abstract` | String? | Brief description |
| `overview` | String? | Extended description |
| `discussion` | String? | Discussion section |
| `codeExamples` | Array | Code snippets with language and caption |
| `parameters` | Array | Function/method parameters |
| `returnValue` | String? | Return value description |
| `conformsTo` | Array | Protocol conformances |
| `platforms` | Array | Platform availability |
| `seeAlso` | Array | Related documentation links |
| `rawMarkdown` | String? | Full rendered markdown |

### Markdown Format

Returns rendered markdown content:

```markdown
# View

A type that represents part of your app's user interface and provides modifiers that you use to configure views.

## Overview

You create custom views by declaring types that conform to the View protocol...

## Declaration

```swift
protocol View
```

## Topics

### Creating a View
...
```

## Examples

### Read in JSON Format (Recommended)

```json
{
  "uri": "apple-docs://swift/documentation_swift_actor",
  "format": "json"
}
```

### Read in Markdown Format

```json
{
  "uri": "apple-docs://swiftui/documentation_swiftui_view",
  "format": "markdown"
}
```

### Read Swift Evolution Proposal

```json
{
  "uri": "swift-evolution://SE-0302",
  "format": "json"
}
```

## Workflow

### Typical Search-Then-Read Pattern

1. **Search for documentation:**
   ```json
   {"name": "search_docs", "arguments": {"query": "Actors Swift concurrency"}}
   ```

2. **Extract URI from results:**
   ```
   URI: apple-docs://swift/documentation_swift_actor
   ```

3. **Read the document:**
   ```json
   {"name": "read_document", "arguments": {"uri": "apple-docs://swift/documentation_swift_actor"}}
   ```

## Error Handling

### Document Not Found

If the URI doesn't exist in the index:

```json
{
  "error": {
    "code": -32602,
    "message": "Invalid argument 'uri': Document not found: apple-docs://invalid/uri"
  }
}
```

**Solution:** Verify the URI from `search_docs` results.

### Invalid URI Format

If the URI format is incorrect:

```json
{
  "error": {
    "code": -32602,
    "message": "Invalid argument 'uri': Invalid resource URI: malformed-uri"
  }
}
```

**Solution:** Use URIs exactly as returned by `search_docs`.

## See Also

- [search_docs](../search_docs/) - Search for documents
- [list_frameworks](../list_frameworks/) - List available frameworks

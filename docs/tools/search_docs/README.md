# search_docs

Full-text search across all indexed documentation.

## Synopsis

```json
{
  "name": "search_docs",
  "arguments": {
    "query": "Actors Swift concurrency",
    "source": "apple-docs",
    "framework": "swift",
    "limit": 10
  }
}
```

## Description

Searches the documentation index using SQLite FTS5 with BM25 ranking. Returns a ranked list of matching documents with URIs that can be used with `read_document` to retrieve full content.

## Parameters

### query (required)

Search keywords to find in documentation.

**Type:** String

**Examples:**
- `"SwiftUI View"` - Find SwiftUI View documentation
- `"Actors Swift concurrency"` - Find actor-related concurrency docs
- `"async await"` - Find async/await documentation
- `"URLSession download"` - Find URLSession download methods

**Search Tips:**
- Use multiple keywords for better results
- More specific queries return more relevant results
- Framework names can help narrow results (e.g., "SwiftUI animation")

### source (optional)

Filter results to a specific documentation source.

**Type:** String

**Default:** None (searches all sources)

**Values:**
- `"apple-docs"` - Apple Developer Documentation
- `"swift-book"` - The Swift Programming Language book
- `"swift-org"` - Swift.org documentation
- `"swift-evolution"` - Swift Evolution proposals
- `"packages"` - Swift Package documentation
- `"apple-archive"` - Apple Archive legacy programming guides

### framework (optional)

Filter results to a specific framework (applies to `apple-docs` source).

**Type:** String

**Default:** None (searches all frameworks)

**Examples:**
- `"swiftui"` - Only SwiftUI documentation
- `"foundation"` - Only Foundation framework
- `"swift"` - Only Swift standard library

Use `list_frameworks` to see available framework names.

### language (optional)

Filter results by programming language.

**Type:** String

**Default:** None (searches all languages)

**Values:**
- `"swift"` - Swift documentation
- `"objc"` - Objective-C documentation

### limit (optional)

Maximum number of results to return.

**Type:** Integer

**Default:** 20

**Maximum:** 100

### include_archive (optional)

Include Apple Archive legacy programming guides in search results.

**Type:** Boolean

**Default:** `false` (archive excluded by default)

Archive documentation is excluded by default to prioritize modern documentation. Set to `true` to include legacy guides like Core Animation Programming Guide, Quartz 2D Programming Guide, etc. These contain foundational knowledge not available in modern docs.

**Note:** You can also search archive exclusively using `source: "apple-archive"`.

## Response

Returns markdown-formatted search results:

```markdown
# Search Results for "Actors Swift concurrency"

Found **15** results:

## 1. Actor | Apple Developer Documentation

- **Framework:** `swift`
- **URI:** `apple-docs://swift/documentation_swift_actor`
- **Score:** 12.45
- **Words:** 1,234

A type whose mutable state is protected from concurrent access...

---

## 2. Actors | Apple Developer Documentation
...
```

### Result Fields

| Field | Description |
|-------|-------------|
| Framework | The framework containing this document |
| URI | Document identifier for use with `read_document` |
| Score | BM25 relevance score (higher = more relevant) |
| Words | Document word count |
| Summary | Brief excerpt from the document |

## Examples

### Basic Search

```json
{
  "query": "SwiftUI"
}
```

### Source-Filtered Search

```json
{
  "query": "async",
  "source": "swift-book"
}
```

### Framework-Filtered Search

```json
{
  "query": "View",
  "framework": "swiftui"
}
```

### Limited Results

```json
{
  "query": "async await",
  "limit": 5
}
```

### Complex Query

```json
{
  "query": "Actors Swift concurrency isolation",
  "framework": "swift",
  "limit": 10
}
```

### Include Archive Guides

```json
{
  "query": "Core Animation layers",
  "include_archive": true
}
```

### Search Archive Only

```json
{
  "query": "CALayer",
  "source": "apple-archive"
}
```

## Common Use Cases

### Finding API Documentation

```json
{"query": "URLSession dataTask"}
{"query": "SwiftUI NavigationStack"}
{"query": "Combine Publisher"}
```

### Finding Concepts

```json
{"query": "Swift concurrency actors"}
{"query": "SwiftUI state management"}
{"query": "memory management ARC"}
```

### Finding Swift Evolution Proposals

```json
{"query": "SE-0001"}
{"query": "async await proposal"}
{"query": "Swift Evolution actors"}
```

## See Also

- [read_document](../read_document/) - Read document content by URI
- [list_frameworks](../list_frameworks/) - List available frameworks

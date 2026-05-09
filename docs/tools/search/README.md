# search

Unified full-text search across every indexed Cupertino source: Apple Developer Documentation, sample code, Human Interface Guidelines, Apple Archive, Swift Evolution, swift.org, the Swift Book, and Swift package metadata.

## Synopsis

```json
{
  "name": "search",
  "arguments": {
    "query": "SwiftUI Tab"
  }
}
```

## Description

The default mode runs a fan-out across every available database in parallel and merges the rankings via reciprocal-rank fusion (k=60). With the `source` parameter, the search is scoped to a single source and returns that source's per-source view shape. Replaces the pre-#239 per-source MCP tools (`search_docs`, `search_hig`, `search_samples`, `search_all`), which were collapsed into this one. Same fan-out behavior and ranking pipeline as the [`search` CLI command](../../commands/search/).

## Parameters

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `query` | string | yes | Search query string. Lexical (BM25F) — does not do fuzzy or vector matching. |
| `source` | string | no | Limit results to a single source. Values: `all`, `apple-docs`, `samples`, `apple-sample-code`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`, `packages`. |
| `framework` | string | no | Framework filter, e.g. `swiftui`, `foundation`, `uikit`. Case-insensitive. |
| `language` | string | no | Language filter for the Swift.org sources (typically `swift`). |
| `include_archive` | boolean | no | When `source` is not specified, include Apple Archive (legacy programming guides) in the fan-out. |
| `limit` | integer | no | Maximum number of results to return. Default `20`. |
| `min_ios` | string | no | Minimum iOS version filter, e.g. `17.0`. Drops results whose minimum-iOS availability annotation is higher. |
| `min_macos` | string | no | Minimum macOS version filter, e.g. `14.0`. |
| `min_tvos` | string | no | Minimum tvOS version filter, e.g. `17.0`. |
| `min_watchos` | string | no | Minimum watchOS version filter, e.g. `10.0`. |
| `min_visionos` | string | no | Minimum visionOS version filter, e.g. `1.0`. |

## Response

### Fan-out mode (no `source` argument)

Returns a JSON object with the unified shape:

```json
{
  "candidates": [
    {
      "uri": "apple-docs://swiftui/Tab",
      "title": "Tab",
      "framework": "swiftui",
      "rank": 1,
      "summary": "A view that creates a tab in a tab view."
    }
  ],
  "contributingSources": ["apple-docs", "swift-evolution", "packages"],
  "question": "SwiftUI Tab"
}
```

`contributingSources` lists which sources contributed at least one candidate; sources with zero hits are dropped from the list.

### Per-source mode (`source` set)

Returns the per-source view shape. Different sources return different shapes — see the source-by-source breakdown:

- `apple-docs`: top-level array of doc objects with `availability`, `framework`, `id`, `rank`
- `samples`: `{files: [{filename, path, projectId, rank, snippet}]}`
- `hig`: `{count, query, results: [{title, uri, summary, availability}]}`
- `apple-archive` / `swift-evolution` / `swift-org` / `swift-book`: source-specific shapes
- `packages`: `{candidates, contributingSources: ["packages"], question}` (matches the unified shape; routes to packages.db)

If you parse JSON, expect different keys per source. The default fan-out is the most consistent option when you don't need source-specific fields.

## Examples

### Fan-out (most common)

Request:
```json
{
  "name": "search",
  "arguments": {
    "query": "SwiftUI Tab"
  }
}
```

### Scoped to one source

```json
{
  "name": "search",
  "arguments": {
    "query": "SwiftUI Tab",
    "source": "apple-docs"
  }
}
```

### Filtered by framework + iOS version

```json
{
  "name": "search",
  "arguments": {
    "query": "Tab",
    "framework": "swiftui",
    "min_ios": "17.0"
  }
}
```

### Filtered by source + limit

```json
{
  "name": "search",
  "arguments": {
    "query": "concurrency",
    "source": "swift-evolution",
    "limit": 5
  }
}
```

## See Also

- CLI equivalent: [`cupertino search`](../../commands/search/) — same fan-out + same ranking; same `--source` semantics
- [list_frameworks](../list_frameworks/) — discover what `framework` values are valid
- [read_document](../read_document/) — fetch a result's full document by URI

## Migration note (#239)

Pre-#239, the MCP surface had four separate tools: `search_docs`, `search_hig`, `search_samples`, `search_all`. They were collapsed into this single `search` tool with a `source` parameter. AI agents using the old tool names should switch to `search` with the appropriate `source` argument.

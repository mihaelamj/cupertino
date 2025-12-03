# search_samples

Search Apple sample code projects and source files.

## Synopsis

```json
{
  "name": "search_samples",
  "arguments": {
    "query": "SwiftUI animation",
    "limit": 10
  }
}
```

## Description

Searches the sample code index using SQLite FTS5. Returns matching projects and source files with relevance ranking.

## Parameters

### query (required)

Search keywords to find in sample code.

**Type:** String

**Examples:**
- `"SwiftUI animation"` - Find SwiftUI animation samples
- `"ARKit"` - Find ARKit sample projects
- `"Core ML vision"` - Find machine learning samples
- `"async await"` - Find concurrency examples

### limit (optional)

Maximum number of results to return.

**Type:** Integer

**Default:** 20

## Response

Returns matching sample code projects and files.

## Examples

### Basic Search

```json
{
  "query": "SwiftUI"
}
```

### Limited Results

```json
{
  "query": "Metal shaders",
  "limit": 5
}
```

## See Also

- [list_samples](../list_samples/) - List all sample projects
- [read_sample](../read_sample/) - Read sample README
- [read_sample_file](../read_sample_file/) - Read specific source file

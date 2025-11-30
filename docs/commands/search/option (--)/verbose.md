# --verbose, -v

Show extended information in search results

## Synopsis

```bash
cupertino search <query> --verbose
cupertino search <query> -v
```

## Description

Enables verbose output mode, which includes additional metadata for each search result: summary, relevance score, and word count.

## Default

`false` (compact output)

## Examples

### Verbose Text Output
```bash
cupertino search "View" --verbose
```

Output:
```
Found 20 result(s) for 'View':

[1] View | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/documentation_swiftui_view
    Summary: A type that represents part of your app's user interface.
    Score: 15.23
    Word Count: 2345

[2] ViewBuilder | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/documentation_swiftui_viewbuilder
    Summary: A custom parameter attribute that constructs views from closures.
    Score: 12.87
    Word Count: 1892
```

### Verbose JSON Output
```bash
cupertino search "View" --format json --verbose --limit 1
```

Output:
```json
[
  {
    "filePath": "/Users/user/.cupertino/docs/swiftui/documentation_swiftui_view.md",
    "framework": "swiftui",
    "score": 15.23,
    "source": "apple-docs",
    "summary": "A type that represents part of your app's user interface.",
    "title": "View | Apple Developer Documentation",
    "uri": "apple-docs://swiftui/documentation_swiftui_view",
    "wordCount": 2345
  }
]
```

### Verbose Markdown Output
```bash
cupertino search "View" --format markdown --verbose --limit 1
```

Output:
```markdown
# Search Results for 'View'

Found 1 result(s).

## 1. View | Apple Developer Documentation

- **Source:** apple-docs
- **Framework:** swiftui
- **URI:** `apple-docs://swiftui/documentation_swiftui_view`
- **Score:** 15.23
- **Word Count:** 2345

> A type that represents part of your app's user interface.
```

## Additional Fields

| Field | Description |
|-------|-------------|
| Summary | Brief description of the document content |
| Score | BM25 relevance score (higher = more relevant) |
| Word Count | Number of words in the document |

## Use Cases

- **Relevance analysis**: Compare scores to understand ranking
- **Content preview**: Summary shows what the document contains
- **Document size**: Word count helps estimate reading time
- **Debugging**: Verify search is returning expected results

## Notes

- Summary is extracted from document metadata
- Score is the BM25 relevance score (SQLite FTS5)
- Word count reflects indexed content length
- Verbose mode increases output size significantly

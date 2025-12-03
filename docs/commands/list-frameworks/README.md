# list-frameworks

List available frameworks with document counts.

## Synopsis

```bash
cupertino list-frameworks [--format <format>] [--search-db <path>]
```

## Description

Lists all frameworks in the search index with their document counts. Use this to discover what frameworks are available for filtering in search queries.

## Options

### --format

Output format: `text` (default), `json`, or `markdown`.

### --search-db

Path to search database. Defaults to `~/.cupertino/search-index.sqlite`.

## Examples

```bash
# List all frameworks
cupertino list-frameworks

# Output as JSON
cupertino list-frameworks --format json

# Output as Markdown table
cupertino list-frameworks --format markdown
```

## Sample Output

```
Available Frameworks
Total: 156 frameworks, 23456 documents

  swiftui: 1234 documents
  foundation: 987 documents
  uikit: 876 documents
  ...
```

## See Also

- [search](../search/) - Filter by framework
- [save](../save/) - Build the search index

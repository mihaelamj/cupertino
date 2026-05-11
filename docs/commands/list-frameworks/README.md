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

Path to search database. Defaults to `~/.cupertino/search.db`.

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
Available Frameworks (402 total, 277640 documents):

  swiftui: 6500 documents
  foundation: 4200 documents
  uikit: 3800 documents
  ...
```

Counts depend on which corpus has been saved to `search.db`. Numbers above snapshot the v1.0 bundle; your local DB will vary.

## See Also

- [search](../search/) - Filter by framework
- [save](../save/) - Build the search index

# list-frameworks

List available frameworks with document counts.

## Synopsis

```bash
cupertino list-frameworks [--format <format>]
```

## Description

Lists all frameworks in the search index with their document counts. Use this to discover what frameworks are available for filtering in search queries.

## Options

### --format

Output format: `text` (default), `json`, or `markdown` / `md`.

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
Available Frameworks (412 total, 351873 documents):
(counts cover the framework-scoped sources: apple-docs + apple-archive)

  kernel: 39396 documents
  matter: 24320 documents
  swift: 17466 documents
  ...
```

Post per-source-DB split (#1036/#1037), `list-frameworks` sums only the sources whose `capabilities.operations` declare `.listFrameworks`: today apple-docs (`apple-documentation.db`) and apple-archive (`apple-archive.db`). The other per-source DBs (HIG / swift-evolution / swift-org / swift-book) do not carry framework partitioning, so their rows are not in this total. The numbers above are from the v1.3.0 bundle (351,505 apple-docs + 368 apple-archive); your local DB will vary, and the scope line lists whichever framework-scoped sources are present.

## See Also

- [search](../search/) - Filter by framework
- [save](../save/) - Build the search index

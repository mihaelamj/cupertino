# cupertino save

Build FTS5 search index from crawled documentation

## Synopsis

```bash
cupertino save [options]
```

## Description

The `index` command builds a Full-Text Search (FTS5) SQLite database from previously crawled documentation. This enables fast, efficient searching across all downloaded documentation.

## Options

- [--docs-dir](docs-dir.md) - Directory containing crawled documentation
- [--evolution-dir](evolution-dir.md) - Directory containing Swift Evolution proposals
- [--metadata-file](metadata-file.md) - Path to metadata.json file
- [--search-db](search-db.md) - Output path for search database
- [--clear](clear.md) - Clear existing index before building

## Examples

### Build Index from Default Locations
```bash
cupertino save
```

### Build Index from Custom Documentation
```bash
cupertino save --docs-dir ./my-docs --search-db ./my-search.db
```

### Rebuild Index (Clear and Rebuild)
```bash
cupertino save --clear
```

### Index Multiple Sources
```bash
cupertino save --docs-dir ./apple-docs --evolution-dir ./evolution
```

## Output

The indexer creates:
- **search.db** - SQLite database with FTS5 index
- Indexed fields:
  - Page titles
  - Full content
  - Framework names
  - URL paths
  - Metadata

## Search Features

The FTS5 index supports:
- **Full-text search** - Search across all documentation content
- **BM25 ranking** - Relevance-based result ordering
- **Framework filtering** - Narrow results by framework
- **Snippet generation** - Show matching context
- **Fast queries** - Sub-second search across thousands of pages

## Notes

- Requires crawled documentation (run `cupertino fetch` first)
- Uses SQLite FTS5 for optimal search performance
- Index size is typically ~10-20% of total documentation size
- Supports incremental updates (without `--clear`)
- Compatible with MCP server for AI integration

## Next Steps

After building the search index, you can start the MCP server:

```bash
cupertino
```

Or explicitly:

```bash
cupertino serve
```

The server will automatically detect and use the search index to provide search tools to AI assistants.

## See Also

- [../mcp/](../mcp/) - MCP server commands
- [../crawl/](../crawl/) - Download documentation

# cupertino save

Build FTS5 search index from crawled documentation

## Synopsis

```bash
cupertino save [options]
```

## Description

The `save` command builds a Full-Text Search (FTS5) SQLite database from previously fetched documentation. This enables fast, efficient searching across all downloaded documentation.

## Options

- [--remote](option%20%28--%29/remote/) - **Stream from GitHub** (instant setup, no local files)
- [--base-dir](option%20%28--%29/base-dir.md) - Base directory (auto-fills all directories from standard structure)
- [--docs-dir](option%20%28--%29/docs-dir.md) - Directory containing crawled documentation
- [--evolution-dir](option%20%28--%29/evolution-dir.md) - Directory containing Swift Evolution proposals
- [--swift-org-dir](option%20%28--%29/swift-org-dir.md) - Directory containing Swift.org documentation
- [--packages-dir](option%20%28--%29/packages-dir.md) - Directory containing package READMEs
- [--metadata-file](option%20%28--%29/metadata-file.md) - Path to metadata.json file
- [--search-db](option%20%28--%29/search-db.md) - Output path for search database
- [--clear](option%20%28--%29/clear.md) - Clear existing index before building

## Examples

### Quick Setup (Recommended)
Stream documentation from GitHub - no crawling needed:
```bash
cupertino save --remote
```

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

- **Remote mode** (`--remote`): No prerequisites - streams from GitHub
- **Local mode**: Requires crawled documentation (run `cupertino fetch` first)
- Uses SQLite FTS5 for optimal search performance
- Index size is typically ~10-20% of total documentation size
- Remote mode is resumable if interrupted
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

- [search](../search/) - Search documentation from CLI
- [serve](../serve/) - Start MCP server
- [fetch](../fetch/) - Download documentation
- [doctor](../doctor/) - Check server health

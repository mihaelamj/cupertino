# search.db - FTS5 Search Index Database

SQLite database with Full-Text Search (FTS5) index for fast documentation searches.

## Location

**Default**: `~/.cupertino/search.db`

## Created By

```bash
cupertino save
```

## Purpose

- **Fast Full-Text Search** - Sub-second queries across thousands of pages
- **BM25 Ranking** - Relevance-based result ordering
- **Framework Filtering** - Search within specific frameworks
- **Snippet Generation** - Show matching context
- **MCP Integration** - Power AI documentation search

## Database Structure

SQLite database with FTS5 virtual table:

```sql
CREATE VIRTUAL TABLE documents USING fts5(
    title,           -- Page title
    content,         -- Full page content
    framework,       -- Framework name
    url,             -- Source URL
    path,            -- File path
    tokenize = 'porter unicode61'
);
```

## Fields

- **title** - Page title (e.g., "Array - Swift Standard Library")
- **content** - Full Markdown content
- **framework** - Framework name (e.g., "swift", "swiftui")
- **url** - Original documentation URL
- **path** - Local file path

## Size

Typically ~10-20% of source documentation size:

| Documentation Size | Index Size |
|-------------------|------------|
| 100 MB | ~15 MB |
| 500 MB | ~75 MB |
| 1 GB | ~150 MB |

## Usage

### Query with SQL
```bash
# Search for "async"
sqlite3 ~/.cupertino/search.db "SELECT title, framework FROM documents WHERE documents MATCH 'async' LIMIT 10"

# Search within SwiftUI
sqlite3 ~/.cupertino/search.db "SELECT title FROM documents WHERE documents MATCH 'view' AND framework = 'swiftui' LIMIT 10"

# Get snippets
sqlite3 ~/.cupertino/search.db "SELECT snippet(documents, 1, '<b>', '</b>', '...', 32) FROM documents WHERE documents MATCH 'concurrency'"
```

### Use with MCP
```bash
# Start MCP server (uses search.db automatically)
cupertino-mcp serve
```

The MCP server provides search capabilities to AI assistants like Claude.

### Use in Swift
```swift
import CupertinoSearch

let searchIndex = SearchIndex(databasePath: URL(fileURLWithPath: "~/.cupertino/search.db"))
let results = try await searchIndex.search(query: "async await")
```

## Search Features

### Full-Text Search
- Searches across all content
- Supports phrase queries: `"exact phrase"`
- Boolean operators: `term1 AND term2`, `term1 OR term2`
- Prefix search: `asyn*` matches "async", "asynchronous"

### BM25 Ranking
- Relevance-based result ordering
- Term frequency and inverse document frequency
- Better results than simple matching

### Framework Filtering
```sql
-- Only SwiftUI results
WHERE framework = 'swiftui'

-- Multiple frameworks
WHERE framework IN ('swift', 'foundation')
```

### Snippets
```sql
-- Show matching context with highlighting
snippet(documents, 1, '<mark>', '</mark>', '...', 32)
```

## Rebuilding Index

```bash
# Clear and rebuild from scratch
cupertino save --clear

# Update with new documentation
cupertino save --no-clear
```

## Customizing Location

```bash
# Use custom database path
cupertino save --search-db ./my-search.db
```

## Technical Details

- **Engine**: SQLite FTS5
- **Tokenizer**: Porter stemming + Unicode61
- **Format**: Standard SQLite database file
- **Compatibility**: Any SQLite 3.9.0+ client
- **Performance**: Optimized for fast queries on large datasets

## Used By

- `cupertino-mcp serve` - MCP server for AI integration
- Direct SQL queries
- Custom search applications via CupertinoSearch library

## Notes

- Standard SQLite file - can be queried with any SQLite tool
- FTS5 provides production-grade full-text search
- Rebuilding is fast (minutes for full Apple docs)
- Can be backed up like any SQLite database
- Thread-safe for concurrent reads

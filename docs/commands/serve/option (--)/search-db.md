# --search-db

Path to search database for serving search tools

## Synopsis

```bash
cupertino serve --search-db <path>
```

## Description

Specifies the SQLite search database file that the MCP server will use to provide search tool functionality. When available, enables `search_docs` and `list_frameworks` tools for AI assistants.

## Default

`~/.cupertino/search.db`

## Examples

### Serve with Default Database
```bash
cupertino serve
```

### Serve with Custom Database
```bash
cupertino serve --search-db ./my-search.db
```

### Serve Specific Database
```bash
cupertino serve --search-db ~/.cupertino/apple-search.db
```

### Absolute Path
```bash
cupertino serve --search-db /Users/username/Documents/search.db
```

## Server Behavior

**When database exists:**
```
🚀 Cupertino MCP Server starting...
   Apple docs: ~/.cupertino/docs
   Evolution: ~/.cupertino/swift-evolution
   Search DB: ~/.cupertino/search.db
✅ Search enabled (index found)
   Waiting for client connection...
```

Server provides:
- `search_docs(query, limit, framework)` - Full-text search
- `list_frameworks()` - List all indexed frameworks

**When database missing:**
```
🚀 Cupertino MCP Server starting...
   Apple docs: ~/.cupertino/docs
   Evolution: ~/.cupertino/swift-evolution
   Search DB: ~/.cupertino/search.db
ℹ️  Search index not found at: ~/.cupertino/search.db
   Tools will not be available. Run 'cupertino save' to enable search.
   Waiting for client connection...
```

Server still runs, but search tools are unavailable.

**When database corrupted:**
```
⚠️  Failed to load search index: unable to open database file
   Tools will not be available. Run 'cupertino save' to create the index.
```

## Provided Tools

### search_docs

Search documentation with full-text indexing:

```json
{
  "name": "search_docs",
  "description": "Search Apple documentation and Swift Evolution proposals",
  "inputSchema": {
    "query": "string (required)",
    "limit": "number (optional, default: 10)",
    "framework": "string (optional)"
  }
}
```

### list_frameworks

List all indexed frameworks:

```json
{
  "name": "list_frameworks",
  "description": "List all available frameworks in the index"
}
```

## Database Requirements

- Must be SQLite database
- Must have FTS5 schema (created by `cupertino save`)
- Should contain indexed documentation
- Readable by server process

## Performance Impact

- Database opened once at startup
- Queries execute in <100ms typically
- Memory-mapped for efficiency
- No disk writes (read-only)

## Server Startup Requirements

The serve command requires at least ONE of:
- Apple documentation (`--docs-dir`)
- Swift Evolution proposals (`--evolution-dir`)
- Search database (`--search-db`)

Search database is **optional** - server will run without it, but search tools won't be available.

## Notes

- Tilde (`~`) expansion is supported
- Database must be created by `cupertino save`
- Used by `SearchToolProvider` for tool functionality
- If missing, server runs but tools disabled
- Changes to database require server restart
- Compatible with Claude Desktop and other MCP clients
- Enables semantic search for AI assistants
- Optional but highly recommended for best experience

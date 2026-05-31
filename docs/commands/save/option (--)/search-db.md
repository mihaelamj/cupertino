# --search-db

Output path for the apple-docs database (legacy flag name)

## Synopsis

```bash
cupertino save --search-db <path>
```

## Description

Specifies where to create the SQLite FTS5 search database.

## Default

`~/.cupertino/apple-documentation.db`

## Examples

### Use Default Location
```bash
cupertino save --source apple-docs
```

### Custom Database Path
```bash
cupertino save --search-db ./apple-documentation.db
```

### Per-source databases (built automatically)
```bash
# Each source writes its own DB; --search-db only overrides the apple-docs DB path.
cupertino save --source apple-docs   # → apple-documentation.db
cupertino save --source swift-org    # → swift-org.db
cupertino save --source hig          # → hig.db
```

## Database Format

- SQLite database file
- Uses FTS5 full-text search extension
- Typically 10-20% of source documentation size
- Can be queried with any SQLite client

## File Size Examples

| Documentation Size | Index Size |
|-------------------|------------|
| 100 MB Markdown | ~15 MB |
| 500 MB Markdown | ~75 MB |
| 1 GB Markdown | ~150 MB |

## Notes

- File is created if it doesn't exist
- Overwrites existing file if `--clear` is used
- Can be used with MCP server for search
- Standard SQLite database - readable by any SQLite tool

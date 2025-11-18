# --search-db

Output path for search database

## Synopsis

```bash
cupertino index --search-db <path>
```

## Description

Specifies where to create the SQLite FTS5 search database.

## Default

`~/.cupertino/search.db`

## Examples

### Use Default Location
```bash
cupertino index
```

### Custom Database Path
```bash
cupertino index --search-db ./my-search.db
```

### Separate Database per Documentation Type
```bash
# Apple docs
cupertino index --docs-dir ~/.cupertino/docs --search-db ~/.cupertino/apple-search.db

# Swift.org
cupertino index --docs-dir ~/.cupertino/swift-org --search-db ~/.cupertino/swift-search.db
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

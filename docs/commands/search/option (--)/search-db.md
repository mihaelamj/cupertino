# --search-db

Path to the search database file

## Synopsis

```bash
cupertino search <query> --search-db <path>
```

## Description

Specifies a custom path to the SQLite FTS5 search database. Use this to search a different database than the default location.

## Default

`~/.cupertino/search.db`

## Examples

### Use Custom Database
```bash
cupertino search "View" --search-db ~/my-docs/search.db
```

### Absolute Path
```bash
cupertino search "SwiftUI" --search-db /Users/username/custom/search.db
```

### Relative Path
```bash
cupertino search "Array" --search-db ./local-search.db
```

## Use Cases

- **Multiple indexes**: Maintain separate indexes for different documentation sets
- **Testing**: Use a test database without affecting production
- **Shared indexes**: Point to a shared network database
- **Development**: Test against custom-built indexes

## Creating a Custom Database

```bash
# Fetch documentation to custom location
cupertino fetch --type docs --output-dir ~/custom-docs

# Build index with custom database path
cupertino save --base-dir ~/custom-docs --search-db ~/custom-docs/search.db

# Search using custom database
cupertino search "View" --search-db ~/custom-docs/search.db
```

## Notes

- Tilde (`~`) expansion is supported
- Database must exist (created by `cupertino save`)
- Database must be on local filesystem (SQLite limitation)
- If database not found, command exits with error message
- Same database format as used by `cupertino serve`

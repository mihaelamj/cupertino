# --search-db

Path to the search database file

## Synopsis

```bash
cupertino read <uri> --search-db <path>
```

## Description

Specifies a custom path to the SQLite FTS5 search database. Use this to read documents from a different database than the default location.

## Default

`~/.cupertino/search.db`

## Examples

### Use Custom Database
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --search-db ~/my-docs/search.db
```

### Absolute Path
```bash
cupertino read "swift-evolution://SE-0302" --search-db /Users/username/custom/search.db
```

### Relative Path
```bash
cupertino read "apple-docs://swift/documentation_swift_array" --search-db ./local-search.db
```

## Use Cases

- **Multiple indexes**: Read from separate indexes for different documentation sets
- **Testing**: Use a test database without affecting production
- **Shared indexes**: Point to a shared network database
- **Development**: Test against custom-built indexes

## Creating a Custom Database

```bash
# Fetch documentation to custom location
cupertino fetch --type docs --output-dir ~/custom-docs

# Build index with custom database path
cupertino save --base-dir ~/custom-docs --search-db ~/custom-docs/search.db

# Read using custom database
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --search-db ~/custom-docs/search.db
```

## Notes

- Tilde (`~`) expansion is supported
- Database must exist (created by `cupertino save`)
- Database must be on local filesystem (SQLite limitation)
- If database not found, command exits with error message
- Same database format as used by `cupertino serve` and `cupertino search`

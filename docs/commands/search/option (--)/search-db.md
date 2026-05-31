# --search-db

Legacy debug knob: override the docs database path

## Synopsis

```bash
cupertino search <query> --search-db <path>
```

## Description

Overrides the docs database path. Post-#1037 each docs source owns its own per-source DB (`apple-documentation.db`, `hig.db`, `apple-archive.db`, `swift-evolution.db`, `swift-org.db`, `swift-book.db`), resolved through the registry under the base directory; this legacy flag overrides that resolution.

## Default

Resolved per-source via the registry (no single `search.db`).

## Examples

### Use Custom Database
```bash
cupertino search "View" --search-db ~/my-docs/apple-documentation.db
```

### Absolute Path
```bash
cupertino search "SwiftUI" --search-db /Users/username/custom/apple-documentation.db
```

### Relative Path
```bash
cupertino search "Array" --search-db ./apple-documentation.db
```

## Use Cases

- **Multiple indexes**: Maintain separate indexes for different documentation sets
- **Testing**: Use a test database without affecting production
- **Shared indexes**: Point to a shared network database
- **Development**: Test against custom-built indexes

## Creating a Custom Database

```bash
# Fetch documentation to custom location
cupertino fetch --source apple-docs --output-dir ~/custom-docs

# Build index with custom database path
cupertino save --source apple-docs --base-dir ~/custom-docs --search-db ~/custom-docs/apple-documentation.db

# Search using custom database
cupertino search "View" --search-db ~/custom-docs/apple-documentation.db
```

## Notes

- Tilde (`~`) expansion is supported
- Database must exist (created by `cupertino save`)
- Database must be on local filesystem (SQLite limitation)
- If database not found, command exits with error message
- Same database format as used by `cupertino serve`

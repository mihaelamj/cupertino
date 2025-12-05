# --search-db (with --remote)

Output path for the search database when using remote mode.

## Usage

```bash
cupertino save --remote --search-db ~/custom/search.db
```

## Behavior in Remote Mode

When combined with `--remote`, the `--search-db` option specifies where to write the search database.

### How It Works

1. Remote indexer streams documentation from GitHub
2. Parses JSON and extracts searchable content
3. Writes directly to the specified SQLite database
4. No intermediate files are created

### SQLite Requirement

The database path must be on a **local filesystem**. SQLite does not work reliably on network drives (NFS/SMB).

## Examples

```bash
# Custom database location
cupertino save --remote --search-db /Volumes/FastSSD/search.db
```

```bash
# Project-specific database
cupertino save --remote --search-db ./project-docs.db
```

```bash
# Combined with base-dir (state file separate from database)
cupertino save --remote --base-dir ~/.cupertino --search-db ~/databases/apple.db
```

## Default

If not specified:
- Defaults to `{base-dir}/search.db`
- If `--base-dir` is also not specified, defaults to `~/.cupertino/search.db`

## Database Size

| Content | Approximate Size |
|---------|------------------|
| Full documentation | ~150-200 MB |
| Minimal (evolution only) | ~5 MB |

## See Also

- [--remote](../README.md) - Parent option documentation
- [--base-dir](base-dir.md) - Custom state file location
- [--search-db (local mode)](../../search-db.md) - Behavior without --remote

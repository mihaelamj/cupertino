# --base-dir (with --remote)

Base directory for state file storage when using remote mode.

## Usage

```bash
cupertino save --remote --base-dir ~/custom-cupertino
```

## Behavior in Remote Mode

When combined with `--remote`, the `--base-dir` option controls:

1. **State file location**: `{base-dir}/remote-save-state.json`
2. **Default apple-docs database path**: `{base-dir}/apple-documentation.db` (unless `--search-db` is specified)

### Important Difference

In **local mode** (without `--remote`), `--base-dir` determines where to look for crawled documentation files.

In **remote mode**, documentation is streamed from GitHub, so `--base-dir` only affects:
- Where the resume state file is saved
- The default location for the search database

## Examples

```bash
# Use custom base directory for state and database
cupertino save --remote --base-dir ~/my-docs

# Creates:
#   ~/my-docs/remote-save-state.json
#   ~/my-docs/apple-documentation.db
```

```bash
# Combine with custom search-db
cupertino save --remote --base-dir ~/my-docs --search-db ~/databases/apple-documentation.db

# Creates:
#   ~/my-docs/remote-save-state.json
#   ~/databases/apple-documentation.db
```

## Default

If not specified, defaults to `~/.cupertino/`.

## See Also

- [--remote](../README.md) - Parent option documentation
- [--search-db](search-db.md) - Custom database path
- [--base-dir (local mode)](../../base-dir.md) - Behavior without --remote

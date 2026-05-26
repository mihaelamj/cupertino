# --search-db

Override the apple-docs database path.

## Synopsis

```bash
cupertino list-frameworks --search-db <path>
```

## Description

Override the default apple-docs database location. Post-#1037 per-source DB split, framework partitioning lives in `apple-documentation.db` (resolved through the production source registry as `AppleDocsSource.destinationDB.filename`); this flag points the lookup at a different file. Apple-archive framework rows are still read from the canonical `apple-archive.db` location; the override applies to apple-docs only.

## Default

`~/.cupertino/apple-documentation.db` (or the override resolved via `cupertino.config.json` next to the running binary; see `Shared.BinaryConfig`).

## Examples

### Run against a development DB

```bash
cupertino list-frameworks --search-db ~/.cupertino-dev/apple-documentation.db
```

### Run against a snapshot DB

```bash
cupertino list-frameworks --search-db /tmp/apple-documentation.snapshot.db
```

## Notes

- Read-only access, `list-frameworks` doesn't modify the DB.
- If the file doesn't exist, the command exits with a missing-DB error. A legacy `search.db` sitting next to the expected file is reported in the diagnostic and migrated by `cupertino setup`.
- `apple-archive.db` is opened separately at its canonical location; this flag does not override it.

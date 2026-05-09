# --search-db

Path to the search database

## Synopsis

```bash
cupertino list-frameworks --search-db <path>
```

## Description

Override the default `search.db` location. Useful when running against a non-default base directory (e.g., a `~/.cupertino-dev/` development instance) or against a manually-relocated DB.

## Default

`~/.cupertino/search.db` (or the override resolved via `cupertino.config.json` next to the running binary; see `Shared.BinaryConfig`).

## Examples

### Run against a development DB
```bash
cupertino list-frameworks --search-db ~/.cupertino-dev/search.db
```

### Run against a snapshot DB
```bash
cupertino list-frameworks --search-db /tmp/search.snapshot.db
```

## Notes

- Read-only access — `list-frameworks` doesn't modify the DB.
- If the file doesn't exist, the command exits with a missing-DB error.

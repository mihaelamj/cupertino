# --sample-db

Path to the sample-index database

## Synopsis

```bash
cupertino list-samples --sample-db <path>
```

## Description

Override the default `apple-sample-code.db` location. Useful when running against a non-default base directory (e.g., a `~/.cupertino-dev/` development instance).

## Default

`~/.cupertino/apple-sample-code.db` (or the override resolved via `cupertino.config.json` next to the running binary).

## Examples

### Run against a development DB
```bash
cupertino list-samples --sample-db ~/.cupertino-dev/apple-sample-code.db
```

### Run against a snapshot
```bash
cupertino list-samples --sample-db /tmp/samples.snapshot.db
```

## Notes

- Read-only access.
- If the file doesn't exist, the command exits with a missing-DB error.

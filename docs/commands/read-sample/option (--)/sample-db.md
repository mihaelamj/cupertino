# --sample-db

Path to the sample-index database

## Synopsis

```bash
cupertino read-sample <project-id> --sample-db <path>
```

## Description

Override the default `apple-sample-code.db` location. Useful when running against a non-default base directory (e.g., a `~/.cupertino-dev/` development instance).

## Default

`~/.cupertino/apple-sample-code.db` (or the override resolved via `cupertino.config.json` next to the running binary).

## Examples

### Read against a development DB
```bash
cupertino read-sample building-a-document-based-app-with-swiftui \
  --sample-db ~/.cupertino-dev/apple-sample-code.db
```

## Notes

- Read-only access.
- If the file doesn't exist, the command exits with a missing-DB error.

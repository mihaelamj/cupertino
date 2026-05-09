# --db

Path to the packages database

## Synopsis

```bash
cupertino package-search <question> --db <path>
```

## Description

Override the default `packages.db` location. Useful when running against a non-default base directory (e.g., a `~/.cupertino-dev/` development instance).

## Default

`~/.cupertino/packages.db` (or the override resolved via `cupertino.config.json` next to the running binary).

## Examples

### Run against a development DB
```bash
cupertino package-search "swift-nio event loop" --db ~/.cupertino-dev/packages.db
```

## Notes

- Read-only access.
- `package-search` is a hidden subcommand intended as a packages-only shortcut for the same smart-query path that `cupertino search --source packages` runs.

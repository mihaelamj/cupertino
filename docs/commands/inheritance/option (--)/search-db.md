# --search-db

Override the apple-docs database path.

## Synopsis

```bash
cupertino inheritance <symbol> --search-db <path>
```

## Description

A debug knob to point the walk at a specific apple-docs database file instead of
the one resolved through the production source registry. Post-#1037 each docs
source owns its own per-source database; the inheritance edges live in the
apple-docs database, named `apple-documentation.db` as of the v1.3.0 per-source
split.

## Default

The registry-resolved apple-docs database (`apple-documentation.db` under the
configured base directory).

## Example

```bash
cupertino inheritance UIButton --search-db ~/.cupertino-dev/apple-documentation.db
```

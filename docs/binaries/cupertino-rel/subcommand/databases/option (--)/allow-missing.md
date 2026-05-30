# --allow-missing

Allow publishing even when some registry-derived databases are absent from the base directory.

## Synopsis

```bash
cupertino-rel databases --allow-missing
```

## Description

The bundled database set is derived from the production source registry: one
file per enabled source's declared `destinationDB`. By default the command
refuses to publish if any of those databases is missing from the base
directory, because a partial release would silently ship an incomplete corpus.

Passing `--allow-missing` downgrades each absent database to a warning and drops
it from the bundle, letting a partial release proceed. Use it only when you
intend to ship a subset (for example, a docs-only refresh while a large
per-source database is still rebuilding).

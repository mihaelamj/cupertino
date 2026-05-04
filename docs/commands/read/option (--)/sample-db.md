# --sample-db

Path to sample-code database (`samples.db`)

## Synopsis

```bash
cupertino read <identifier> --sample-db <path>
```

## Description

Override the default `~/.cupertino/samples.db` location. Used when `--source samples` (or auto-source dispatching to samples) needs to query.

## Default

`~/.cupertino/samples.db`

## Example

```bash
cupertino read my-sample-id --source samples --sample-db ~/dev/samples.db
```

## Notes

- Tilde (`~`) expansion supported.
- Honours `Shared.BinaryConfig.baseDirectory` overrides (#211).
- Missing file → `notFound` error for the samples backend.

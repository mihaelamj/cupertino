# --sample-db

Path to sample-code database (`apple-sample-code.db`)

## Synopsis

```bash
cupertino search <query> --sample-db <path>
```

## Description

Override the default `~/.cupertino/apple-sample-code.db` location. Used when `--source samples` (or default fan-out) needs to query sample-code.

## Default

`~/.cupertino/apple-sample-code.db`

## Example

```bash
cupertino search "@Observable" --source samples --sample-db ~/custom/apple-sample-code.db
```

## Notes

- Tilde (`~`) expansion supported.
- Honours `Shared.BinaryConfig.baseDirectory` overrides (#211).
- Missing file → samples source skipped in fan-out, with an info log.

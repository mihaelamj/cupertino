# --sample-db

Path to sample-code database (`samples.db`)

## Synopsis

```bash
cupertino search <query> --sample-db <path>
```

## Description

Override the default `~/.cupertino/samples.db` location. Used when `--source samples` (or default fan-out) needs to query sample-code.

## Default

`~/.cupertino/samples.db`

## Example

```bash
cupertino search "@Observable" --source samples --sample-db ~/custom/samples.db
```

## Notes

- Tilde (`~`) expansion supported.
- Honours `Shared.BinaryConfig.baseDirectory` overrides (#211).
- Missing file → samples source skipped in fan-out, with an info log.

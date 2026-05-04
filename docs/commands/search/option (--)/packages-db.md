# --packages-db

Path to the packages database (`packages.db`)

## Synopsis

```bash
cupertino search <query> --packages-db <path>
```

## Description

Override the default `~/.cupertino/packages.db` location. Used in fan-out mode (no `--source`) and with `--source packages`. ([#239](https://github.com/mihaelamj/cupertino/issues/239))

## Default

`~/.cupertino/packages.db`

## Example

```bash
cupertino search "swift testing fixtures" --packages-db ~/custom/packages.db
```

## Notes

- Tilde (`~`) expansion supported.
- Honours `Shared.BinaryConfig.baseDirectory` overrides (#211).
- Missing file → that source is skipped in fan-out, with an info log.

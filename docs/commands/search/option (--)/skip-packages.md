# --skip-packages

Skip the packages source in fan-out mode

## Synopsis

```bash
cupertino search <query> --skip-packages
```

## Description

Excludes the `packages.db`-backed source from fan-out search. Useful when packages.db is missing/stale or when you want only docs + samples. ([#239](https://github.com/mihaelamj/cupertino/issues/239))

## Default

`false`

## Example

```bash
cupertino search "navigationStack vs navigationView" --skip-packages
```

## Notes

- Fan-out mode only.
- Combine with `--skip-docs` / `--skip-samples` to scope further.

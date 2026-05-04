# --skip-samples

Skip the samples source in fan-out mode

## Synopsis

```bash
cupertino search <query> --skip-samples
```

## Description

Excludes the `samples.db`-backed source from fan-out search. Useful when samples.db is missing/stale or when you only care about docs + packages. ([#239](https://github.com/mihaelamj/cupertino/issues/239))

## Default

`false`

## Example

```bash
cupertino search "Observable macro" --skip-samples
```

## Notes

- Fan-out mode only.
- Combine with `--skip-docs` / `--skip-packages` to scope further.

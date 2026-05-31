# --skip-docs

Skip every apple-docs-backed source in fan-out mode

## Synopsis

```bash
cupertino search <query> --skip-docs
```

## Description

In fan-out mode (no `--source`), excludes apple-docs, apple-archive, hig, swift-evolution, swift-org, and swift-book from the search. Useful when the apple-docs database is locked (e.g. another process running `cupertino save --source apple-docs`) or when you only want package + sample results. ([#239](https://github.com/mihaelamj/cupertino/issues/239))

## Default

`false`

## Example

```bash
cupertino search "swift-nio EventLoopGroup" --skip-docs
```

## Notes

- Fan-out mode only. Ignored when `--source` is set.
- Combine with `--skip-packages` / `--skip-samples` to scope further.

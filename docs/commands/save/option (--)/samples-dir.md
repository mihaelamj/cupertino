# --samples-dir

Sample-code source directory for `--samples`

## Synopsis

```bash
cupertino save --samples --samples-dir <path>
```

## Description

Override the default `~/.cupertino/sample-code/` source location. The samples indexer expects extracted sample-code zips at this path. ([#231](https://github.com/mihaelamj/cupertino/issues/231))

## Default

`~/.cupertino/sample-code/`

## Example

```bash
cupertino save --samples --samples-dir ~/Downloads/sample-code
```

## Notes

- Tilde (`~`) expansion supported.
- Honours `Shared.BinaryConfig.baseDirectory` overrides (#211).
- If the directory is missing, the samples scope is skipped with an info log (when running multi-scope) or errors (when only `--samples` was passed).

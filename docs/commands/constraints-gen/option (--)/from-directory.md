# --from-directory

Recursively scan a directory for `*.symbols.json` files.

## Synopsis

```bash
cupertino-constraints-gen generate --from-directory <dir> -o <output>
```

## Description

Collects every `*.symbols.json` under `<dir>` recursively, including cross-module extension graphs such as `SwiftUI@Foundation.symbols.json`. Mutually exclusive with the positional `<symbol-graph-files>` list: pass one or the other, not both.

If `<dir>` is missing or contains no `*.symbols.json`, the command exits 1 with instructions for producing symbol graphs, rather than writing an empty table.

## Type

String (directory path). Optional, but exactly one of `--from-directory` or the positional file list must be supplied.

## Example

```bash
cupertino-constraints-gen generate \
  --from-directory ~/Developer/public/cupertino-symbolgraphs \
  -o apple-constraints.json
```

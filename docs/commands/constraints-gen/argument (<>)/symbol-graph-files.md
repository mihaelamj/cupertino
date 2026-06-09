# <symbol-graph-files>

Explicit list of `.symbols.json` files to parse.

## Synopsis

```bash
cupertino-constraints-gen generate <symbol-graph-files> ... -o <output>
cupertino-constraints-gen conformances <symbol-graph-files> ... -o <output>
```

## Description

Zero or more `swift symbolgraph-extract` output files, passed as positional arguments. Mutually exclusive with [`--from-directory`](../option%20%28--%29/from-directory.md): supply explicit files OR a directory to scan, not both. When neither is supplied the command exits 1.

For `generate`, when multiple files emit entries for the same `docURI`, the last file wins; pass files in the desired override order. For `conformances`, entries are merged by `docURI`.

## Type

List of strings (file paths). Optional (use `--from-directory` instead to scan a tree).

## Example

```bash
cupertino-constraints-gen generate \
  /tmp/SwiftUI.symbols.json /tmp/Foundation.symbols.json \
  -o apple-constraints.json

cupertino-constraints-gen conformances \
  /tmp/SwiftUI.symbols.json /tmp/Foundation.symbols.json \
  -o apple-conformances.json
```

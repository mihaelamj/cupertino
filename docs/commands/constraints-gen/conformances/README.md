# conformances

Parse Swift symbol-graph JSON and emit `apple-conformances.json`.

## Synopsis

```bash
cupertino-constraints-gen conformances [<symbol-graph-files> ...] [--from-directory <dir>] -o <output>
```

## Description

`conformances` is the conformance sibling of `generate`. It reads SDK symbol graphs, extracts `conformsTo` / `inheritsFrom` relationships keyed by Cupertino document URI, and writes the `apple-conformances.json` table consumed by the conformance enrichment pass.

The command refuses to write an empty table. A 0-entry `apple-conformances.json` would silently strip SDK conformance facts from apple-docs, samples, and packages, so missing, unreadable, or fully unparseable inputs exit non-zero and leave the output path untouched.

## Options

- [`<symbol-graph-files>`](../argument%20%28%3C%3E%29/symbol-graph-files.md): explicit list of `.symbols.json` files.
- [`--from-directory`](../option%20%28--%29/from-directory.md): recursively scan a directory for `*.symbols.json`.
- [`--output` / `-o`](../option%20%28--%29/output.md): output JSON path for `apple-conformances.json` (required).
- [`--verbose`](../option%20%28--%29/verbose.md): print per-file entry counts.

## Example

```bash
cupertino-constraints-gen conformances \
  --from-directory ~/Developer/public/cupertino-symbolgraphs \
  -o apple-conformances.json
```

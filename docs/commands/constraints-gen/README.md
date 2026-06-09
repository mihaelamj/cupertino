# cupertino-constraints-gen

Generate the Apple-type generic-constraints table (`apple-constraints.json`) from Swift symbol graphs.

## Synopsis

```bash
cupertino-constraints-gen generate <symbol-graph-files> ... -o <output>
cupertino-constraints-gen generate --from-directory <dir> -o <output>
cupertino-constraints-gen conformances <symbol-graph-files> ... -o <output>
cupertino-constraints-gen conformances --from-directory <dir> -o <output>
```

## Description

`cupertino-constraints-gen` is a standalone maintainer tool (a separate binary from `cupertino`). It parses `swift symbolgraph-extract` JSON and emits the filtered constraint table consumed by the indexer's iteration-3 static-constraints enrichment pass ([#759](https://github.com/mihaelamj/cupertino/issues/759)). That table is the single Apple-wide source of truth the apple-docs, samples, and packages constraint passes all read; it is regenerated when Apple ships a new SDK.

DocC markdown spells out only a fraction of Apple's generic constraints; the symbol graphs cover the full API surface. That is why the table is symbolgraph-derived, not scraped from the docs.

### `generate` subcommand

Reads one or more `.symbols.json` files and writes the constraint table to `--output`. Two input modes, mutually exclusive:

- **Explicit files:** positional [`<symbol-graph-files>`](argument%20%28%3C%3E%29/symbol-graph-files.md) paths.
- **Directory scan:** [`--from-directory <dir>`](option%20%28--%29/from-directory.md) recursively collects every `*.symbols.json` under the directory, including cross-module extension graphs such as `SwiftUI@Foundation.symbols.json`.

### Refuses to write a degraded table

The command hard-fails (exit 1) with remediation instructions instead of writing a partial or empty `apple-constraints.json` when:

- `--from-directory` resolves to a missing or empty directory (no `*.symbols.json` found), or
- every input file is unreadable or unparseable, so 0 constraints are extracted.

A 0-entry table would silently strip Apple constraint enrichment from every consuming DB (apple-docs, samples, packages), and the loss is only visible by inspecting the DB afterwards. The error text names how to produce symbol graphs and re-run.

### `conformances` subcommand

Reads the same `.symbols.json` inputs and writes `apple-conformances.json`, the conformance sibling of `apple-constraints.json`. The conformance table feeds the SDK conformance enrichment pass for apple-docs, samples, and packages. It refuses to write a 0-entry table for the same reason as `generate`: an empty artifact would silently remove SDK conformance facts from every consuming DB.

## Options

- [`<symbol-graph-files>`](argument%20%28%3C%3E%29/symbol-graph-files.md): explicit list of `.symbols.json` files.
- [`--from-directory`](option%20%28--%29/from-directory.md): recursively scan a directory for `*.symbols.json`.
- [`--output` / `-o`](option%20%28--%29/output.md): output JSON path for the table (required).
- [`--verbose`](option%20%28--%29/verbose.md): print per-file entry counts as files are processed.

## Examples

### From a directory of symbol graphs

```bash
cupertino-constraints-gen generate \
  --from-directory ~/Developer/public/cupertino-symbolgraphs \
  -o apple-constraints.json
```

### From explicit files

```bash
cupertino-constraints-gen generate \
  /tmp/SwiftUI.symbols.json /tmp/Foundation.symbols.json \
  -o apple-constraints.json
```

### Conformance table

```bash
cupertino-constraints-gen conformances \
  --from-directory ~/Developer/public/cupertino-symbolgraphs \
  -o apple-conformances.json
```

### Producing symbol graphs first

```bash
swift symbolgraph-extract -module-name SwiftUI -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path)" -output-dir /tmp/symbolgraphs
cupertino-constraints-gen generate --from-directory /tmp/symbolgraphs -o apple-constraints.json
```

## Exit Codes

- **0:** table written (count + byte size printed to stdout).
- **1:** no usable symbol graphs (missing or empty directory, or 0 constraints extracted). Nothing is written.

## See Also

- [Symbol Graph Corpus pipeline](../../symbolgraph-corpus.md): the full chain (generate the corpus, build the table, where each artifact lives).
- [save](../save/): consumes `apple-constraints.json` during the constraints enrichment pass.
- [setup](../setup/): downloads the pre-built `apple-constraints.json` for end users (who never run this tool).

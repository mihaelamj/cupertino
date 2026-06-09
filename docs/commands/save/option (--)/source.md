# --source

Source id to build (repeatable). Replaces the pre-#1037 `--docs / --packages / --samples` triplet with per-source granularity.

## Synopsis

```bash
cupertino save --source <id> [--source <id>]...
```

## Description

Selects which source's database `cupertino save` will rebuild. Pass `--source <id>` multiple times to build several sources. Mutually exclusive with `--all`; at least one of `--source` or `--all` is required (bare `cupertino save` with no scope flag is a usage error post-#1037).

## Valid source ids

| id | DB target |
|---|---|
| `apple-docs` | `apple-documentation.db` |
| `swift-evolution` | `swift-evolution.db` |
| `hig` | `hig.db` |
| `apple-archive` | `apple-archive.db` |
| `swift-org` | `swift-org.db` |
| `swift-book` | `swift-book.db` |
| `samples` | `apple-sample-code.db` (BOTH the Sample.Index rich schema AND SampleCodeSource FTS rows; one DB, two table tracks per #1037) |
| `packages` | `packages.db` (standalone PackagesService pipeline) |

### Aliases

`apple-sample-code` is accepted as an alias for `samples` (matches the `cupertino fetch --source apple-sample-code` shape so the two commands take the same id).

## Examples

```bash
# Build just the Apple Developer Documentation DB.
cupertino save --source apple-docs

# Build apple-documentation.db + hig.db.
cupertino save --source apple-docs --source hig

# Build samples (writes both rich + FTS tracks to apple-sample-code.db).
cupertino save --source samples
```

## Dispatch

`--source <id>` narrows the docs runner to ONLY the destination DB whose providers include that id.

- `--source apple-docs` builds `apple-documentation.db` alone.
- `--source hig` builds `hig.db` alone (and analogously for `swift-evolution`, `apple-archive`).
- `--source swift-org` builds `swift-org.db`; `--source swift-book` builds `swift-book.db`. They are separate source databases post-#1038/#1093.
- `--source samples` (or `--source apple-sample-code` alias) writes to `apple-sample-code.db` via BOTH the standalone `Sample.Index.Builder` pipeline (rich schema: projects + files + file_symbols + imports) AND the docs runner's `SampleCodeSource` group (FTS rows: docs_metadata + docs_fts). One file, two table tracks per #1037.
- `--source packages` runs the standalone `Indexer.PackagesService` against `packages.db` (not via the docs runner; PackagesSource is excluded from `groupedByDestinationDB`).

Multiple `--source` values build the union of their destinations. `--all` builds every source's DB.

## Related

- `--all` – build every source's DB
- `cupertino fetch --source <id>` – download a source's raw corpus before `save`
- `cupertino doctor` – inspect per-source DB state

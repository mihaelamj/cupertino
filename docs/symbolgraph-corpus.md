# Symbol Graph Corpus and `apple-constraints.json` Pipeline

How the Apple SDK symbol-graph corpus is generated, where it is used, and where each artifact in the chain must live. This is the input side of enrichment #9 (Constraint Resolution) and #10 (Constraint Propagation) in [enrichment-inventory.md](enrichment-inventory.md).

## The chain at a glance

```
Xcode SDKs ──(cupertino-symbolgraphs-gen)──▶ *.symbols.json corpus
   corpus ──(cupertino-constraints-gen generate)──▶ apple-constraints.json
   apple-constraints.json ──(cupertino save)──▶ generic_constraints columns
                                                  in apple-documentation.db /
                                                  apple-sample-code.db / packages.db
```

Three repos take part:

- **`cupertino-symbolgraphs`** (producer): owns the generator + the published corpus.
- **`cupertino`** (this repo): owns the consumer tooling (`AppleConstraintsKit`, `cupertino-constraints-gen`) and the `save` enrichment that reads `apple-constraints.json`.
- **`cupertino-docs`** (distribution): hosts the committed `apple-constraints.json` that `cupertino setup` downloads.

## How to generate

`apple-constraints.json` is regenerated when Apple ships a new SDK (Xcode update), a new framework appears in the apple-docs corpus, or a tracked framework is deprecated. Two steps.

### Step 1: obtain the symbol-graph corpus

The corpus is the set of `*.symbols.json` files emitted by `xcrun swift symbolgraph-extract`, one per Apple module, unioned across platforms (macOS first, then iOS / watchOS / visionOS / tvOS fallback for frameworks absent on macOS). The v0.1.1 corpus is 269 modules / 532 `.symbols.json` (canonical + cross-module extension graphs), ~96 MB zipped.

**Option A: download the published corpus (download-first, fast).** The corpus ships as a GitHub Release on `cupertino-symbolgraphs`, one zip per Swift version. It is NOT in any git tree.

```bash
cd <cupertino-symbolgraphs>
gh release download v0.1.1 --repo mihaelamj/cupertino-symbolgraphs --dir corpus
unzip -o corpus/corpus-v0.1.1.zip -d corpus
```

**Option B: regenerate from the active Xcode (GH-free).** Use when Xcode / the SDKs changed.

```bash
cd <cupertino-symbolgraphs>
swift run cupertino-symbolgraphs-gen --output corpus
# defaults: arm64-apple-macos15, falling back to arm64-apple-ios18 /
# arm64_32-apple-watchos11 / arm64-apple-xros2 / appletvos for modules not on
# macOS. Per-platform --<os>-sdk-path / --<os>-target flags override; set an
# SDK path empty to disable that platform's fallback.
```

Either way the corpus lands in the gitignored `corpus/` dir (see "Where it should be").

### Step 2: build the table

```bash
cd <cupertino>/Packages
swift build --product cupertino-constraints-gen
.build/debug/cupertino-constraints-gen generate \
  --from-directory <cupertino-symbolgraphs>/corpus \
  -o apple-constraints.json
```

`cupertino-constraints-gen` keeps only `conformance` + `superclass` constraints (drops `sameType` + layout), maps each symbol-graph identity to an `apple-docs://` URI, and writes the filtered table. It **hard-fails (exit 1) rather than writing a degraded table** when the directory holds no `*.symbols.json` or 0 constraints are extracted (see [docs/commands/constraints-gen](commands/constraints-gen/README.md)). The v0.1.1 corpus produces 61,040 entries across 227 frameworks.

### Step 3: place it for a save, or publish it

- For a local `cupertino save`: put `apple-constraints.json` in the save's base directory and point `save` at it with `--base-dir`:

  ```bash
  cp apple-constraints.json <baseDir>/apple-constraints.json
  cupertino save --source apple-docs --base-dir <baseDir>   # or --all
  ```

  `--base-dir` is where `save` writes the per-source DBs and reads `apple-constraints.json` from (finer per-DB overrides: `--samples-db`, `--metadata-file`). Never target the brew base `~/.cupertino`; use a dev base such as `~/.cupertino-dev`.
- For distribution: commit it to `cupertino-docs` (root), which is what `cupertino setup` downloads into the user's base dir.

## Where it is used

`apple-constraints.json` (not the raw corpus) is the runtime input. Consumers:

- **`cupertino save`** reads `<baseDir>/apple-constraints.json`. The declarative enrichment-input preflight (`Search.EnrichmentInputPreflight`) hard-fails before indexing if it is absent and a selected source declares it (apple-docs / samples / packages, via `SourceDefinition.requiredEnrichmentInputs`), unless `--allow-degraded-enrichment` is passed. `AppleConstraintsKit.Table` loads it; the `constraints` / `hierarchy` / `samples-apple-constraints` / `packages-apple-constraints` passes stamp `generic_constraints` onto `doc_symbols` / `file_symbols` / `package_symbols`.
- **`cupertino setup`** downloads it from `https://raw.githubusercontent.com/mihaelamj/cupertino-docs/main/apple-constraints.json` into `<baseDir>/apple-constraints.json` so end users get it without running the generator.

The raw symbol-graph corpus is used ONLY by `cupertino-constraints-gen` (and the `cupertino-symbolgraphs-audit` validator). Nothing in the `cupertino` runtime reads `*.symbols.json` directly.

## Where it should be

| Artifact | Canonical location | In git? | Distributed via |
|---|---|---|---|
| `*.symbols.json` corpus | `cupertino-symbolgraphs/corpus/` (working), `output/` | **No** (gitignored: `*.symbols.json`, `/corpus/`, `/output/`) | GitHub Releases on `cupertino-symbolgraphs`, one zip per Swift version |
| `manifest.json` (corpus manifest) | alongside the corpus | the *last-published* manifest is committed to `cupertino-symbolgraphs`; the regenerated copy is gitignored | with the corpus zip |
| `apple-constraints.json` (derived table) | `cupertino-docs/apple-constraints.json` (distribution); `<baseDir>/apple-constraints.json` (runtime) | **Yes**, committed to `cupertino-docs` | `cupertino setup` raw-github fetch |
| `generic_constraints` columns (enrichment output) | per-source DBs (`apple-documentation.db` / `apple-sample-code.db` / `packages.db`) | No (DBs ship via GitHub Releases) | `cupertino setup` DB bundle |

Rule of thumb: **the corpus is gitignored and released; the derived table is committed and distributed.** A `*.symbols.json` file must never be committed to any repo, and `apple-constraints.json` must never be derived on the fly from a remote source (download-first, then build locally).

## See also

- [docs/commands/constraints-gen](commands/constraints-gen/README.md): the `cupertino-constraints-gen` consumer CLI + its empty-corpus guard.
- [enrichment-inventory.md](enrichment-inventory.md): enrichment #9 (Constraint Resolution) and #10 (Constraint Propagation), which this pipeline feeds.
- `cupertino-symbolgraphs/README.md`: the generator's coverage model + when-to-regenerate triggers.

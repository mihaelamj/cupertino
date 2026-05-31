# Default Options Behavior

Post-#1037 `cupertino save` requires an explicit scope flag (`--source <id>` repeatable, or `--all`). Bare `cupertino save` is a usage error. This page documents the default-value behaviour for every other option.

## Synopsis

```bash
cupertino save --all
# or
cupertino save --source <id> [--source <id>]...
```

## Default Behavior

`cupertino save --all` runs the **full pipeline**: every source's DB is built if its source data is present. Each source reads from its standard directory under `~/.cupertino/` and writes to its standard DB path. With explicit `--source <id>`, only the selected scope(s) fire (current internal dispatch is bucket-level; see [source.md](source.md) Notes for the per-source-id dispatch refactor that lands in a follow-up commit).

Equivalent to specifying every default explicitly:

```bash
cupertino save --all \
  --base-dir ~/.cupertino \
  --search-db ~/.cupertino/apple-documentation.db \
  --samples-db ~/.cupertino/apple-sample-code.db
```

(There is no `--packages-db` flag yet; the packages-scope DB path is derived from `--base-dir`.)

## Default Option Values

| Option | Default | Description |
|--------|---------|-------------|
| `--base-dir` | `~/.cupertino` | Base directory; auto-fills every other directory option from standard structure |
| `--docs-dir` | `~/.cupertino/docs` | Apple docs corpus |
| `--evolution-dir` | `~/.cupertino/swift-evolution` | Swift Evolution proposals corpus |
| `--swift-org-dir` | `~/.cupertino/swift-org` | Swift.org corpus |
| `--packages-dir` | `~/.cupertino/packages` | Extracted package archives |
| `--archive-dir` | `~/.cupertino/archive` | Apple Archive legacy guides corpus |
| `--samples-dir` | `~/.cupertino/sample-code` | Extracted sample-code projects |
| `--metadata-file` | `~/.cupertino/docs/metadata.json` | Crawler-side metadata index |
| `--search-db` | `~/.cupertino/apple-documentation.db` | apple-docs database output path (legacy flag name) |
| `--samples-db` | `~/.cupertino/apple-sample-code.db` | apple-sample-code.db output path |
| `--source <id>` | (no default; required unless `--all` is passed) | Source id to build, repeatable |
| `--all` | `false` (no default; required unless `--source` is passed) | Build every source's DB |
| `--clear` | `false` | Incremental build (default); `--clear` to wipe and rebuild |
| `--remote` | `false` | Stream from GitHub instead of reading local files. Mutually exclusive with `--source` / `--all`. |
| `--force` | `false` | Re-index every sample under `--source samples` even if unchanged |
| `--yes` / `-y` | `false` | Skip the preflight summary + confirmation prompt |

## Build Behavior

Under `cupertino save --all` (or `--source` covering all three buckets), `cupertino save`:

1. **Loads `BinaryConfig`**, resolves `defaultBaseDirectory` (overridable via `cupertino.config.json` next to the binary).
2. **Runs the preflight**, prints the resolved scope set, source directories, output DB paths, and asks for confirmation (skipped when stdin isn't a TTY or `--yes` is set; #232).
3. **Builds the per-source documentation databases** (`apple-documentation.db`, `hig.db`, `apple-archive.db`, `swift-evolution.db`, `swift-org.db`, `swift-book.db`; docs bucket), iterates `--docs-dir`, `--evolution-dir`, `--swift-org-dir`, `--archive-dir`, `--metadata-file`. Missing directories are skipped with an info-level log (not a hard error).
4. **Builds `packages.db`** (packages bucket), iterates `--packages-dir/<owner>/<repo>/`. Skipped if no extracted archives exist.
5. **Builds `apple-sample-code.db`** (samples bucket), iterates `--samples-dir`. Always wipes-and-rebuilds (the samples-side schema doesn't yet support partial updates).

Steps 3-5 are independent. Failures in one scope don't block the others.

## Directory Requirements

None of the source directories are individually required. Each scope is best-effort: missing directory → scope skipped with a log line. The command exits with success if at least one scope completed; with an error if every scope was skipped (no source data anywhere).

## Expected Directory Structure

```
~/.cupertino/
├── docs/                          # --docs-dir       (docs scope)
│   ├── metadata.json              # --metadata-file
│   ├── Foundation/
│   └── SwiftUI/
├── swift-evolution/               # --evolution-dir  (docs scope)
├── swift-org/                     # --swift-org-dir  (docs scope)
├── archive/                       # --archive-dir    (docs scope)
├── hig/                           # docs scope
├── packages/                      # --packages-dir   (packages.db scope)
│   └── <owner>/<repo>/...
├── sample-code/                   # --samples-dir    (apple-sample-code.db scope)
│   └── <project_id>/
├── apple-documentation.db         # --search-db      (apple-docs output; + sibling per-source DBs)
├── packages.db                    #                  (output, derived path)
└── apple-sample-code.db                     # --samples-db     (output)
```

## Incremental vs. Full Build

### Default (incremental)
```bash
cupertino save --all
```
- Computes content hash per document; only re-indexes documents whose hash changed.
- Drops rows whose source files have been removed.
- Fast for partial recrawls.
- Note: `--source samples` scope is always wipe-and-rebuild; `--clear` is meaningful for the docs + packages buckets.

### Full rebuild
```bash
cupertino save --all --clear
```
- Wipes the in-scope DB(s).
- Re-indexes everything.
- Slower but produces a known-clean baseline.

## Common Usage Patterns

### Build every source's DB
```bash
cupertino save --all
```

### Only docs (skip packages and samples)
```bash
cupertino save --source apple-docs
```

### Only samples
```bash
cupertino save --source samples
```

### Force samples re-index
```bash
cupertino save --source samples --force
```

### Stream-from-GitHub mode (no local crawl needed)
```bash
cupertino save --remote
```

### Skip preflight prompt
```bash
cupertino save --yes
```

## Output

| Scope (`--source <id>`) | DB | Tables (top-level) |
|-------|-----|---------|
| docs-bucket sources (`apple-docs`, `swift-evolution`, `hig`, `apple-archive`, `swift-org`, `swift-book`) | `apple-documentation.db` + sibling per-source DBs | `docs_fts`, `docs_metadata`, `docs_structured`, `doc_symbols`, `doc_imports`, `framework_aliases`, `doc_code_examples`, `doc_code_fts` |
| `packages` | `packages.db` | `package_files_fts`, `package_files`, `packages` |
| `samples` | `apple-sample-code.db` (one file, two table tracks per #1037) | rich: `projects`, `files`, `file_symbols`, `file_imports`, `samples_schema_version`; FTS: `docs_metadata`, `docs_fts` |

## Error Handling

### Every scope's source dir missing
```
❌ No source data found for any scope.
   Run 'cupertino fetch' first, or use 'cupertino save --remote'.
```

### One scope's source dir missing (others continue)
```
ℹ️  No package archives at ~/.cupertino/packages/, skipping packages scope.
ℹ️  No sample-code at ~/.cupertino/sample-code/, skipping samples scope.
✓ apple-documentation.db built (docs scope).
```

## Notes

- The `cupertino index` subcommand is gone, `--source samples` absorbed it (#231).
- All paths support tilde (`~`) expansion.
- Run `cupertino save --help` for the complete current flag list.

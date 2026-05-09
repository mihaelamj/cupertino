# Default Options Behavior

When no options are specified for `save` command

## Synopsis

```bash
cupertino save
```

## Default Behavior

`cupertino save` with no scope flag runs the **full pipeline** — it builds `search.db` (the docs scope, default ON) plus `packages.db` and `samples.db` if their source data is present (#231). Each scope reads from its standard directory under `~/.cupertino/` and writes to its standard DB path.

Equivalent to:

```bash
cupertino save --docs --packages --samples \
  --base-dir ~/.cupertino \
  --search-db ~/.cupertino/search.db \
  --samples-db ~/.cupertino/samples.db
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
| `--search-db` | `~/.cupertino/search.db` | search.db output path |
| `--samples-db` | `~/.cupertino/samples.db` | samples.db output path |
| `--docs` | (on by default if no scope flag set) | Build search.db |
| `--packages` | (off unless explicit, or implied default) | Build packages.db |
| `--samples` | (off unless explicit, or implied default) | Build samples.db |
| `--clear` | `false` | Incremental build (default); `--clear` to wipe and rebuild |
| `--remote` | `false` | Stream from GitHub instead of reading local files |
| `--force` | `false` | Re-index every sample under `--samples` even if unchanged |
| `--yes` / `-y` | `false` | Skip the preflight summary + confirmation prompt |

## Build Behavior

With no scope flag, `cupertino save`:

1. **Loads `BinaryConfig`** — resolves `defaultBaseDirectory` (overridable via `cupertino.config.json` next to the binary).
2. **Runs the preflight** — prints the resolved scope set, source directories, output DB paths, and asks for confirmation (skipped when stdin isn't a TTY or `--yes` is set; #232).
3. **Builds `search.db`** (docs scope) — iterates `--docs-dir`, `--evolution-dir`, `--swift-org-dir`, `--archive-dir`, `--metadata-file`. Missing directories are skipped with an info-level log (not a hard error).
4. **Builds `packages.db`** (packages scope) — iterates `--packages-dir/<owner>/<repo>/`. Skipped if no extracted archives exist.
5. **Builds `samples.db`** (samples scope) — iterates `--samples-dir`. Always wipes-and-rebuilds (the samples-side schema doesn't yet support partial updates).

Steps 3–5 are independent. Failures in one scope don't block the others.

## Directory Requirements

None of the source directories are individually required. Each scope is best-effort: missing directory → scope skipped with a log line. The command exits with success if at least one scope completed; with an error if every scope was skipped (no source data anywhere).

## Expected Directory Structure

```
~/.cupertino/
├── docs/                          # --docs-dir       (search.db scope)
│   ├── metadata.json              # --metadata-file
│   ├── Foundation/
│   └── SwiftUI/
├── swift-evolution/               # --evolution-dir  (search.db scope)
├── swift-org/                     # --swift-org-dir  (search.db scope)
├── archive/                       # --archive-dir    (search.db scope)
├── hig/                           # search.db scope
├── packages/                      # --packages-dir   (packages.db scope)
│   └── <owner>/<repo>/...
├── sample-code/                   # --samples-dir    (samples.db scope)
│   └── <project_id>/
├── search.db                      # --search-db      (output)
├── packages.db                    #                  (output, derived path)
└── samples.db                     # --samples-db     (output)
```

## Incremental vs. Full Build

### Default (incremental)
```bash
cupertino save
```
- Computes content hash per document; only re-indexes documents whose hash changed.
- Drops rows whose source files have been removed.
- Fast for partial recrawls.
- Note: `--samples` scope is always wipe-and-rebuild; `--clear` is meaningful for `--docs` and `--packages`.

### Full rebuild
```bash
cupertino save --clear
```
- Wipes the in-scope DB(s).
- Re-indexes everything.
- Slower but produces a known-clean baseline.

## Common Usage Patterns

### Default (build all three scopes)
```bash
cupertino save
```

### Only docs (skip packages and samples)
```bash
cupertino save --docs
```

### Only samples
```bash
cupertino save --samples
```

### Force samples re-index
```bash
cupertino save --samples --force
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

| Scope | DB | Tables (top-level) |
|-------|-----|---------|
| `--docs` | `search.db` | `docs_fts`, `docs_metadata`, `docs_structured`, `doc_symbols`, `doc_imports`, `framework_aliases`, `doc_code_examples`, `doc_code_fts`, `packages` (legacy), `package_dependencies` (legacy), `sample_code` (legacy) |
| `--packages` | `packages.db` | `package_files_fts`, `package_files`, `packages` |
| `--samples` | `samples.db` | `samples_fts`, `samples`, `projects`, `project_imports` |

## Error Handling

### Every scope's source dir missing
```
❌ No source data found for any scope.
   Run 'cupertino fetch' first, or use 'cupertino save --remote'.
```

### One scope's source dir missing (others continue)
```
ℹ️  No package archives at ~/.cupertino/packages/ — skipping packages scope.
ℹ️  No sample-code at ~/.cupertino/sample-code/ — skipping samples scope.
✓ search.db built (docs scope).
```

## Notes

- The `cupertino index` subcommand is gone — `--samples` absorbed it (#231).
- All paths support tilde (`~`) expansion.
- Run `cupertino save --help` for the complete current flag list.

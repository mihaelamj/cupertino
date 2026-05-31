# cupertino save

Rebuild the per-source databases (`apple-documentation.db`, `packages.db`, `apple-sample-code.db`, and the smaller per-source files) from on-disk sources.

> **Most users do not need this command.** `cupertino setup` downloads the pre-built bundle and is the supported end-user workflow. `save` is for maintainers rebuilding the bundle, or advanced users rebuilding from a local crawl produced by `cupertino fetch`. ([#671](https://github.com/mihaelamj/cupertino/issues/671))

## Synopsis

```bash
cupertino save [options]
```

## Description

The `save` command builds the local SQLite databases that back `cupertino search` (both the default fan-out mode and `--source`-filtered queries). Post-#1037 the build scope is selected per source via `--source <id>` (repeatable) or `--all`:

| Source id | Builds | Input |
|---|---|---|
| `apple-docs` | `apple-documentation.db` | `~/.cupertino/docs/` |
| `swift-evolution` | `swift-evolution.db` | `~/.cupertino/swift-evolution/` |
| `hig` | `hig.db` | `~/.cupertino/hig/` |
| `apple-archive` | `apple-archive.db` | `~/.cupertino/archive/` |
| `swift-org` | `swift-org.db` | `~/.cupertino/swift-org/` |
| `swift-book` | `swift-book.db` | `~/.cupertino/swift-org/swift-book/` |
| `samples` | `apple-sample-code.db` (Sample.Index rich schema + SampleCodeSource FTS rows; one DB, two table tracks per #1037) | `~/.cupertino/sample-code/*.zip` |
| `packages` | `packages.db` | `~/.cupertino/packages/<owner>/<repo>/` |

`apple-sample-code` is accepted as an alias for `samples` (cross-command consistency with `cupertino fetch --source apple-sample-code`).

Bare `cupertino save` (no `--source` and no `--all`) is a usage error post-#1037. Sources whose input directory is absent or whose catalog is empty are skipped cleanly; the per-source summary shows `[source] skipped (no local corpus)` and the run does not count as a failure ([#671](https://github.com/mihaelamj/cupertino/issues/671)).

**Dispatch granularity**: `--source <id>` narrows the docs runner to ONLY the destination DB whose providers include that id. `--source apple-docs` builds `apple-documentation.db` alone; post-#1038 `swift-org` builds `swift-org.db` and `swift-book` builds `swift-book.db` (separate files); `--source samples` writes to `apple-sample-code.db` via BOTH the Sample.Index rich-data pipeline AND the docs runner's SampleCodeSource group; `--source packages` runs the standalone PackagesService outside the docs runner. See [source.md](option%20%28--%29/source.md) Dispatch section.

## Options

### Scope (mutually exclusive; one is required)

- [--source](option%20%28--%29/source.md), source id to build, repeatable. Valid ids: `apple-docs`, `swift-evolution`, `hig`, `apple-archive`, `swift-org`, `swift-book`, `samples`, `packages` (plus `apple-sample-code` alias for `samples`).
- [--all](option%20%28--%29/all.md), build every source's DB (explicit replacement for the pre-#1037 bare-`cupertino save` default).

### Docs-build options

- [--remote](option%20%28--%29/remote/) - **Stream from GitHub** (instant setup, no local files)
- [--base-dir](option%20%28--%29/base-dir.md) - Base directory (auto-fills all directories from standard structure)
- [--docs-dir](option%20%28--%29/docs-dir.md) - Directory containing crawled documentation
- [--evolution-dir](option%20%28--%29/evolution-dir.md) - Directory containing Swift Evolution proposals
- [--swift-org-dir](option%20%28--%29/swift-org-dir.md) - Directory containing Swift.org documentation
- [--packages-dir](option%20%28--%29/packages-dir.md) - Directory containing package READMEs
- `--archive-dir` - Directory containing Apple Archive documentation (legacy programming guides like Core Animation, Quartz 2D, KVO/KVC)
- [--metadata-file](option%20%28--%29/metadata-file.md) - Path to metadata.json file
- [--clear](option%20%28--%29/clear.md) - Clear existing index before building

### Samples-build options (consumed only when `--source samples` is in scope; passing them otherwise emits a warning)

- `--samples-dir <path>`, sample-code source directory (defaults to `~/.cupertino/sample-code/`)
- `--samples-db <path>`, `apple-sample-code.db` output path
- `--force`, re-index every sample even if already in the DB

### Common options

- [--yes](option%20%28--%29/yes.md), skip the preflight summary + confirmation prompt ([#232](https://github.com/mihaelamj/cupertino/issues/232)). Auto-skipped when stdin isn't a TTY (so cron jobs, CI runs, and pipelines don't hang waiting for input).

## Examples

### Build everything
```bash
cupertino save --all                    # build every source's DB
```

### Quick docs setup via remote stream
```bash
cupertino save --remote
```

### Scoped builds
```bash
cupertino save --source apple-docs                   # apple-documentation.db only
cupertino save --source packages               # packages.db only
cupertino save --source samples                # apple-sample-code.db only (was: cupertino index)
cupertino save --source packages --source samples     # both packages and samples, skip docs
```

### Custom paths
```bash
cupertino save --source apple-docs --docs-dir ./my-docs
cupertino save --source samples --samples-dir ~/my-samples --samples-db ~/my-apple-sample-code.db
```

### Rebuild docs index
```bash
cupertino save --source apple-docs --clear
```

### Index Multiple Sources
```bash
cupertino save --source apple-docs --docs-dir ./apple-docs --evolution-dir ./evolution
```

## Output

The indexer creates:
- **apple-documentation.db** (plus the sibling per-source DBs) - SQLite databases with FTS5 indexes
- Indexed fields:
  - Page titles
  - Full content
  - Framework names
  - URL paths
  - Metadata

## Search Features

The FTS5 index supports:
- **Full-text search** - Search across all documentation content
- **BM25 ranking** - Relevance-based result ordering
- **Framework filtering** - Narrow results by framework
- **Snippet generation** - Show matching context
- **Fast queries** - Sub-second search across thousands of pages

## Notes

- **Remote mode** (`--remote`): No prerequisites - streams from GitHub
- **Local mode**: Requires crawled documentation (run `cupertino fetch` first)
- Uses SQLite FTS5 for optimal search performance
- Index size is typically ~10-20% of total documentation size
- Remote mode is resumable if interrupted
- Compatible with MCP server for AI integration

## Next Steps

After building the search index, you can start the MCP server:

```bash
cupertino
```

Or explicitly:

```bash
cupertino serve
```

The server will automatically detect and use the search index to provide search tools to AI assistants.

## See Also

- [search](../search/) - Search documentation from CLI
- [serve](../serve/) - Start MCP server
- [fetch](../fetch/) - Download documentation
- [doctor](../doctor/) - Check server health

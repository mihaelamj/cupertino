# cupertino save

Rebuild `search.db` / `packages.db` / `samples.db` from on-disk sources.

> **Most users do not need this command.** `cupertino setup` downloads the pre-built bundle and is the supported end-user workflow. `save` is for maintainers rebuilding the bundle, or advanced users rebuilding from a local crawl produced by `cupertino fetch`. ([#671](https://github.com/mihaelamj/cupertino/issues/671))

## Synopsis

```bash
cupertino save [options]
```

## Description

The `save` command builds the local SQLite databases that back `cupertino search` (both the default fan-out mode and `--source`-filtered queries). As of [#231](https://github.com/mihaelamj/cupertino/issues/231) it covers all three databases via scope flags:

| Flag | Builds | Source |
|---|---|---|
| `--docs` | `search.db` | `~/.cupertino/docs/`, `swift-evolution/`, `swift-org/`, `archive/`, `hig/` |
| `--packages` | `packages.db` | `~/.cupertino/packages/<owner>/<repo>/` |
| `--samples` | `samples.db` | `~/.cupertino/sample-code/*.zip` |

When **no scope flag is passed**, `save` builds **all three** in fixed order (docs → packages → samples). Sources whose input directory is absent or whose catalog is empty are skipped cleanly — the per-source summary shows `[source] skipped (no local corpus)` instead of `[source] indexed: 0, skipped: 0`, and the run does not count as a failure ([#671](https://github.com/mihaelamj/cupertino/issues/671)).

The `--samples` form replaces the old `cupertino index` command (removed in #231). No backwards-compat alias — pre-1.0 clean break.

## Options

### Scope (combinable)

- `--docs` — build `search.db` only
- `--packages` — build `packages.db` only
- `--samples` — build `samples.db` only (replaces `cupertino index`, [#231](https://github.com/mihaelamj/cupertino/issues/231))

### Docs-build options

- [--remote](option%20%28--%29/remote/) - **Stream from GitHub** (instant setup, no local files)
- [--base-dir](option%20%28--%29/base-dir.md) - Base directory (auto-fills all directories from standard structure)
- [--docs-dir](option%20%28--%29/docs-dir.md) - Directory containing crawled documentation
- [--evolution-dir](option%20%28--%29/evolution-dir.md) - Directory containing Swift Evolution proposals
- [--swift-org-dir](option%20%28--%29/swift-org-dir.md) - Directory containing Swift.org documentation
- [--packages-dir](option%20%28--%29/packages-dir.md) - Directory containing package READMEs
- `--archive-dir` - Directory containing Apple Archive documentation (legacy programming guides like Core Animation, Quartz 2D, KVO/KVC)
- [--metadata-file](option%20%28--%29/metadata-file.md) - Path to metadata.json file
- [--search-db](option%20%28--%29/search-db.md) - Output path for search database
- [--clear](option%20%28--%29/clear.md) - Clear existing index before building

### Samples-build options ([#231](https://github.com/mihaelamj/cupertino/issues/231))

- `--samples-dir <path>` — sample-code source directory (defaults to `~/.cupertino/sample-code/`)
- `--samples-db <path>` — `samples.db` output path
- `--force` — re-index every sample even if already in the DB

### Common options

- [--yes](option%20%28--%29/yes.md) — skip the preflight summary + confirmation prompt ([#232](https://github.com/mihaelamj/cupertino/issues/232)). Auto-skipped when stdin isn't a TTY (so cron jobs, CI runs, and pipelines don't hang waiting for input).

## Examples

### Build everything (default)
```bash
cupertino save                          # docs → packages → samples, in order
```

### Quick docs setup via remote stream
```bash
cupertino save --remote
```

### Scoped builds
```bash
cupertino save --docs                   # search.db only
cupertino save --packages               # packages.db only
cupertino save --samples                # samples.db only (was: cupertino index)
cupertino save --packages --samples     # both packages and samples, skip docs
```

### Custom paths
```bash
cupertino save --docs --docs-dir ./my-docs --search-db ./my-search.db
cupertino save --samples --samples-dir ~/my-samples --samples-db ~/my-samples.db
```

### Rebuild docs index
```bash
cupertino save --docs --clear
```

### Index Multiple Sources
```bash
cupertino save --docs-dir ./apple-docs --evolution-dir ./evolution
```

## Output

The indexer creates:
- **search.db** - SQLite database with FTS5 index
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

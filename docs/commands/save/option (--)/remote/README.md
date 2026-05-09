# --remote

Stream documentation from GitHub to build search database without local files.

## Usage

```bash
cupertino save --remote
```

## Description

The `--remote` flag enables **instant setup** by streaming pre-crawled documentation directly from the [cupertino-docs](https://github.com/mihaelamj/cupertino-docs) GitHub repository into the search database.

### Key Features

- **No disk bloat**: Streams JSON directly to SQLite without saving files locally
- **Resumable**: If interrupted, re-run and choose to resume from where you left off
- **No rate limits**: Uses raw.githubusercontent.com (not GitHub API)
- **Fast setup**: Minutes instead of hours of crawling

### How It Works

1. Fetches framework list from GitHub API (single call)
2. For each framework/phase:
   - Streams files via raw GitHub URLs
   - Parses JSON and indexes directly to search.db
   - Saves progress state for resume capability
3. Shows animated progress with ETA

### Phases

`--remote` only feeds the **docs scope** — the search.db that `cupertino save --docs` builds. The `--packages` and `--samples` scopes still require local extracted archives (run `cupertino fetch --type packages` / `cupertino fetch --type samples` first).

| Phase | Source | Description |
|-------|--------|-------------|
| docs | `docs/` | Apple framework documentation folders |
| evolution | `swift-evolution/` | Swift Evolution proposals |
| archive | `archive/` | Legacy Apple programming guides |
| swiftOrg | `swift-org/` | Swift.org documentation |
| hig | `hig/` | Human Interface Guidelines |

### State File

Progress is saved to `~/.cupertino/remote-save-state.json` for resume support. Schema (illustrative — exact field set may evolve across releases):

```json
{
  "version": "<binary-version>",
  "started": "2026-05-09T12:00:00Z",
  "phase": "docs",
  "phasesCompleted": [],
  "currentFramework": "swiftui",
  "frameworksCompleted": ["accelerate", "accessibility"],
  "frameworksTotal": 261,
  "currentFileIndex": 456,
  "filesTotal": 1000
}
```

### Resume

If interrupted and re-run:

```
Found previous session
   Phase: docs
   Progress: 142/248 frameworks
   Current: swiftui (456/1000 files)

Resume from swiftui? [Y/n]
```

### Progress Display

```
Building database from remote...

Docs: [############........] 142/248
   Current: SwiftUI (456/1000 files)

Elapsed: 12:34 | ETA: 8:21
Overall: 28.5%
```

## Options

When using `--remote`, these options change behavior:

- [--base-dir](option%20%28--%29/base-dir.md) - Base directory for state file only (not documentation)
- [--search-db](option%20%28--%29/search-db.md) - Output path for search database

## Comparison

| Method | What it produces | Notes |
|--------|------------------|-------|
| `cupertino setup` | All three databases (search.db + packages.db + samples.db) | Fastest — single zip download |
| `cupertino save --remote` | search.db only (docs scope) | Streams from cupertino-docs repo, no local crawl needed |
| `cupertino fetch && cupertino save` | Whichever scopes you fetched | Multi-hour fresh crawl + local index build |

## Related

- [save command](../../README.md)
- [cupertino-docs repo](https://github.com/mihaelamj/cupertino-docs)

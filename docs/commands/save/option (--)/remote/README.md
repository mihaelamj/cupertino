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

| Phase | Source | Description |
|-------|--------|-------------|
| docs | `docs/` | 248 Apple framework documentation folders |
| evolution | `swift-evolution/` | Swift Evolution proposals |
| archive | `archive/` | Legacy Apple programming guides |
| swiftOrg | `swift-org/` | Swift.org documentation |
| packages | `packages/` | Package READMEs |

### State File

Progress is saved to `~/.cupertino/remote-save-state.json` for resume support:

```json
{
  "version": "0.2.7",
  "started": "2025-12-04T12:00:00Z",
  "phase": "docs",
  "phasesCompleted": [],
  "currentFramework": "swiftui",
  "frameworksCompleted": ["accelerate", "accessibility"],
  "frameworksTotal": 248,
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

| Method | Time | Disk Space | Requirements |
|--------|------|------------|--------------|
| `cupertino fetch` + `save` | ~20+ hours | ~50GB docs + DB | Apple account (for samples) |
| `cupertino save --remote` | ~30 minutes | DB only (~500MB) | Internet connection |

## Related

- [save command](../../README.md)
- [cupertino-docs repo](https://github.com/mihaelamj/cupertino-docs)

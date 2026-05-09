# cupertino setup

Download every cupertino database (search.db, samples.db, packages.db) in one go.

## Synopsis

```bash
cupertino setup
```

## Description

The `setup` command downloads pre-built databases from GitHub Releases, providing instant access to Apple documentation, sample code, and Swift package search without crawling or indexing.

This is the **fastest way to get started** with Cupertino.

All three databases ship in a single bundle from the [`cupertino-docs`](https://github.com/mihaelamj/cupertino-docs) releases (`cupertino-databases-vX.zip`). One download, one extract, all three databases on disk. (Earlier releases split `packages.db` into a separate companion repo; that proved to be needless complexity and is gone as of v1.0.0.)

## What Gets Downloaded

A single zip from the [`cupertino-docs`](https://github.com/mihaelamj/cupertino-docs) GitHub Releases — `cupertino-databases-vX.zip` — containing all three databases. Exact contents vary by release; the v1.0.0 / v1.0.1 bundles ship roughly:

| Database | Contents | Size |
|----------|----------|------|
| `search.db` | ~405,000 documentation pages across Apple frameworks + Swift Evolution + Swift.org + HIG + Apple Archive + Swift Book | ~1.5 GB |
| `samples.db` | Indexed Apple sample-code catalog and crawled GitHub sample projects (READMEs + source files + AST symbols) | ~150-200 MB |
| `packages.db` | ~9,700 Swift packages with README, Package.swift, Sources/, Tests/, .docc/ extracted | ~150 MB |

Numbers above are approximate and snapshot the v1.0 bundle; check the corresponding GitHub Release for the per-release totals.

## Options

- `--base-dir` - Custom directory for databases (default: `~/.cupertino/`)
- `--keep-existing` - Skip the download and use whatever databases are already installed

## Default behaviour

`cupertino setup` always downloads the release matching the binary's expected `databaseVersion`. On each successful download it stamps a `.setup-version` file next to the databases so subsequent invocations can show:

- the version currently installed,
- whether it's current, stale, or unknown relative to the binary,
- whether a re-run is a no-op refresh or a real upgrade.

If you upgrade cupertino itself (via `brew upgrade cupertino` or the install script) and the new binary expects a newer `databaseVersion`, rerunning `cupertino setup` upgrades the databases in place.

## Examples

### Quick Setup (Recommended)

```bash
cupertino setup
```

### Custom Location

```bash
cupertino setup --base-dir ~/my-docs
```

### Keep Existing Databases

```bash
cupertino setup --keep-existing
```

## Output

```
📦 Cupertino Setup

⬇️  Downloading Documentation database...
   [████████████████████████████░░] 93% (186.2 MB/200.0 MB)
   ✓ Documentation database (200.0 MB)

⬇️  Downloading Sample code database...
   [██████████████████████████████] 100% (75.0 MB/75.0 MB)
   ✓ Sample code database (75.0 MB)

⬇️  Downloading Packages database...
   [██████████████████████████████] 100% (xx.x MB/xx.x MB)
   ✓ Packages database (xx.x MB)

✅ Setup complete!
   Documentation: /Users/you/.cupertino/search.db
   Sample code:   /Users/you/.cupertino/samples.db
   Packages:      /Users/you/.cupertino/packages.db

💡 Start the server with: cupertino serve
```

## Comparison

| Method | Time | Disk Space |
|--------|------|------------|
| `cupertino setup` | ~30 seconds | ~250 MB |
| `cupertino save --remote` | ~45 minutes | ~250 MB |
| `cupertino fetch && save` | ~20+ hours | ~3 GB + 250 MB |

## Next Steps

After setup, start the MCP server:

```bash
cupertino serve
```

Or simply:

```bash
cupertino
```

## See Also

- [serve](../serve/) - Start MCP server
- [save --remote](../save/option%20%28--%29/remote/) - Stream and build locally
- [fetch](../fetch/) - Download documentation manually

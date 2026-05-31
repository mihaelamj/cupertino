# cupertino doctor

Check MCP server health and configuration

## Synopsis

```bash
cupertino doctor [options]
```

## Description

Verifies that the MCP server can start and all required components are available and properly configured.

**Default output (no flags)** focuses on the runtime surface a `cupertino setup` user cares about:

- **Server initialization** - MCP server can be created, transport is stdio, current protocol version
- **Packages index (`packages.db`)** - Presence, size, row counts (packages + indexed files), bundled version. Missing is a warning, not a failure.
- **Sample code index (`apple-sample-code.db`)** - Presence, size, row counts (projects + indexed files + symbols).
- **Per-source documentation indexes** - One health block per source database (`apple-documentation.db`, `hig.db`, `apple-archive.db`, `swift-evolution.db`, `swift-org.db`, `swift-book.db`): presence, size, **schema version** vs binary, framework + entry counts. Schema mismatch (older or newer than the binary) is a hard fail with a precise rebuild hint. A legacy `search.db` check remains for installs still carrying the pre-v1.3.0 unified file (normally absent post-split).
- **Resource providers** - DocsResourceProvider and SearchToolProvider are available
- **Schema versions per DB** ([#234](https://github.com/mihaelamj/cupertino/issues/234)) - sequential schema number + journal mode for every local database. WAL sidecar size + non-local-volume warnings ([#236](https://github.com/mihaelamj/cupertino/issues/236)). The v1.3.0 bundle ships `packages.db` + `apple-sample-code.db` in rollback (`journal=delete`) mode; doctor labels that `read-only distribution mode` and does not flag it.

**[`--save`](option%20%28--%29/save.md) adds the maintenance sections** for users about to crawl or re-index:

- **Documentation directories** - Apple docs, Swift Evolution, HIG, Swift.org, Apple Archive (each with file count)
- **Swift Packages (filesystem)** - User selections file, downloaded READMEs, orphan / missing tallies, priority-package counts (Apple + Ecosystem)
- **`cupertino save` preflight summary** - per-source presence and availability-annotation coverage (backed by `Indexer.Preflight.preflightLines(...)`)

Use this command to troubleshoot setup issues before starting the server. Pre-[#68](https://github.com/mihaelamj/cupertino/issues/68) the corpus + packages-filesystem sections ran on every invocation; they made a `cupertino setup`-only install look broken (a `0 files` line under "Apple docs" is normal in that flow, not a failure).

## Options

### --docs-dir

Directory containing Apple documentation.

**Type:** String
**Default:** `~/.cupertino/docs`

**Example:**
```bash
cupertino doctor --docs-dir ~/my-custom-docs
```

### --evolution-dir

Directory containing Swift Evolution proposals.

**Type:** String
**Default:** `~/.cupertino/swift-evolution`

**Example:**
```bash
cupertino doctor --evolution-dir ~/my-evolution
```

### --save

Include the maintenance-side sections in the doctor report (additive on top of the default health suite). See [`option (--)/save.md`](option%20%28--%29/save.md) for the full description.

Adds these to the default output:

- 📂 Raw corpus directories (the inputs `cupertino save` would consume)
- 📦 Swift Packages: user selection state + downloaded README counts + orphan / missing tallies
- 🔍 `cupertino save` per-source preflight summary (backed by `Indexer.Preflight.preflightLines(...)`, lifted in [#244](https://github.com/mihaelamj/cupertino/issues/244))

Pre-[#68](https://github.com/mihaelamj/cupertino/issues/68) this flag short-circuited to only the preflight summary; it is now additive so a maintainer gets one combined report instead of running doctor twice.

**Type:** Flag
**Default:** false

**Example:**
```bash
cupertino doctor --save
```

## Examples

### Check Default Configuration

```bash
cupertino doctor
```

### Check Custom Configuration

```bash
cupertino doctor \
  --docs-dir ~/custom/docs \
  --evolution-dir ~/custom/evolution
```

### Verify Before Starting Server

```bash
# Check health first
cupertino doctor

# If all checks pass, start server
cupertino serve
```

## Output

### All Checks Passing

Default `cupertino doctor` output (no flags):

```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📦 Packages Index (packages.db)
   ✓ Database: /Users/you/.cupertino/packages.db
   ✓ Size: 988.9 MB
   ✓ Indexed files: 20186
   ℹ  Bundled version: 1.1.0

🧪 Sample Code Index (apple-sample-code.db)
   ✓ Database: /Users/you/.cupertino/apple-sample-code.db
   ✓ Size: 184.4 MB
   ✓ Projects: 619
   ✓ Indexed files: 18928
   ✓ Indexed symbols: 108536

🔍 Search Index
   ⚠  search.db: not found (legacy unified DB; superseded by the per-source DBs below in v1.3.0)

🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: /Users/you/.cupertino/apple-documentation.db
   ✓ Size: 2.82 GB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 398
   📚 Indexed sources:
     ✓ apple-docs: 351505 entries

🔍 Human Interface Guidelines (hig.db)
   ✓ Database: /Users/you/.cupertino/hig.db
   ✓ Size: 12.5 MB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 6
   📚 Indexed sources:
     ✓ hig: 173 entries

🔍 Apple Archive (apple-archive.db)
   ✓ Database: /Users/you/.cupertino/apple-archive.db
   ✓ Size: 25.0 MB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 14
   📚 Indexed sources:
     ✓ apple-archive: 368 entries

🔍 Swift Evolution (swift-evolution.db)
   ✓ Database: /Users/you/.cupertino/swift-evolution.db
   ✓ Size: 24.6 MB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 1
   📚 Indexed sources:
     ✓ swift-evolution: 487 entries

🔍 Swift.org (swift-org.db)
   ✓ Database: /Users/you/.cupertino/swift-org.db
   ✓ Size: 13.6 MB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 1
   📚 Indexed sources:
     ✓ swift-org: 469 entries

🔍 Swift Book (swift-book.db)
   ✓ Database: /Users/you/.cupertino/swift-book.db
   ✓ Size: 2.3 MB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 1
   📚 Indexed sources:
     ✓ swift-book: 43 entries

🔧 Providers
   ✓ MCP.Support.DocsResourceProvider: available
   ✓ SearchToolProvider: available


8. Schema versions (#234)

   ⚠ search.db: not found (legacy unified DB; superseded by per-source DBs)
   ✓ apple-documentation.db: 18 (sequential), journal=wal
   ✓ hig.db: 18 (sequential), journal=wal
   ✓ apple-archive.db: 18 (sequential), journal=wal
   ✓ swift-evolution.db: 18 (sequential), journal=wal
   ✓ swift-org.db: 18 (sequential), journal=wal
   ✓ swift-book.db: 18 (sequential), journal=wal
   ✓ packages.db: 5 (sequential), journal=delete (read-only distribution mode)
   ✓ apple-sample-code.db: 4 (sequential), journal=delete (read-only distribution mode)

✅ All checks passed - MCP server ready
```

`cupertino doctor --save` appends the maintenance sections on top of the default output:

```
… (default sections above) …

📂 Raw corpus directories (input for `cupertino save`)
   ✓ Apple docs: /Users/you/.cupertino/docs (415212 files)
   ✓ Swift Evolution: /Users/you/.cupertino/swift-evolution (483 proposals)
   ✓ Swift.org: /Users/you/.cupertino/swift-org (196 pages)
   ✓ HIG: /Users/you/.cupertino/hig (173 pages)
   ✓ Apple Archive: /Users/you/.cupertino/archive (406 guides)

📦 Swift Packages
   ✓ User selections: /Users/you/.cupertino/selected-packages.json
     135 packages selected
   ✓ Downloaded READMEs: 448 packages
   ℹ  Priority packages: 135 total (Apple: 43, Ecosystem: 92)

🔍 `cupertino save` preflight check

  Docs (apple-documentation.db)
    ✓  /Users/you/.cupertino/docs  (415212 entries)
    ✓  Availability annotation present

  Packages (packages.db)
    ✓  /Users/you/.cupertino/packages  (183 packages)
    ✓  availability.json sidecars  (183/183)

  Samples (apple-sample-code.db)
    ✓  /Users/you/.cupertino/sample-code  (627 zips)
    (annotation runs inline during save, no preflight check needed)

✅ All checks passed - MCP server ready
```

### Schema Mismatch (binary newer than DB)

```
🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: /Users/you/.cupertino/apple-documentation.db
   ✓ Size: 2.1 GB
   ✗ Schema version: 15 (binary expects 18, rebuild required)
     → rm /Users/you/.cupertino/apple-documentation.db && cupertino setup

⚠️  Some checks failed - see above for details
```

### Schema Mismatch (binary older than DB)

```
🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: /Users/you/.cupertino/apple-documentation.db
   ✓ Size: 2.8 GB
   ✗ Schema version: 19 (newer than binary, expected 18)
     → Upgrade cupertino: brew upgrade cupertino

⚠️  Some checks failed - see above for details
```

### Fresh Installation (no databases yet)

Default `cupertino doctor` output before `cupertino setup` has been run:

```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📦 Packages Index (packages.db)
   ⚠  Database: /Users/you/.cupertino/packages.db (not found)
     → Run: cupertino setup  (downloads the pre-built packages index)
     Expected version: 1.1.0

🧪 Sample Code Index (apple-sample-code.db)
   ⚠  Database: /Users/you/.cupertino/apple-sample-code.db (not found)
     → Run: cupertino fetch --source samples && cupertino cleanup && cupertino save --source samples

🔍 Apple Developer Documentation (apple-documentation.db)
   ✗ Database: /Users/you/.cupertino/apple-documentation.db (not found)
     → Run: cupertino setup  (or `cupertino save --source apple-docs` if building locally)

🔧 Providers
   ✓ MCP.Support.DocsResourceProvider: available
   ✓ SearchToolProvider: available

⚠️  Some checks failed - see above for details
```

Note the absence of the `📚 Documentation Directories` and filesystem `📦 Swift Packages` sections that appeared here pre-[#68](https://github.com/mihaelamj/cupertino/issues/68). A `cupertino setup`-only user never populates the raw corpus dirs and the missing-corpus warnings were false alarms. To see those sections, run `cupertino doctor --save`.

## Health Checks

### Default (always run)

#### 1. MCP Server

Verifies that:
- MCP server can be initialized
- Stdio transport is available
- Current protocol version (`2025-11-25`)

**Always passes** - checks basic server functionality.

#### 2. Packages Index (`packages.db`)

Verifies:
- `~/.cupertino/packages.db` exists
- Reports size, package count, indexed file count, and the bundled `packagesIndexVersion`

**Warning only** - server runs without `packages.db`; the packages tool simply isn't available.

#### 3. Sample Code Index (`apple-sample-code.db`)

Verifies:
- `~/.cupertino/apple-sample-code.db` exists
- Reports size, project count, indexed file count, indexed symbol count

**Warning only** - server runs without `apple-sample-code.db`; the sample-code search just isn't available.

#### 4. Per-source documentation indexes

For each docs source DB (`apple-documentation.db`, `hig.db`, `apple-archive.db`, `swift-evolution.db`, `swift-org.db`, `swift-book.db`) verifies:
- The file exists under the base directory
- **Schema version** matches the binary's expected `Search.Index.schemaVersion`
- Database can be opened and queried via `Search.Index`
- Counts indexed frameworks + per-source entries

A legacy `search.db` block still runs for pre-v1.3.0 installs; post-split it reports "not found" (or "empty") and is not a failure on a per-source bundle.

Shows:
- Database path
- File size
- Schema version (with `matches` / older / newer status)
- Framework count

**Critical** - schema mismatch is a hard fail. Older schema suggests `rm <db> && cupertino save --source apple-docs`. Newer schema suggests `brew upgrade cupertino`. Doctor exits non-zero so CI / smoke tests fail loudly. ([#192 F2](https://github.com/mihaelamj/cupertino/issues/192))

#### 5. Providers

Confirms that:
- DocsResourceProvider is available
- SearchToolProvider is available

**Always passes** - providers are built into the binary.

#### 6. Schema versions per DB ([#234](https://github.com/mihaelamj/cupertino/issues/234))

Reads `PRAGMA user_version` for every local database (the 8 per-source DBs plus any legacy `search.db`) and reports the sequential schema number plus journal mode. The v1.3.0 bundle ships `packages.db` + `apple-sample-code.db` in rollback (`journal=delete`) mode, labelled `read-only distribution mode` and not flagged; other DBs on `journal=wal` get a non-local-volume warning for NFS / SMB / AFP, since SQLite WAL doesn't work over network filesystems ([#236](https://github.com/mihaelamj/cupertino/issues/236)). The WAL sidecar size is included; runaway sidecars (`> 16 MB`) hint at checkpoint starvation from a long-lived reader.

### `--save` only (maintainer-facing, added by [`--save`](option%20%28--%29/save.md))

#### A. Documentation Directories

Checks:
- **Apple docs**: Directory exists and contains `.md` files
- **Swift Evolution**: Directory exists and contains proposal files
- **HIG**, **Swift.org**, **Apple Archive**: Directory exists and contains pages

Shows:
- Path to each directory
- Number of files / proposals / pages found
- Suggestions if directories are missing

**Warning only** - server doesn't need raw corpus on disk once the per-source DBs are built (a `cupertino setup` user has the DB but no source dirs, and that's fine).

#### B. Swift Packages (filesystem)

Checks:
- **User selections file** (`~/.cupertino/selected-packages.json`), additively merged with the embedded priority list on every load ([#218](https://github.com/mihaelamj/cupertino/issues/218)). New seeds shipped in `PriorityPackagesEmbedded.swift` propagate into existing installs the next time any subcommand touches the catalog. User deletions don't stick: the merge is set-diff.
- **Downloaded packages** under `~/.cupertino/packages/<owner>/<repo>/` (whole archives, not just READMEs, see `fetch --source packages` stage 2)
- Reports orphaned READMEs (packages no longer selected)
- Counts priority packages bundled with the binary (Apple + Ecosystem)

**Warning only** - server still runs without local package archives.

#### C. `cupertino save` preflight summary

Same output `cupertino save` prints before its confirmation prompt: per-source presence, availability-annotation coverage, sidecar counts. Backed by `Indexer.Preflight.preflightLines(...)` ([#244](https://github.com/mihaelamj/cupertino/issues/244)). Read-only.

## Exit Codes

- **0** - All checks passed, server ready
- **1** - Some checks failed, see output for details

## Use Cases

### Before First Run

```bash
# Download documentation
cupertino fetch --source apple-docs

# Build search index
cupertino save --all

# Verify everything is set up
cupertino doctor

# Start the server
cupertino
```

### Troubleshooting

If the server won't start or clients can't access resources:

```bash
# Run diagnostics
cupertino doctor

# Follow the suggestions in the output
# Example: "Run: cupertino fetch --source apple-docs"
```

### CI/CD Validation

```bash
#!/bin/bash
# Verify server setup in CI

cupertino doctor
if [ $? -eq 0 ]; then
    echo "Server configuration valid"
    exit 0
else
    echo "Server configuration invalid"
    exit 1
fi
```

### Custom Installation Verification

```bash
# After installing to custom location
cupertino doctor \
  --docs-dir /opt/cupertino/docs \
  --evolution-dir /opt/cupertino/evolution
```

## Troubleshooting

### Documentation Not Found

**Problem:**
```
✗ Apple docs: /Users/username/.cupertino/docs (not found)
  → Run: cupertino fetch --source apple-docs
```

**Solution:**
```bash
cupertino fetch --source apple-docs
```

### Search Database Not Found

**Problem:**
```
✗ Database: /Users/you/.cupertino/apple-documentation.db (not found)
  → Run: cupertino setup  (or `cupertino save` if building locally)
```

**Solution (recommended):**
```bash
cupertino setup
```

Or, if you're building the index from a local crawl:
```bash
cupertino save --all
```

### Schema Version Mismatch

**Problem:**
```
✗ Schema version: 15 (binary expects 18, rebuild required)
  → rm /Users/you/.cupertino/apple-documentation.db && cupertino save --source apple-docs
```

This means the on-disk DB was built by an older `cupertino` and the current binary expects a newer schema (one of the FTS5 columns can't be ALTERed, so a rebuild is required).

**Solution:**
```bash
rm ~/.cupertino/apple-documentation.db && cupertino save --source apple-docs
```

Or, if you'd rather pull the pre-built DB matching this binary:
```bash
rm ~/.cupertino/apple-documentation.db && cupertino setup
```

**Inverse problem** (binary newer than DB the user is running against, schema version on disk is **higher** than the binary expects):
```
✗ Schema version: 19 (newer than binary, expected 18)
  → Upgrade cupertino: brew upgrade cupertino
```

**Solution:**
```bash
brew upgrade cupertino
```

### Database Error

**Problem:**
```
✗ Database error: <error message>
  → rm /Users/you/.cupertino/apple-documentation.db && cupertino save --source apple-docs
```

**Possible causes:**
- Corrupted database file
- Permission issues
- Incomplete indexing

**Solution:**
```bash
# Wipe the broken DB and rebuild from local crawl
rm ~/.cupertino/apple-documentation.db && cupertino save --source apple-docs

# Or pull the pre-built DB matching this binary
rm ~/.cupertino/apple-documentation.db && cupertino setup
```

### Custom Path Issues

**Problem:**
Doctor checks wrong paths after using custom directories.

**Solution:**
Specify the same paths you'll use with `serve`:
```bash
cupertino doctor \
  --docs-dir ~/my-docs \
  --evolution-dir ~/my-evolution
```

## Tips

1. **Run after updates**: Run `doctor` after downloading new documentation
2. **Verify before deployment**: Check configuration before deploying to production
3. **Automate checks**: Include in setup scripts to validate installations
4. **Debug client issues**: If Claude can't access resources, run `doctor` to verify server-side setup

## See Also

- [serve](../serve/) - Start the MCP server
- [search](../search/) - Search documentation from CLI
- [fetch](../fetch/) - Download documentation
- [save](../save/) - Build search index

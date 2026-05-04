# cupertino doctor

Check MCP server health and configuration

## Synopsis

```bash
cupertino doctor [options]
```

## Description

Verifies that the MCP server can start and all required components are available and properly configured.

This command performs comprehensive health checks on:
- **Server initialization** - MCP server can be created, transport is stdio, current protocol version
- **Documentation directories** - Apple docs, Swift Evolution, HIG (each with file count)
- **Swift Packages (filesystem)** - User selections file, downloaded READMEs, priority-package counts (Apple + Ecosystem)
- **Packages index (`packages.db`)** - Presence, size, row counts (packages + indexed files), bundled version. Missing is a warning, not a failure.
- **Search index (`search.db`)** - Presence, size, **schema version** vs binary, indexed framework count. Schema mismatch (older or newer than the binary) is a hard fail with a precise rebuild hint.
- **Resource providers** - DocsResourceProvider and SearchToolProvider are available

Use this command to troubleshoot setup issues before starting the server.

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

### --search-db

Path to the search database file.

**Type:** String
**Default:** `~/.cupertino/search.db`

**Example:**
```bash
cupertino doctor --search-db ~/my-search.db
```

### --save

Run the `cupertino save` preflight check only — print which sources are present, which lack availability annotations, what would be skipped — without running the regular doctor health suite. Read-only, no DB writes. Same output `cupertino save` would print as its preflight summary, so you can ask "is save ready?" before committing to a run. ([#232](https://github.com/mihaelamj/cupertino/issues/232))

**Type:** Flag
**Default:** false

**Example:**
```bash
cupertino doctor --save
```

**Sample output:**
```
🔍 `cupertino save` preflight check

  Docs (search.db)
    ✓  /Users/me/.cupertino/docs  (404969 entries)
    ✓  Availability annotation present

  Packages (packages.db)
    ✓  /Users/me/.cupertino/packages  (183 packages)
    ✓  availability.json sidecars  (183/183)

  Samples (samples.db)
    ✓  /Users/me/.cupertino/sample-code  (627 zips)
    (annotation runs inline during save — no preflight check needed)
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
  --evolution-dir ~/custom/evolution \
  --search-db ~/custom/search.db
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

```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📚 Documentation Directories
   ✓ Apple docs: /Users/you/.cupertino/docs (22341 files)
   ✓ Swift Evolution: /Users/you/.cupertino/swift-evolution (500 proposals)
   ✓ HIG: /Users/you/.cupertino/hig (612 pages)

📦 Swift Packages
   ✓ User selections: /Users/you/.cupertino/selected-packages.json
     128 packages selected
   ✓ Downloaded READMEs: 128 packages
     /Users/you/.cupertino/packages
   ℹ  Priority packages: 135 total
     Apple: 43, Ecosystem: 92

📦 Packages Index (packages.db)
   ✓ Database: /Users/you/.cupertino/packages.db
   ✓ Size: 38.4 MB
   ✓ Packages: 9699
   ✓ Indexed files: 124508
   ℹ  Bundled version: 1.0.0

🔍 Search Index
   ✓ Database: /Users/you/.cupertino/search.db
   ✓ Size: 2.5 GB
   ✓ Schema version: 12 (matches installed binary)
   ✓ Frameworks: 261

🔧 Providers
   ✓ DocsResourceProvider: available
   ✓ SearchToolProvider: available

✅ All checks passed - MCP server ready
```

### Schema Mismatch (binary newer than DB)

```
🔍 Search Index
   ✓ Database: /Users/you/.cupertino/search.db
   ✓ Size: 2.1 GB
   ✗ Schema version: 10 (binary expects 12, rebuild required)
     → rm /Users/you/.cupertino/search.db && cupertino save

⚠️  Some checks failed - see above for details
```

### Schema Mismatch (binary older than DB)

```
🔍 Search Index
   ✓ Database: /Users/you/.cupertino/search.db
   ✓ Size: 2.5 GB
   ✗ Schema version: 13 (newer than binary — expected 12)
     → Upgrade cupertino: brew upgrade cupertino

⚠️  Some checks failed - see above for details
```

### Missing Documentation

```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📚 Documentation Directories
   ✗ Apple docs: /Users/you/.cupertino/docs (not found)
     → Run: cupertino fetch --type docs
   ⚠  Swift Evolution: /Users/you/.cupertino/swift-evolution (not found)
     → Run: cupertino fetch --type evolution
   ⚠  HIG: /Users/you/.cupertino/hig (not found)
     → Run: cupertino fetch --type hig

📦 Swift Packages
   ⚠  User selections: not configured
     → Use TUI to select packages, or will use bundled defaults
   ⚠  Package docs: not downloaded
   ℹ  Priority packages: 135 total
     Apple: 43, Ecosystem: 92

📦 Packages Index (packages.db)
   ⚠  Database: /Users/you/.cupertino/packages.db (not found)
     → Run: cupertino setup  (downloads the pre-built packages index)
     Expected version: 1.0.0

🔍 Search Index
   ✗ Database: /Users/you/.cupertino/search.db (not found)
     → Run: cupertino setup  (or `cupertino save` if building locally)

🔧 Providers
   ✓ DocsResourceProvider: available
   ✓ SearchToolProvider: available

⚠️  Some checks failed - see above for details
```

## Health Checks

### 1. MCP Server

Verifies that:
- MCP server can be initialized
- Stdio transport is available
- Current protocol version (`2025-11-25`)

**Always passes** - checks basic server functionality.

### 2. Documentation Directories

Checks:
- **Apple docs**: Directory exists and contains `.md` files
- **Swift Evolution**: Directory exists and contains proposal files
- **HIG**: Directory exists and contains pages

Shows:
- Path to each directory
- Number of files / proposals / pages found
- Suggestions if directories are missing

**Critical for Apple docs** - server needs at least one documentation source.
**Warning for Evolution and HIG** - server can work without them.

### 3. Swift Packages (filesystem)

Checks:
- **User selections file** (`~/.cupertino/selected-packages.json`) — additively merged with the embedded priority list on every load ([#218](https://github.com/mihaelamj/cupertino/issues/218)). New seeds shipped in `PriorityPackagesEmbedded.swift` propagate into existing installs the next time any subcommand touches the catalog. User deletions don't stick — the merge is set-diff.
- **Downloaded packages** under `~/.cupertino/packages/<owner>/<repo>/` (whole archives, not just READMEs — see `fetch --type packages` stage 2)
- Reports orphaned READMEs (packages no longer selected)
- Counts priority packages bundled with the binary (Apple + Ecosystem)

**Warning only** - server still runs without local package archives.

### 4. Packages Index (`packages.db`)

Verifies:
- `~/.cupertino/packages.db` exists
- Reports size, package count, indexed file count, and the bundled `packagesIndexVersion`

**Warning only** - server runs without `packages.db`; the packages tool simply isn't available.

### 5. Search Index (`search.db`)

Verifies:
- `~/.cupertino/search.db` exists
- **Schema version** matches the binary's expected `Search.Index.schemaVersion`
- Database can be opened and queried via `Search.Index`
- Counts indexed frameworks

Shows:
- Database path
- File size
- Schema version (with `matches` / older / newer status)
- Framework count

**Critical** - schema mismatch is a hard fail. Older schema → suggests `rm <db> && cupertino save`. Newer schema → suggests `brew upgrade cupertino`. Doctor exits non-zero so CI / smoke tests fail loudly. (#192 F2)

### 6. Providers

Confirms that:
- DocsResourceProvider is available
- SearchToolProvider is available

**Always passes** - providers are built into the binary.

## Exit Codes

- **0** - All checks passed, server ready
- **1** - Some checks failed, see output for details

## Use Cases

### Before First Run

```bash
# Download documentation
cupertino fetch --type docs

# Build search index
cupertino save

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
# Example: "Run: cupertino fetch --type docs"
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
  --evolution-dir /opt/cupertino/evolution \
  --search-db /opt/cupertino/search.db
```

## Troubleshooting

### Documentation Not Found

**Problem:**
```
✗ Apple docs: /Users/username/.cupertino/docs (not found)
  → Run: cupertino fetch --type docs
```

**Solution:**
```bash
cupertino fetch --type docs
```

### Search Database Not Found

**Problem:**
```
✗ Database: /Users/you/.cupertino/search.db (not found)
  → Run: cupertino setup  (or `cupertino save` if building locally)
```

**Solution (recommended):**
```bash
cupertino setup
```

Or, if you're building the index from a local crawl:
```bash
cupertino save
```

### Schema Version Mismatch

**Problem:**
```
✗ Schema version: 10 (binary expects 12, rebuild required)
  → rm /Users/you/.cupertino/search.db && cupertino save
```

This means the on-disk DB was built by an older `cupertino` and the current binary expects a newer schema (one of the FTS5 columns can't be ALTERed, so a rebuild is required).

**Solution:**
```bash
rm ~/.cupertino/search.db && cupertino save
```

Or, if you'd rather pull the pre-built DB matching this binary:
```bash
rm ~/.cupertino/search.db && cupertino setup
```

**Inverse problem** (binary newer than DB the user is running against — schema version on disk is **higher** than the binary expects):
```
✗ Schema version: 13 (newer than binary — expected 12)
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
  → rm /Users/you/.cupertino/search.db && cupertino save
```

**Possible causes:**
- Corrupted database file
- Permission issues
- Incomplete indexing

**Solution:**
```bash
# Wipe the broken DB and rebuild from local crawl
rm ~/.cupertino/search.db && cupertino save

# Or pull the pre-built DB matching this binary
rm ~/.cupertino/search.db && cupertino setup
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

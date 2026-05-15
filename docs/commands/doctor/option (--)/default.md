# Default Options Behavior

When no options are specified for `doctor` command

## Synopsis

```bash
cupertino doctor
```

## Default Behavior

When you run `cupertino doctor` without any options, it uses these defaults:

```bash
cupertino doctor \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir ~/.cupertino/swift-evolution \
  --search-db ~/.cupertino/search.db
```

Default output focuses on **database + MCP health**. Raw corpus directories and Swift-package selection state moved behind [`--save`](save.md) in [#68](https://github.com/mihaelamj/cupertino/issues/68) because a `cupertino setup` user has no raw corpus on disk (the bundle ships pre-built DBs); the previous `0 files` line under "Apple docs" looked like a failure and isn't.

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--docs-dir` | `~/.cupertino/docs` | Apple documentation directory (only used when `--save` is also passed) |
| `--evolution-dir` | `~/.cupertino/swift-evolution` | Swift Evolution proposals directory (only used when `--save` is also passed) |
| `--search-db` | `~/.cupertino/search.db` | Search database path |

## Default Health Check Process

The doctor command performs these checks using default paths:

### 1. Server Initialization ✅
```
✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25
```

Always passes (verifies code is working).

### 2. Packages Index (`packages.db`) 📦
```
📦 Packages Index (packages.db)
   ✓ Database: ~/.cupertino/packages.db
   ✓ Size: 988.9 MB
   ✓ Indexed files: 20186
   ℹ  Bundled version: 1.1.0
```

or

```
⚠  Database: ~/.cupertino/packages.db (not found)
   → Run: cupertino setup  (downloads the pre-built packages index)
```

### 3. Sample Code Index (`samples.db`) 🧪
```
🧪 Sample Code Index (samples.db)
   ✓ Database: ~/.cupertino/samples.db
   ✓ Size: 184.4 MB
   ✓ Projects: 619
   ✓ Indexed files: 18928
   ✓ Indexed symbols: 108536
```

### 4. Search Index (`search.db`) 🔍
```
🔍 Search Index
   ✓ Database: ~/.cupertino/search.db
   ✓ Size: 2.48 GB
   ✓ Schema version: 13 (matches installed binary)
   ✓ Frameworks: 420
   📚 Indexed sources:
     ✓ apple-docs: 284518 entries
     ✓ swift-evolution: 483 entries
```

or

```
✗ Database: ~/.cupertino/search.db (not found)
   → Run: cupertino setup  (or `cupertino save` if building locally)
```

### 5. Providers 🔧
```
🔧 Providers
   ✓ MCP.Support.DocsResourceProvider: available
   ✓ SearchToolProvider: available
```

### 6. Schema versions (#234)
```
8. Schema versions (#234)

   ✓ search.db: 13 (sequential), journal=wal
   ✓ packages.db: 2 (sequential), journal=delete
   ✓ samples.db: 3 (sequential), journal=wal
```

Anything other than `journal=wal` is flagged (the schema-version probe doubles as a WAL sanity check per [#236](https://github.com/mihaelamj/cupertino/issues/236)).

## Exit Codes

### Success (0)
```
✅ All checks passed - MCP server ready
```

All checks passed.

### Failure (1)
```
⚠️  Some checks failed - see above for details
```

One or more checks failed.

## Common Usage Patterns

### Quick Health Check (default)
```bash
cupertino doctor
```

### Include maintenance sections (corpus, packages selection, save preflight)
```bash
cupertino doctor --save
```

See [`--save`](save.md) for the full additive surface.

### Check Custom Search DB
```bash
cupertino doctor --search-db /opt/search.db
```

## Typical Output

### Fully Configured System
```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📦 Packages Index (packages.db)
   ✓ Database: ~/.cupertino/packages.db
   ✓ Size: 988.9 MB
   ✓ Indexed files: 20186
   ℹ  Bundled version: 1.1.0

🧪 Sample Code Index (samples.db)
   ✓ Database: ~/.cupertino/samples.db
   ✓ Size: 184.4 MB
   ✓ Projects: 619
   ✓ Indexed files: 18928
   ✓ Indexed symbols: 108536

🔍 Search Index
   ✓ Database: ~/.cupertino/search.db
   ✓ Size: 2.48 GB
   ✓ Schema version: 13 (matches installed binary)
   ✓ Frameworks: 420
   📚 Indexed sources:
     ✓ apple-docs: 284518 entries
     ✓ swift-evolution: 483 entries
     ✓ apple-archive: 368 entries
     ✓ hig: 173 entries
     ✓ swift-org: 115 entries
     ✓ swift-book: 78 entries

🔧 Providers
   ✓ MCP.Support.DocsResourceProvider: available
   ✓ SearchToolProvider: available


8. Schema versions (#234)

   ✓ search.db: 13 (sequential), journal=wal
   ✓ packages.db: 2 (sequential), journal=delete
   ✓ samples.db: 3 (sequential), journal=wal

✅ All checks passed - MCP server ready
```

(Output snapshots a v1.1.0 install; sizes / counts vary with your local DB. To also see corpus / packages / save-preflight state, run `cupertino doctor --save`.)

### Fresh Installation (no databases yet)
```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📦 Packages Index (packages.db)
   ⚠  Database: ~/.cupertino/packages.db (not found)
     → Run: cupertino setup  (downloads the pre-built packages index)

🧪 Sample Code Index (samples.db)
   ⚠  Database: ~/.cupertino/samples.db (not found)
     → Run: cupertino fetch --type samples && cupertino cleanup && cupertino save --samples

🔍 Search Index
   ✗ Database: ~/.cupertino/search.db (not found)
     → Run: cupertino setup  (or `cupertino save` if building locally)

🔧 Providers
   ✓ MCP.Support.DocsResourceProvider: available
   ✓ SearchToolProvider: available

⚠️  Some checks failed - see above for details
```

## Recommended Workflow

1. **Run doctor first:**
   ```bash
   cupertino doctor
   ```

2. **If databases are missing, run setup (downloads the pre-built bundle):**
   ```bash
   cupertino setup
   ```

3. **Verify setup:**
   ```bash
   cupertino doctor
   ```

4. **Start server:**
   ```bash
   cupertino serve
   ```

For maintainers rebuilding locally, see [`--save`](save.md) and the `cupertino fetch` + `cupertino save` flow.

## Notes

- Default focus is the runtime surface: MCP server health + the three databases. Corpus + package-selection state is opt-in via [`--save`](save.md).
- Defaults match `cupertino fetch`, `cupertino save`, and `cupertino serve`.
- All paths support tilde (`~`) expansion.
- Use before starting server to verify setup.
- Exit code suitable for CI/CD pipelines.
- Provides actionable remediation commands.
- Use `--help` to see all options.

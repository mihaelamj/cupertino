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
  --search-db ~/.cupertino/apple-documentation.db
```

Default output focuses on **database + MCP health**. Raw corpus directories and Swift-package selection state moved behind [`--save`](save.md) in [#68](https://github.com/mihaelamj/cupertino/issues/68) because a `cupertino setup` user has no raw corpus on disk (the bundle ships pre-built DBs); the previous `0 files` line under "Apple docs" looked like a failure and isn't.

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--docs-dir` | `~/.cupertino/docs` | Apple documentation directory (only used when `--save` is also passed) |
| `--evolution-dir` | `~/.cupertino/swift-evolution` | Swift Evolution proposals directory (only used when `--save` is also passed) |
| `--search-db` | `~/.cupertino/apple-documentation.db` | apple-docs database path (legacy flag name) |

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

### 3. Sample Code Index (`apple-sample-code.db`) 🧪
```
🧪 Sample Code Index (apple-sample-code.db)
   ✓ Database: ~/.cupertino/apple-sample-code.db
   ✓ Size: 184.4 MB
   ✓ Projects: 619
   ✓ Indexed files: 18928
   ✓ Indexed symbols: 108536
```

### 4. Per-source documentation indexes 🔍
```
🔍 Search Index
   ⚠  search.db: not found (legacy unified DB; superseded by the per-source DBs in v1.3.0)

🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: ~/.cupertino/apple-documentation.db
   ✓ Size: 2.82 GB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 398
   📚 Indexed sources:
     ✓ apple-docs: 351505 entries

   … one 🔍 section per source follows (hig.db, apple-archive.db,
     swift-evolution.db, swift-org.db, swift-book.db), each with size,
     schema 18, and framework + entry counts
```

or

```
✗ Database: ~/.cupertino/apple-documentation.db (not found)
   → Run: cupertino setup  (or `cupertino save --source apple-docs` if building locally)
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

   ⚠ search.db: not found (legacy unified DB; superseded by per-source DBs)
   ✓ apple-documentation.db: 18 (sequential), journal=wal
   ✓ hig.db: 18 (sequential), journal=wal
   ✓ apple-archive.db: 18 (sequential), journal=wal
   ✓ swift-evolution.db: 18 (sequential), journal=wal
   ✓ swift-org.db: 18 (sequential), journal=wal
   ✓ swift-book.db: 18 (sequential), journal=wal
   ✓ packages.db: 5 (sequential), journal=delete (read-only distribution mode)
   ✓ apple-sample-code.db: 4 (sequential), journal=delete (read-only distribution mode)
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
cupertino doctor --search-db /opt/apple-documentation.db
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

🧪 Sample Code Index (apple-sample-code.db)
   ✓ Database: ~/.cupertino/apple-sample-code.db
   ✓ Size: 184.4 MB
   ✓ Projects: 619
   ✓ Indexed files: 18928
   ✓ Indexed symbols: 108536

🔍 Search Index
   ⚠  search.db: not found (legacy unified DB; superseded by the per-source DBs in v1.3.0)

🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: ~/.cupertino/apple-documentation.db
   ✓ Size: 2.82 GB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 398
   📚 Indexed sources:
     ✓ apple-docs: 351505 entries

   … one 🔍 section per source follows (hig.db, apple-archive.db,
     swift-evolution.db, swift-org.db, swift-book.db), each with size,
     schema 18, and framework + entry counts

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

(Output snapshots a v1.3.0 install; sizes / counts vary with your local DB. To also see corpus / packages / save-preflight state, run `cupertino doctor --save`.)

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

🧪 Sample Code Index (apple-sample-code.db)
   ⚠  Database: ~/.cupertino/apple-sample-code.db (not found)
     → Run: cupertino fetch --source samples && cupertino cleanup && cupertino save --source samples

🔍 Search Index
   ✗ Database: ~/.cupertino/apple-documentation.db (not found)
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

- Default focus is the runtime surface: MCP server health + the bundled databases (the per-source docs DBs, `packages.db`, `apple-sample-code.db`). Corpus + package-selection state is opt-in via [`--save`](save.md).
- Defaults match `cupertino fetch`, `cupertino save`, and `cupertino serve`.
- All paths support tilde (`~`) expansion.
- Use before starting server to verify setup.
- Exit code suitable for CI/CD pipelines.
- Provides actionable remediation commands.
- Use `--help` to see all options.

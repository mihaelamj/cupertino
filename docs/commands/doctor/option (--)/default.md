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

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--docs-dir` | `~/.cupertino/docs` | Apple documentation directory |
| `--evolution-dir` | `~/.cupertino/swift-evolution` | Swift Evolution proposals directory |
| `--search-db` | `~/.cupertino/search.db` | Search database path |

## Health Check Process

The doctor command performs these checks using default paths:

### 1. Server Initialization ✅
```
✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25
```

Always passes (verifies code is working).

### 2. Documentation Directories 📚

**Apple Docs Check:**
```
✓ Apple docs: ~/.cupertino/docs (13,842 files)
```

or

```
✗ Apple docs: ~/.cupertino/docs (not found)
  → Run: cupertino fetch --type docs
```

**Swift Evolution Check:**
```
✓ Swift Evolution: ~/.cupertino/swift-evolution (414 proposals)
```

or

```
⚠  Swift Evolution: ~/.cupertino/swift-evolution (not found)
  → Run: cupertino fetch --type evolution
```

### 3. Search Index 🔍

**Database exists:**
```
✓ Database: ~/.cupertino/search.db
✓ Size: 52.3 MB
✓ Frameworks: 287
```

**Database missing:**
```
✗ Database: ~/.cupertino/search.db (not found)
  → Run: cupertino save
```

**Database corrupted:**
```
✗ Database error: unable to open database file
  → Run: cupertino save
```

### 4. Providers 🔧
```
✅ Providers
   ✓ DocsResourceProvider: available
   ✓ SearchToolProvider: available
```

Always passes (verifies providers can load).

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

### Quick Health Check (All Defaults)
```bash
cupertino doctor
```

### Check Custom Directories
```bash
cupertino doctor \
  --docs-dir ./my-docs \
  --search-db ./my-search.db
```

### Check Specific Installation
```bash
cupertino doctor \
  --docs-dir /opt/apple-docs \
  --evolution-dir /opt/swift-evolution \
  --search-db /opt/search.db
```

## Typical Output

### Fully Configured System
```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📂 Raw corpus directories (input for `cupertino save`)
   ✓ Apple docs: ~/.cupertino/docs
   ✓ Swift Evolution: ~/.cupertino/swift-evolution
   ✓ HIG: ~/.cupertino/hig
   ✓ Apple Archive: ~/.cupertino/archive

📦 Swift Packages
   ✓ User selections: ~/.cupertino/user-package-selections.json
   ✓ Package docs: 9,699 packages indexed
   ℹ  Priority packages: 135 total (Apple: 43, Ecosystem: 92)

📦 Packages Index (packages.db)
   ✓ Database: ~/.cupertino/packages.db (~150 MB)
   ✓ Schema version: 2 (matches binary)
   ✓ Bundled version: 1.0.3

🧪 Sample Code Index (samples.db)
   ✓ Database: ~/.cupertino/samples.db
   ✓ Indexed projects: hundreds

🔍 Search Index
   ✓ Database: ~/.cupertino/search.db
   ✓ Size: 2.5 GB
   ✓ Frameworks: 261
   ✓ Schema version: 12 (matches binary)

🔧 Providers
   ✓ DocsResourceProvider: available
   ✓ SearchToolProvider: available

✅ All checks passed - MCP server ready
```

(Output snapshots the v1.0 corpus; sizes / counts vary with your local DB.)

### Fresh Installation
```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📚 Documentation Directories
   ✗ Apple docs: ~/.cupertino/docs (not found)
     → Run: cupertino fetch --type docs
   ⚠  Swift Evolution: ~/.cupertino/swift-evolution (not found)
     → Run: cupertino fetch --type evolution

🔍 Search Index
   ✗ Database: ~/.cupertino/search.db (not found)
     → Run: cupertino save

🔧 Providers
   ✓ DocsResourceProvider: available
   ✓ SearchToolProvider: available

⚠️  Some checks failed - see above for details
```

## Recommended Workflow

1. **Run doctor first:**
   ```bash
   cupertino doctor
   ```

2. **Follow remediation steps:**
   ```bash
   cupertino fetch --type docs
   cupertino fetch --type evolution
   cupertino save
   ```

3. **Verify setup:**
   ```bash
   cupertino doctor
   ```

4. **Start server:**
   ```bash
   cupertino serve
   ```

## Notes

- Defaults match `cupertino fetch`, `cupertino save`, and `cupertino serve`
- All paths support tilde (`~`) expansion
- Use before starting server to verify setup
- Exit code suitable for CI/CD pipelines
- Provides actionable remediation commands
- Evolution directory is optional (shows warning, not error)
- Use `--help` to see all options

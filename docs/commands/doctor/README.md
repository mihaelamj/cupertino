# cupertino doctor

Check MCP server health and configuration

## Synopsis

```bash
cupertino doctor [options]
```

## Description

Verifies that the MCP server can start and all required components are available and properly configured.

This command performs comprehensive health checks on:
- **Server initialization** - Verify the MCP server can be created
- **Resource providers** - Check documentation resource providers
- **Tool providers** - Check search tool providers
- **Database connectivity** - Verify search database access
- **Documentation directories** - Confirm documentation exists

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
   ✓ Protocol version: 2025-06-18

📚 Documentation Directories
   ✓ Apple docs: /Users/username/.cupertino/docs (1234 files)
   ✓ Swift Evolution: /Users/username/.cupertino/swift-evolution (500 proposals)

🔍 Search Index
   ✓ Database: /Users/username/.cupertino/search.db
   ✓ Size: 45.2 MB
   ✓ Frameworks: 89

🔧 Providers
   ✓ DocsResourceProvider: available
   ✓ SearchToolProvider: available

✅ All checks passed - MCP server ready
```

### Missing Documentation

```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-06-18

📚 Documentation Directories
   ✗ Apple docs: /Users/username/.cupertino/docs (not found)
     → Run: cupertino fetch --type docs
   ⚠  Swift Evolution: /Users/username/.cupertino/swift-evolution (not found)
     → Run: cupertino fetch --type evolution

🔍 Search Index
   ✗ Database: /Users/username/.cupertino/search.db (not found)
     → Run: cupertino save

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
- Protocol version is correct (2025-06-18)

**Always passes** - checks basic server functionality.

### 2. Documentation Directories

Checks:
- **Apple docs**: Directory exists and contains `.md` files
- **Swift Evolution**: Directory exists and contains proposal files

Shows:
- Path to each directory
- Number of files/proposals found
- Suggestions if directories are missing

**Critical for Apple docs** - server needs at least one documentation source.
**Warning for Evolution** - server can work without it.

### 3. Search Index

Verifies:
- Search database file exists
- Database can be opened and queried
- Database contains indexed content

Shows:
- Database path
- File size
- Number of indexed frameworks

**Not critical** - server works without search, but tools won't be available.

### 4. Providers

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
✗ Database: /Users/username/.cupertino/search.db (not found)
  → Run: cupertino save
```

**Solution:**
```bash
cupertino save
```

### Database Error

**Problem:**
```
✗ Database error: unable to open database file
  → Run: cupertino save
```

**Possible causes:**
- Corrupted database file
- Permission issues
- Incomplete indexing

**Solution:**
```bash
# Rebuild the index
cupertino save --clear
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

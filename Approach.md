# Cupertino - Download & Index Approach

This document provides ready-to-use commands for downloading and indexing Apple documentation.

## Target Directory

All documentation will be stored in:
```
/Volumes/Code/DeveloperExt/private/cupertino
```

## Prerequisites

Ensure the binaries are installed:
```bash
which cupertino
which cupertino-mcp
```

If not installed, run from the project root:
```bash
cd /Volumes/Code/DeveloperExt/private/cupertino
sudo make install-symlinks
```

## Quick Start - Full Documentation

### 1. Download All Apple Documentation (~2-4 hours)

```bash
cupertino crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

**What this does:**
- Crawls all Apple documentation pages (15,000+ pages)
- Saves as Markdown files with metadata
- Creates directory structure: `/Volumes/Code/DeveloperExt/private/cupertino/docs/`
- Estimated time: 2-4 hours
- Estimated size: 2-3 GB

### 2. Download Swift Evolution Proposals (~2-5 minutes)

```bash
cupertino crawl-evolution \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution
```

**What this does:**
- Downloads all ~400 Swift Evolution proposals from GitHub
- Saves as Markdown files
- Creates directory: `/Volumes/Code/DeveloperExt/private/cupertino/swift-evolution/`
- Estimated time: 2-5 minutes
- Estimated size: 10-20 MB

### 3. Build Search Index (~2-5 minutes)

```bash
cupertino build-index \
  --docs-dir /Volumes/Code/DeveloperExt/private/cupertino/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution \
  --output /Volumes/Code/DeveloperExt/private/cupertino/search.db
```

**What this does:**
- Creates SQLite FTS5 full-text search index
- Indexes both Apple docs and Swift Evolution proposals
- Creates file: `/Volumes/Code/DeveloperExt/private/cupertino/search.db`
- Estimated time: 2-5 minutes
- Estimated size: ~50 MB

### 4. Start MCP Server

```bash
appledocsucker-mcp serve \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
  --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

**What this does:**
- Starts MCP server for AI agents (Claude Desktop)
- Serves documentation via Model Context Protocol
- Enables full-text search via MCP tools
- Press Ctrl+C to stop

---

## Quick Start - Minimal Test (5 minutes)

For testing or quick setup, use a smaller dataset:

### 1. Download Swift Documentation Only

```bash
cupertino crawl \
  --start-url "https://developer.apple.com/documentation/swift" \
  --max-pages 100 \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

### 2. Download Swift Evolution

```bash
cupertino crawl-evolution \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution
```

### 3. Build Search Index

```bash
cupertino build-index \
  --docs-dir /Volumes/Code/DeveloperExt/private/cupertino/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution \
  --output /Volumes/Code/DeveloperExt/private/cupertino/search.db
```

### 4. Test MCP Server

```bash
cupertino-mcp serve \
  --docs-dir /Volumes/Code/DeveloperExt/private/cupertino/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution \
  --search-db /Volumes/Code/DeveloperExt/private/cupertino/search.db
```

---

## Framework-Specific Downloads

### SwiftUI Only

```bash
cupertino crawl \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500 \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

### UIKit Only

```bash
cupertino crawl \
  --start-url "https://developer.apple.com/documentation/uikit" \
  --max-pages 1000 \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

### Foundation Only

```bash
cupertino crawl \
  --start-url "https://developer.apple.com/documentation/foundation" \
  --max-pages 800 \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

### Combine Only

```bash
cupertino crawl \
  --start-url "https://developer.apple.com/documentation/combine" \
  --max-pages 200 \
  --output-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

---

## Incremental Updates

After initial download, update existing documentation with changes:

```bash
cupertino update \
  --docs-dir /Volumes/Code/DeveloperExt/private/cupertino/docs
```

**What this does:**
- Re-crawls existing pages
- Only updates pages that have changed (checks content hash)
- Skips unchanged pages for efficiency
- Updates metadata with change detection

Then rebuild the search index:

```bash
cupertino build-index \
  --docs-dir /Volumes/Code/DeveloperExt/private/cupertino/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution \
  --output /Volumes/Code/DeveloperExt/private/cupertino/search.db
```

---

## Directory Structure After Full Download

```
/Volumes/Code/DeveloperExt/private/cupertino/
├── docs/                           # Apple documentation (2-3 GB)
│   ├── documentation_swift.md
│   ├── documentation_swiftui.md
│   ├── documentation_uikit.md
│   ├── ... (15,000+ files)
│   └── .cupertino_metadata.json    # Crawl metadata
├── swift-evolution/                # Swift Evolution proposals (10-20 MB)
│   ├── SE-0001.md
│   ├── SE-0002.md
│   ├── ... (400+ files)
│   └── .cupertino_metadata.json    # Crawl metadata
└── search.db                       # Search index (~50 MB)
```

---

## Configuration (Optional)

Create a config file at `~/.cupertino/config.json`:

```json
{
  "defaultDocsDir": "/Volumes/Code/DeveloperExt/private/cupertino/docs",
  "defaultEvolutionDir": "/Volumes/Code/DeveloperExt/private/cupertino/swift-evolution",
  "defaultSearchDB": "/Volumes/Code/DeveloperExt/private/cupertino/search.db",
  "maxConcurrentDownloads": 5,
  "requestDelayMs": 100
}
```

Then you can use shorter commands:

```bash
# With config file
cupertino crawl --max-pages 15000
cupertino build-index
cupertino-mcp serve
```

---

## Claude Desktop Integration

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino-mcp",
      "args": [
        "serve",
        "--docs-dir", "/Volumes/Code/DeveloperExt/private/cupertino/docs",
        "--evolution-dir", "/Volumes/Code/DeveloperExt/private/cupertino/swift-evolution",
        "--search-db", "/Volumes/Code/DeveloperExt/private/cupertino/search.db"
      ]
    }
  }
}
```

Restart Claude Desktop, then ask:
- "Show me the documentation for Swift Array"
- "Search for documentation about SwiftUI animations"
- "What does Swift Evolution proposal SE-0255 say?"

---

## Monitoring Progress

### View Live Logs

```bash
# In another terminal while crawling
log stream --predicate 'subsystem == "com.cupertino"'
```

### View Recent Logs

```bash
log show --predicate 'subsystem == "com.cupertino"' --last 1h
```

### View Specific Category

```bash
log show --predicate 'subsystem == "com.cupertino" AND category == "crawler"' --last 1h
```

---

## Troubleshooting

### Check Disk Space

```bash
df -h /Volumes/Code/DeveloperExt/
```

You need at least 3-4 GB free for full documentation.

### Verify Downloads

```bash
# Count downloaded files
find /Volumes/Code/DeveloperExt/private/cupertino/docs -name "*.md" | wc -l

# Check metadata
cat /Volumes/Code/DeveloperExt/private/cupertino/docs/.cupertino_metadata.json
```

### Verify Search Index

```bash
# Check database exists
ls -lh /Volumes/Code/DeveloperExt/private/cupertino/search.db

# Count indexed documents
sqlite3 /Volumes/Code/DeveloperExt/private/cupertino/search.db "SELECT COUNT(*) FROM docs_fts;"
```

### Resume Interrupted Download

If a crawl is interrupted, simply run the same command again. Cupertino will:
- Read existing metadata
- Skip already-downloaded pages
- Continue from where it left off

---

## Performance Notes

### Crawling Speed
- **Rate limiting:** ~10 pages/second (respects Apple's servers)
- **Network speed:** Depends on your connection
- **Parallel downloads:** 5 concurrent connections (configurable)

### Storage Requirements
- **Full Apple docs:** 2-3 GB (15,000+ pages)
- **Swift Evolution:** 10-20 MB (400+ proposals)
- **Search index:** ~50 MB
- **Total:** ~3 GB

### Memory Usage
- **Crawler:** ~50-100 MB
- **Search indexer:** ~200-300 MB (peak during indexing)
- **MCP server:** ~20-50 MB

---

## Next Steps

After completing the download and indexing:

1. **Test MCP Server:** Ask Claude to search documentation
2. **Set up auto-updates:** Create a cron job to run `cupertino update` weekly
3. **Explore search:** Use the `search_docs` MCP tool to find relevant documentation
4. **Export PDFs:** Use `cupertino export-pdf` to create PDF versions

See [README.md](README.md) and [DEVELOPMENT.md](DEVELOPMENT.md) for more details.

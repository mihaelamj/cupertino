# AppleDocsucker - Download & Index Approach

This document provides ready-to-use commands for downloading and indexing Apple documentation.

## Target Directory

All documentation will be stored in:
```
/Volumes/Code/DeveloperExt/appledocsucker
```

## Prerequisites

Ensure the binaries are installed:
```bash
which appledocsucker
which appledocsucker-mcp
```

If not installed, run from the project root:
```bash
cd /Volumes/Code/DeveloperExt/work/appledocsucker
sudo make install-symlinks
```

## Quick Start - Full Documentation

### 1. Download All Apple Documentation (~2-4 hours)

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

**What this does:**
- Crawls all Apple documentation pages (15,000+ pages)
- Saves as Markdown files with metadata
- Creates directory structure: `/Volumes/Code/DeveloperExt/appledocsucker/docs/`
- Estimated time: 2-4 hours
- Estimated size: 2-3 GB

### 2. Download Swift Evolution Proposals (~2-5 minutes)

```bash
appledocsucker crawl-evolution \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution
```

**What this does:**
- Downloads all ~400 Swift Evolution proposals from GitHub
- Saves as Markdown files
- Creates directory: `/Volumes/Code/DeveloperExt/appledocsucker/swift-evolution/`
- Estimated time: 2-5 minutes
- Estimated size: 10-20 MB

### 3. Build Search Index (~2-5 minutes)

```bash
appledocsucker build-index \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
  --output /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

**What this does:**
- Creates SQLite FTS5 full-text search index
- Indexes both Apple docs and Swift Evolution proposals
- Creates file: `/Volumes/Code/DeveloperExt/appledocsucker/search.db`
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
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/swift" \
  --max-pages 100 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

### 2. Download Swift Evolution

```bash
appledocsucker crawl-evolution \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution
```

### 3. Build Search Index

```bash
appledocsucker build-index \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
  --output /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

### 4. Test MCP Server

```bash
appledocsucker-mcp serve \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
  --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

---

## Framework-Specific Downloads

### SwiftUI Only

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

### UIKit Only

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/uikit" \
  --max-pages 1000 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

### Foundation Only

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/foundation" \
  --max-pages 800 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

### Combine Only

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/combine" \
  --max-pages 200 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

---

## Incremental Updates

After initial download, update existing documentation with changes:

```bash
appledocsucker update \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

**What this does:**
- Re-crawls existing pages
- Only updates pages that have changed (checks content hash)
- Skips unchanged pages for efficiency
- Updates metadata with change detection

Then rebuild the search index:

```bash
appledocsucker build-index \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
  --output /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

---

## Directory Structure After Full Download

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── docs/                           # Apple documentation (2-3 GB)
│   ├── documentation_swift.md
│   ├── documentation_swiftui.md
│   ├── documentation_uikit.md
│   ├── ... (15,000+ files)
│   └── .docsucker_metadata.json    # Crawl metadata
├── swift-evolution/                # Swift Evolution proposals (10-20 MB)
│   ├── SE-0001.md
│   ├── SE-0002.md
│   ├── ... (400+ files)
│   └── .docsucker_metadata.json    # Crawl metadata
└── search.db                       # Search index (~50 MB)
```

---

## Configuration (Optional)

Create a config file at `~/.docsucker/config.json`:

```json
{
  "defaultDocsDir": "/Volumes/Code/DeveloperExt/appledocsucker/docs",
  "defaultEvolutionDir": "/Volumes/Code/DeveloperExt/appledocsucker/swift-evolution",
  "defaultSearchDB": "/Volumes/Code/DeveloperExt/appledocsucker/search.db",
  "maxConcurrentDownloads": 5,
  "requestDelayMs": 100
}
```

Then you can use shorter commands:

```bash
# With config file
appledocsucker crawl --max-pages 15000
appledocsucker build-index
appledocsucker-mcp serve
```

---

## Claude Desktop Integration

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "appledocsucker": {
      "command": "/usr/local/bin/appledocsucker-mcp",
      "args": [
        "serve",
        "--docs-dir", "/Volumes/Code/DeveloperExt/appledocsucker/docs",
        "--evolution-dir", "/Volumes/Code/DeveloperExt/appledocsucker/swift-evolution",
        "--search-db", "/Volumes/Code/DeveloperExt/appledocsucker/search.db"
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
log stream --predicate 'subsystem == "com.docsucker.appledocsucker"'
```

### View Recent Logs

```bash
log show --predicate 'subsystem == "com.docsucker.appledocsucker"' --last 1h
```

### View Specific Category

```bash
log show --predicate 'subsystem == "com.docsucker.appledocsucker" AND category == "crawler"' --last 1h
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
find /Volumes/Code/DeveloperExt/appledocsucker/docs -name "*.md" | wc -l

# Check metadata
cat /Volumes/Code/DeveloperExt/appledocsucker/docs/.docsucker_metadata.json
```

### Verify Search Index

```bash
# Check database exists
ls -lh /Volumes/Code/DeveloperExt/appledocsucker/search.db

# Count indexed documents
sqlite3 /Volumes/Code/DeveloperExt/appledocsucker/search.db "SELECT COUNT(*) FROM docs_fts;"
```

### Resume Interrupted Download

If a crawl is interrupted, simply run the same command again. AppleDocsucker will:
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
2. **Set up auto-updates:** Create a cron job to run `appledocsucker update` weekly
3. **Explore search:** Use the `search_docs` MCP tool to find relevant documentation
4. **Export PDFs:** Use `appledocsucker export-pdf` to create PDF versions

See [README.md](README.md) and [DEVELOPMENT.md](DEVELOPMENT.md) for more details.

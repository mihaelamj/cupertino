# cupertino serve

Start the MCP server

## Synopsis

```bash
cupertino serve [options]
```

## Description

Starts the Model Context Protocol (MCP) server that provides documentation search and access capabilities for AI assistants like Claude.

The server communicates via stdio using JSON-RPC and provides:
- **Resource providers** for documentation access
- **Search tools** for querying indexed documentation

The server runs indefinitely until terminated (Ctrl+C).

## Default Command

The `cupertino` binary defaults to `serve`, so these commands are equivalent:

```bash
cupertino
cupertino serve
```

This makes it easy to configure in MCP client applications - you only need to specify the binary path.

## Options

### --docs-dir

Directory containing Apple documentation.

**Type:** String
**Default:** `~/.cupertino/docs`

**Example:**
```bash
cupertino serve --docs-dir ~/my-custom-docs
```

### --evolution-dir

Directory containing Swift Evolution proposals.

**Type:** String
**Default:** `~/.cupertino/swift-evolution`

**Example:**
```bash
cupertino serve --evolution-dir ~/my-evolution
```

### --search-db

Path to the search database file.

**Type:** String
**Default:** `~/.cupertino/search.db`

**Example:**
```bash
cupertino serve --search-db ~/my-search.db
```

## Prerequisites

Before starting the MCP server, you need:

1. **Downloaded documentation**:
   ```bash
   cupertino crawl --type docs
   cupertino crawl --type evolution
   ```

2. **Search index** (recommended):
   ```bash
   cupertino index
   ```

Without documentation, the server will display a getting started guide and exit.

## Examples

### Start with Defaults

```bash
cupertino
```

The server will use:
- Docs: `~/.cupertino/docs`
- Evolution: `~/.cupertino/swift-evolution`
- Search DB: `~/.cupertino/search.db`

### Start with Custom Directories

```bash
cupertino serve \
  --docs-dir ~/custom/apple-docs \
  --evolution-dir ~/custom/evolution \
  --search-db ~/custom/search.db
```

### Use in Claude Desktop Config

**File:** `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

No args needed - the binary defaults to `serve`!

### Use with Custom Directories in Claude

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino",
      "args": [
        "serve",
        "--docs-dir", "/Users/YOUR_USERNAME/my-docs",
        "--evolution-dir", "/Users/YOUR_USERNAME/my-evolution"
      ]
    }
  }
}
```

## Server Output

When the server starts successfully:

```
🚀 Cupertino MCP Server starting...
   Apple docs: /Users/username/.cupertino/docs
   Evolution: /Users/username/.cupertino/swift-evolution
   Search DB: /Users/username/.cupertino/search.db
   Waiting for client connection...
```

### With Search Index

```
✅ Search enabled (index found)
```

### Without Search Index

```
ℹ️  Search index not found at: /Users/username/.cupertino/search.db
   Tools will not be available. Run 'cupertino index' to enable search.
```

The server will still work for resource access, but search tools won't be available.

## Getting Started Guide

If you start the server without any documentation, you'll see:

```
╭─────────────────────────────────────────────────────────────────────────╮
│                                                                         │
│  👋 Welcome to Cupertino MCP Server!                                    │
│                                                                         │
│  No documentation found to serve. Let's get you started!                │
│                                                                         │
╰─────────────────────────────────────────────────────────────────────────╯

📚 STEP 1: Crawl Documentation
───────────────────────────────────────────────────────────────────────────
First, download the documentation you want to serve:

• Apple Developer Documentation (recommended):
  $ cupertino crawl --type docs

• Swift Evolution Proposals:
  $ cupertino crawl --type evolution

• Swift.org Documentation:
  $ cupertino crawl --type swift

⏱️  Crawling takes 10-30 minutes depending on content type.
   You can resume if interrupted with --resume flag.

🔍 STEP 2: Build Search Index
───────────────────────────────────────────────────────────────────────────
After crawling, create a search index for fast lookups:

  $ cupertino index

⏱️  Indexing typically takes 2-5 minutes.

🚀 STEP 3: Start the Server
───────────────────────────────────────────────────────────────────────────
Once you have data, start the MCP server:

  $ cupertino

The server will provide documentation access to AI assistants like Claude.
```

## Resource URIs

Once running, the server provides access via URI patterns:

### Apple Documentation

```
apple-docs://{framework}/{page}
```

**Examples:**
- `apple-docs://swift/array`
- `apple-docs://swiftui/view`
- `apple-docs://foundation/url`

### Swift Evolution Proposals

```
swift-evolution://{proposalID}
```

**Examples:**
- `swift-evolution://SE-0001`
- `swift-evolution://SE-0255`
- `swift-evolution://SE-0400`

## Search Tools

If a search index is available, the server provides search tools:

- **search** - Full-text search across all documentation
- **search_by_framework** - Search within a specific framework
- **list_frameworks** - List all indexed frameworks

## Stopping the Server

Press `Ctrl+C` to stop the server gracefully.

## Troubleshooting

### Server Won't Start

**Check if documentation exists:**
```bash
ls -la ~/.cupertino/docs
ls -la ~/.cupertino/swift-evolution
```

**Solution:** Download documentation first:
```bash
cupertino crawl --type docs
cupertino crawl --type evolution
```

### No Search Tools Available

**Check if index exists:**
```bash
ls -la ~/.cupertino/search.db
```

**Solution:** Build the search index:
```bash
cupertino index
```

### Binary Not Found

**Check installation:**
```bash
which cupertino
# or
ls -la /usr/local/bin/cupertino
```

**Solution:** Install the binary:
```bash
cd Packages
swift build -c release --product cupertino
cp .build/release/cupertino /usr/local/bin/
```

### Client Can't Connect

**Verify config syntax (Claude Desktop):**
```bash
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json | python3 -m json.tool
```

**Check logs:**
- Claude Desktop: Settings → Developer → View Logs
- Look for errors related to "cupertino"

## See Also

- [doctor](../doctor/) - Check server health
- [../../MCP_SERVER_README.md](../../MCP_SERVER_README.md) - Detailed server guide
- [../crawl/](../crawl/) - Download documentation
- [../index/](../index/) - Build search index

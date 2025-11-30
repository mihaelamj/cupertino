why don't I see any changes to docs'# Default Options Behavior

When no options are specified for `serve` command

## Synopsis

```bash
cupertino serve
```

or simply:

```bash
cupertino
```

(serve is the default subcommand)

## Default Behavior

When you run `cupertino serve` without any options, it uses these defaults:

```bash
cupertino serve \
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

## Startup Behavior

The serve command will:

1. **Check for data** - Verify at least one source exists
2. **Initialize MCP server** - Create server instance
3. **Register providers** - Based on available data
4. **Connect transport** - Start stdio communication
5. **Wait for clients** - Run indefinitely

## Data Source Requirements

At least **ONE** of the following must exist:
- Apple documentation (`--docs-dir`)
- Swift Evolution proposals (`--evolution-dir`)
- Search database (`--search-db`)

If **none** exist, server shows getting started guide and exits.

## Expected Directory Structure

```
~/.cupertino/
├── docs/                          # --docs-dir
│   ├── metadata.json
│   ├── Foundation/
│   └── SwiftUI/
├── swift-evolution/               # --evolution-dir
│   ├── SE-0001.md
│   └── SE-0296.md
└── search.db                      # --search-db
```

## Provider Registration

Based on what's available:

### All Data Available
```
🚀 Cupertino MCP Server starting...
   Apple docs: ~/.cupertino/docs
   Evolution: ~/.cupertino/swift-evolution
   Search DB: ~/.cupertino/search.db
✅ Search enabled (index found)
   Waiting for client connection...
```

**Provides:**
- `apple-docs://` resources (DocsResourceProvider)
- `swift-evolution://` resources (EvolutionResourceProvider)
- `search_docs` tool (SearchToolProvider)
- `list_frameworks` tool (SearchToolProvider)

### Docs Only
```
🚀 Cupertino MCP Server starting...
   Apple docs: ~/.cupertino/docs
   Evolution: ~/.cupertino/swift-evolution
   Search DB: ~/.cupertino/search.db
ℹ️  Search index not found at: ~/.cupertino/search.db
   Tools will not be available. Run 'cupertino save' to enable search.
   Waiting for client connection...
```

**Provides:**
- `apple-docs://` resources only
- No search tools

### Nothing Available
```
👋 Welcome to Cupertino MCP Server!

No documentation found to serve. Let's get you started!

📚 STEP 1: Crawl Documentation
  $ cupertino fetch --type docs

🔍 STEP 2: Build Search Index
  $ cupertino save

🚀 STEP 3: Start the Server
  $ cupertino serve
```

Server exits with error.

## Common Usage Patterns

### Minimal (All Defaults)
```bash
cupertino
```

or

```bash
cupertino serve
```

### Custom Directories
```bash
cupertino serve \
  --docs-dir ./my-docs \
  --search-db ./my-search.db
```

### Docs Only
```bash
cupertino serve \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir /nonexistent
```

## Server Lifecycle

1. **Startup** - Registers providers, connects transport
2. **Running** - Processes MCP requests via stdio
3. **Shutdown** - Ctrl+C or client disconnect

The server runs **indefinitely** until:
- Ctrl+C (SIGINT)
- Client disconnects
- Fatal error

## Claude Desktop Integration

Default paths work automatically with Claude Desktop configuration:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

No options needed - uses all defaults.

## Notes

- Defaults match `cupertino fetch` and `cupertino save` output locations
- Minimal configuration for typical use
- Evolution and search are optional
- All paths support tilde (`~`) expansion
- Server auto-detects available data
- Use `cupertino doctor` to verify setup
- Use `--help` to see all options

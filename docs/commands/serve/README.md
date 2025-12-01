# cupertino serve

Start the MCP server

## Synopsis

```bash
cupertino serve
cupertino  # equivalent - serve is the default command
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

## Prerequisites

Before starting the MCP server, you need:

1. **Downloaded documentation**:
   ```bash
   cupertino fetch --type docs
   cupertino fetch --type evolution
   ```

2. **Search index** (recommended):
   ```bash
   cupertino save
   ```

Without documentation, the server will display a getting started guide and exit.

## Examples

### Start Server

```bash
cupertino
```

The server will use default paths:
- Docs: `~/.cupertino/docs`
- Evolution: `~/.cupertino/swift-evolution`
- Search DB: `~/.cupertino/search.db`

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
   Tools will not be available. Run 'cupertino save' to enable search.
```

The server will still work for resource access, but search tools won't be available.

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

## MCP Tools

If a search index is available, the server provides these tools:

### search_docs

Full-text search across all documentation.

**Parameters:**
- `query` (required): Search keywords
- `framework` (optional): Filter by framework name
- `limit` (optional): Max results (default: 20, max: 100)

### list_frameworks

List all indexed frameworks with document counts.

**Parameters:** None

### read_document

Read a document by URI. Returns the full document content in the requested format.

**Parameters:**
- `uri` (required): Document URI from search results
- `format` (optional): Output format - `json` or `markdown`

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
cupertino fetch --type docs
cupertino fetch --type evolution
```

### No Search Tools Available

**Check if index exists:**
```bash
ls -la ~/.cupertino/search.db
```

**Solution:** Build the search index:
```bash
cupertino save
```

## See Also

- [search](../search/) - Search documentation from CLI
- [doctor](../doctor/) - Check server health
- [fetch](../fetch/) - Download documentation
- [save](../save/) - Build search index

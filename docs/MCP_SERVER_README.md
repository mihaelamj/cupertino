# Cupertino MCP Server - Serve Documentation to AI Agents

An MCP (Model Context Protocol) server that provides Apple documentation and Swift Evolution proposals to AI agents like Claude.

## What is MCP?

MCP (Model Context Protocol) is a standardized protocol for providing context to AI models. It allows AI agents to:
- Browse available documentation resources
- Read specific documentation pages
- Search through documentation collections
- Access up-to-date information from your local documentation cache

## v0.2 Architecture

In v0.2, the MCP server is integrated into the main `cupertino` binary. The binary defaults to starting the MCP server when run without arguments, making configuration simpler.

## Features

- 🤖 **AI Agent Integration** - Works with Claude, Claude Code, and other MCP-compatible agents
- 📚 **Dual Documentation Sources** - Serves both Apple docs and Swift Evolution proposals
- 🔍 **Resource Templates** - Easy URI-based access patterns
- 📡 **Stdio Transport** - Standard input/output for seamless integration
- ⚡ **Fast Access** - Instant document retrieval from local cache

## Prerequisites

Before starting the MCP server, you need to download documentation:

```bash
# Download Apple documentation
cupertino fetch \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --output-dir ~/.cupertino/docs

# Download Swift Evolution proposals
cupertino fetch-evolution \
  --output-dir ~/.cupertino/swift-evolution
```

## Installation

### Build from source:

```bash
cd Packages
swift build --product cupertino
```

The executable will be at: `.build/debug/cupertino`

### Install to /usr/local/bin (optional):

```bash
swift build -c release --product cupertino
cp .build/release/cupertino /usr/local/bin/
```

## Usage

### Start the MCP Server

The `cupertino` binary defaults to starting the MCP server:

```bash
# Option 1: Run with default command (recommended for MCP)
cupertino

# Option 2: Explicit command
cupertino mcp serve \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir ~/.cupertino/swift-evolution
```

**Parameters:**
- `--docs-dir` - Directory containing Apple documentation (default: `~/.cupertino/docs`)
- `--evolution-dir` - Directory containing Swift Evolution proposals (default: `~/.cupertino/swift-evolution`)

The server communicates via stdin/stdout using JSON-RPC 2.0.

### Check Server Health

```bash
cupertino mcp doctor
```

This command verifies:
- Documentation directories exist
- Search database is accessible
- Required resources are available

## Integration with Claude Desktop

### 1. Configure Claude Desktop

Edit your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

**Linux**: `~/.config/Claude/claude_desktop_config.json`

**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

### 2. Add Cupertino MCP Server

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

**Note**: The `cupertino` binary defaults to `mcp serve`, so no args are needed. Replace `/usr/local/bin/cupertino` with the actual path to your binary:
- If installed globally: `/usr/local/bin/cupertino`
- If using build directory: `/path/to/Packages/.build/release/cupertino`

### 3. Custom Directories (Optional)

If you want to use custom documentation directories:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino",
      "args": [
        "mcp", "serve",
        "--docs-dir", "/Users/YOUR_USERNAME/my-docs",
        "--evolution-dir", "/Users/YOUR_USERNAME/my-evolution"
      ]
    }
  }
}
```

### 4. Restart Claude Desktop

After editing the config, restart Claude Desktop for changes to take effect.

## Integration with Claude Code (CLI)

### 1. Configure Claude Code

Edit your Claude Code MCP settings:

**macOS/Linux**: `~/.config/claude-code/mcp_settings.json`

### 2. Add Server Configuration

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

## Using the MCP Server

Once connected, AI agents can access documentation through resource URIs:

### Resource URI Patterns

#### Apple Documentation

```
apple-docs://{framework}/{page}
```

**Examples:**
- `apple-docs://swift/array`
- `apple-docs://swiftui/view`
- `apple-docs://foundation/url`

#### Swift Evolution Proposals

```
swift-evolution://{proposalID}
```

**Examples:**
- `swift-evolution://SE-0001`
- `swift-evolution://SE-0255`
- `swift-evolution://SE-0400`

### Example Queries for Claude

**"Show me the documentation for Swift Array"**
→ Claude will access: `apple-docs://swift/array`

**"What does Swift Evolution proposal SE-0255 say?"**
→ Claude will access: `swift-evolution://SE-0255`

**"Find documentation about SwiftUI views"**
→ Claude will list available SwiftUI resources

## Available MCP Operations

### 1. List Resources

The server provides a list of all available documentation resources:

```json
{
  "jsonrpc": "2.0",
  "method": "resources/list",
  "params": {}
}
```

**Response**: List of all Apple docs and Swift Evolution proposals with their URIs.

### 2. Read Resource

Fetch specific documentation content:

```json
{
  "jsonrpc": "2.0",
  "method": "resources/read",
  "params": {
    "uri": "apple-docs://swift/array"
  }
}
```

**Response**: Full markdown content of the documentation page.

### 3. List Resource Templates

Get available URI patterns:

```json
{
  "jsonrpc": "2.0",
  "method": "resources/templates/list",
  "params": {}
}
```

**Response**: Available URI templates with descriptions.

## Server Output

When the server starts, you'll see:

```
🚀 Cupertino MCP Server starting...
   Apple docs: /Users/username/.cupertino/docs
   Evolution: /Users/username/.cupertino/swift-evolution
   Waiting for client connection...
```

The server then communicates via JSON-RPC 2.0 over stdin/stdout.

## Troubleshooting

### Server Won't Start

**Check paths exist:**
```bash
ls ~/.cupertino/docs
ls ~/.cupertino/swift-evolution
```

**Check binary permissions:**
```bash
chmod +x /usr/local/bin/cupertino
```

### Claude Can't Find Server

**Verify binary path:**
```bash
which cupertino
# or
ls -la /usr/local/bin/cupertino
```

**Check Claude config syntax:**
```bash
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json | python3 -m json.tool
```

### No Documentation Available

**Make sure you downloaded docs first:**
```bash
cupertino fetch --max-pages 100 --output-dir ~/.cupertino/docs
cupertino fetch --type evolution --output-dir ~/.cupertino/swift-evolution
```

### Server Crashes

**Check logs in Claude Desktop:**
- Open Claude Desktop
- Go to Settings → Developer → View Logs
- Look for errors related to "cupertino"

## Manual Testing

You can test the MCP server manually using stdio:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"resources/list","params":{}}' | cupertino mcp serve
```

Expected output: JSON-RPC response with list of resources.

## Architecture

```
┌─────────────────┐
│  Claude/AI      │
│     Agent       │
└────────┬────────┘
         │ MCP Protocol
         │ (JSON-RPC 2.0)
         │
┌────────▼────────────┐
│  cupertino          │
│  (MCP Server)       │
└────────┬────────────┘
         │
         ├─→ ~/.cupertino/docs/
         │   ├── swift/
         │   ├── swiftui/
         │   └── foundation/
         │
         └─→ ~/.cupertino/swift-evolution/
             ├── SE-0001-*.md
             ├── SE-0255-*.md
             └── SE-0400-*.md
```

### v0.2 Changes

- **Unified Binary:** No separate `cupertino-mcp` binary
- **Default Command:** `cupertino` defaults to `mcp serve`
- **Health Check:** New `cupertino mcp doctor` command

## Resource Organization

### Apple Documentation

Organized by framework in the docs directory:

```
~/.cupertino/docs/
├── swift/
│   ├── documentation_swift_array.md
│   ├── documentation_swift_string.md
│   └── ...
├── swiftui/
│   ├── documentation_swiftui_view.md
│   └── ...
└── foundation/
    ├── documentation_foundation_url.md
    └── ...
```

**URI mapping:**
- File: `swift/documentation_swift_array.md`
- URI: `apple-docs://swift/array`

### Swift Evolution Proposals

Stored as-is from GitHub:

```
~/.cupertino/swift-evolution/
├── SE-0001-keywords-as-argument-labels.md
├── SE-0002-remove-currying.md
├── SE-0255-omit-return.md
└── ...
```

**URI mapping:**
- File: `SE-0255-omit-return.md`
- URI: `swift-evolution://SE-0255`

## Example Use Cases

### 1. Code Assistance

**User**: "How do I use Swift's Array map function?"

**Claude** (via MCP):
1. Searches resources for "array"
2. Reads `apple-docs://swift/array`
3. Extracts map function documentation
4. Provides contextual answer

### 2. API Reference

**User**: "What are the properties of SwiftUI's Text view?"

**Claude** (via MCP):
1. Reads `apple-docs://swiftui/text`
2. Parses markdown for properties
3. Returns detailed property list

### 3. Evolution Proposals

**User**: "Explain the implicit return proposal"

**Claude** (via MCP):
1. Searches evolution proposals for "return"
2. Reads `swift-evolution://SE-0255`
3. Summarizes the proposal

### 4. Research Questions

**User**: "Show me all evolution proposals about async/await"

**Claude** (via MCP):
1. Lists all evolution resources
2. Filters for async-related proposals
3. Provides summary of each

## Performance

- **Startup time**: < 1 second
- **Resource list**: Instant (metadata cached)
- **Document read**: < 100ms (from local disk)
- **Memory usage**: ~10-50 MB

## Best Practices

1. **Keep docs updated**: Run `cupertino update` periodically
2. **Download before serving**: Ensure docs exist before starting server
3. **Use absolute paths**: In config, use full paths not ~
4. **Monitor logs**: Check Claude logs if issues occur
5. **Test manually**: Use echo test before integrating with Claude

## Security Notes

- Server only reads local files (no network access)
- Only serves files from specified directories
- No write operations performed
- Uses stdio (no network ports exposed)

## See Also

- [CLI README](./DOCSUCKER_CLI_README.md) - Download documentation
- [MCP Specification](https://spec.modelcontextprotocol.io/) - Protocol details
- [Claude Desktop](https://claude.ai/download) - Official Claude client

# cupertino serve

Start the MCP server

## Synopsis

```bash
cupertino serve
cupertino                                    # equivalent - serve is the default command
cupertino serve --base-dir /path/to/bundle   # serve indexes from a specific bundle
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
   cupertino fetch --source apple-docs
   cupertino fetch --source swift-evolution
   ```

2. **Search index** (recommended):
   ```bash
   cupertino save --all
   ```

Without documentation, the server will display a getting started guide and exit.

## Examples

### Start Server

```bash
cupertino
```

The server resolves its databases under the base directory (`~/.cupertino` by default, or `--base-dir <path>`). Post per-source-DB-split (#1036) the apple-docs primary search index is the per-source `apple-documentation.db`, resolved through the source registry, **not** the legacy monolithic `search.db`:
- Apple-docs search index: `~/.cupertino/apple-documentation.db`
- Samples DB: `~/.cupertino/apple-sample-code.db`
- Packages DB: `~/.cupertino/packages.db`

Pass `--base-dir <path>` to serve a bundle from anywhere (a dev snapshot, an alternate corpus) without a `cupertino.config.json` beside the binary. See [`option (--)/base-dir.md`](<option (--)/base-dir.md>).

## MCP Client Configuration

Cupertino uses **stdio transport** - MCP clients launch the server process automatically. You don't need to run the server manually.

> **Note:** Examples use `/opt/homebrew/bin/cupertino` (Homebrew on Apple Silicon). Use `/usr/local/bin/cupertino` for Intel Macs or manual installs. Run `which cupertino` to find your path.

### Claude Desktop

**File:** `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

### Claude Code

```bash
claude mcp add cupertino --scope user -- $(which cupertino)
```

### OpenAI Codex

```bash
codex mcp add cupertino -- $(which cupertino) serve --no-reap
```

Or add to `~/.codex/config.toml`:

```toml
[mcp_servers.cupertino]
command = "/opt/homebrew/bin/cupertino"
args = ["serve", "--no-reap"]
```

**Why `--no-reap`?** Codex spawns a fresh `cupertino serve` per tool call. Without `--no-reap`, each new instance kills its predecessor as a stale sibling and the in-flight transport closes (`Transport closed` error on every tool call, see #280). Equivalent env-var form: `CUPERTINO_DISABLE_REAPER=1` in `[mcp_servers.cupertino.env]`. Claude Desktop / Cursor users keep the default (reap on).

### Cursor

**File:** `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global)

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

### VS Code (GitHub Copilot)

**File:** `.vscode/mcp.json`

```json
{
  "servers": {
    "cupertino": {
      "type": "stdio",
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

### Zed

**File:** `settings.json`

```json
{
  "context_servers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

### Windsurf

**File:** `~/.codeium/windsurf/mcp_config.json`

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

### opencode

**File:** `opencode.jsonc`

```json
{
  "mcp": {
    "cupertino": {
      "type": "local",
      "command": ["/opt/homebrew/bin/cupertino", "serve"]
    }
  }
}
```

### Other MCP Clients

For other MCP clients, the general pattern is:
- **Command:** Path to cupertino binary
- **Args:** `["serve"]` (optional, serve is the default)
- **Transport:** stdio (not HTTP)

## Server Output

When the server starts successfully:

```
🚀 Cupertino MCP Server starting...
   Search DB: /Users/username/.cupertino/apple-documentation.db
   Samples DB: /Users/username/.cupertino/apple-sample-code.db
   Waiting for client connection...
```

Note: Only existing databases are shown. At least one database (search or samples) must exist for the server to start.

### With Search Index

```
✅ Search enabled (index found)
```

### Without Search Index

```
ℹ️  Search index not found at: /Users/username/.cupertino/apple-documentation.db
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

### search

Unified full-text search across every available source. Returns chunked excerpts ranked by reciprocal-rank fusion (RRF, k=60). Replaces the pre-#239 per-source tools (`search_docs`, `search_samples`, `search_all`, `search_hig`).

**Parameters:**
- `query` (required): Search keywords
- `source` (optional): Filter to a single source. Values: `apple-docs`, `samples`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`, `packages`, `all`. Omit for cross-source fan-out (default).
- `framework` (optional): Filter by framework name
- `language` (optional): Filter by language (swift, objc)
- `limit` (optional): Max results (default: 20, max: 100)

### list_frameworks

List all indexed frameworks with document counts.

**Parameters:** None

### read_document

Read a document by URI. Returns the full document content in the requested format.

**Parameters:**
- `uri` (required): Document URI from search results
- `format` (optional): Output format - `json` or `markdown`

## Sample Code Tools

If sample code is indexed (via `cupertino save --source samples`), the server provides these additional tools (and the unified `search` tool above accepts `source: "samples"`):

### list_samples

List all indexed sample code projects.

**Parameters:**
- `framework` (optional): Filter by framework name
- `limit` (optional): Max results (default: 50, max: 100)

### read_sample

Read a sample project's README and metadata.

**Parameters:**
- `project_id` (required): Sample project ID from search results

### read_sample_file

Read a specific source file from a sample project.

**Parameters:**
- `project_id` (required): Sample project ID
- `file_path` (required): Path to file within the project

## AST Symbol Tools

If a search index is available, the server also provides these AST-derived symbol tools (added in [#948](https://github.com/mihaelamj/cupertino/issues/948)). Each mirrors a `cupertino search-*` / `cupertino inheritance` CLI command. The five `min_*` platform filters AND-combine and apply to sources whose data carries availability metadata.

### search_symbols

Search the AST symbol index by name, kind, async, and framework.

**Parameters:**
- `query` (optional): Symbol name pattern (partial, case-insensitive match)
- `kind` (optional): Symbol kind (`struct`, `class`, `actor`, `enum`, `protocol`, `function`, `property`, ...)
- `is_async` (optional): Match only `async` symbols
- `framework` (optional): Framework filter (e.g. `swiftui`, `foundation`)
- `limit` (optional): Max results (default: 20)
- `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` (optional): Minimum platform-version filters

### search_property_wrappers

Find symbols whose declaration uses a given property wrapper.

**Parameters:**
- `wrapper` (required): Property wrapper name (with or without `@`)
- `framework` (optional): Framework filter
- `limit` (optional): Max results (default: 20)
- `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` (optional): Minimum platform-version filters

### search_concurrency

Find symbols using a Swift concurrency pattern.

**Parameters:**
- `pattern` (required): One of `async`, `actor`, `sendable`, `mainactor`, `task`, `asyncsequence`
- `framework` (optional): Framework filter
- `limit` (optional): Max results (default: 20)
- `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` (optional): Minimum platform-version filters

### search_conformances

Find symbols that conform to a given protocol.

**Parameters:**
- `protocol` (required): Protocol name (e.g. `View`, `Codable`, `Hashable`, `Sendable`)
- `framework` (optional): Framework filter
- `limit` (optional): Max results (default: 20)
- `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` (optional): Minimum platform-version filters

### search_generics

Find symbols with a generic-parameter constraint.

**Parameters:**
- `constraint` (required): Constraint type (e.g. `View`, `Hashable`, `Sendable`, `Codable`)
- `framework` (optional): Framework filter
- `limit` (optional): Max results (default: 20)
- `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` (optional): Minimum platform-version filters

### get_inheritance

Walk class-inheritance chains (UIKit / AppKit / Foundation class hierarchies). Returns ancestors, descendants, or both; an empty walk carries a kind-aware `No inheritance data` marker (root class, value type, or a pointer to `search_conformances` for protocols).

**Parameters:**
- `symbol` (required): Symbol name to walk from (e.g. `UIButton`, `NSView`)
- `direction` (optional): `up` (ancestors, default), `down` (descendants), or `both`
- `depth` (optional): Maximum walk depth (default: 5)
- `framework` (optional): Disambiguate when the symbol exists in multiple frameworks

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
cupertino fetch --source apple-docs
cupertino fetch --source swift-evolution
```

### No Search Tools Available

**Check if index exists:**
```bash
ls -la ~/.cupertino/apple-documentation.db
```

**Solution:** Build the search index:
```bash
cupertino save --all
```

## See Also

- [search](../search/) - Search documentation from CLI
- [doctor](../doctor/) - Check server health
- [fetch](../fetch/) - Download documentation
- [save](../save/) - Build search index

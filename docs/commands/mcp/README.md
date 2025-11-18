# cupertino mcp

MCP server operations

## Synopsis

```bash
cupertino mcp <subcommand> [options]
```

## Description

The `mcp` command provides operations for running and managing the Model Context Protocol (MCP) server. The MCP server provides documentation search and access capabilities for AI assistants like Claude.

In v0.2, the `cupertino` binary defaults to `mcp serve` when run without arguments, making it easy to start the server.

## Subcommands

- [serve](serve.md) - Start the MCP server (default)
- [doctor](doctor.md) - Check MCP server health and configuration

## Default Behavior

When you run `cupertino` without arguments, it automatically runs `cupertino mcp serve`:

```bash
# These are equivalent:
cupertino
cupertino mcp serve
```

## Quick Start

### 1. Download Documentation

Before starting the MCP server, download documentation:

```bash
# Apple Developer Documentation
cupertino crawl --type docs

# Swift Evolution Proposals
cupertino crawl --type evolution

# Swift.org Documentation
cupertino crawl --type swift
```

### 2. Build Search Index

Create a search index for fast lookups:

```bash
cupertino index
```

### 3. Start the Server

Start the MCP server:

```bash
cupertino
```

Or explicitly:

```bash
cupertino mcp serve
```

## Health Check

Verify your MCP server setup:

```bash
cupertino mcp doctor
```

This checks:
- Server initialization
- Resource providers
- Tool providers
- Database connectivity
- Documentation directories

## Integration

The MCP server is designed to integrate with AI assistants:

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

### Claude Code (CLI)

Add to `~/.config/claude-code/mcp_settings.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

## Common Options

All MCP commands support these options:

- `--docs-dir` - Directory containing Apple documentation (default: `~/.cupertino/docs`)
- `--evolution-dir` - Directory containing Swift Evolution proposals (default: `~/.cupertino/swift-evolution`)
- `--search-db` - Path to search database (default: `~/.cupertino/search.db`)

## Examples

### Start with Default Directories

```bash
cupertino mcp serve
```

### Start with Custom Directories

```bash
cupertino mcp serve \
  --docs-dir ~/my-docs \
  --evolution-dir ~/my-evolution
```

### Check Server Health

```bash
cupertino mcp doctor
```

## See Also

- [serve](serve.md) - Start the MCP server
- [doctor](doctor.md) - Health check
- [MCP_SERVER_README.md](../../MCP_SERVER_README.md) - Detailed server configuration
- [crawl](../crawl/) - Download documentation
- [index](../index/) - Build search index

# Cupertino Commands

CLI commands for the Cupertino documentation server.

## Commands

| Command | Description |
|---------|-------------|
| [fetch](fetch/) | Download documentation from Apple, Swift Evolution, and Swift.org |
| [save](save/) | Build FTS5 search index from downloaded documentation |
| [serve](serve/) | Start MCP server for AI agent access |
| [search](search/) | Search documentation from the command line |
| [read](read/) | Read full document content by URI |
| [doctor](doctor/) | Check server health and configuration |
| [cleanup](cleanup/) | Clean up downloaded sample code archives |

## Quick Reference

```bash
# Download documentation
cupertino fetch --type docs
cupertino fetch --type evolution

# Build search index
cupertino save

# Start MCP server (default command)
cupertino
cupertino serve

# Search documentation
cupertino search "SwiftUI View" --limit 10
cupertino search "async" --source swift-evolution

# Read full document
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown

# Check health
cupertino doctor
```

## Workflow

### Initial Setup

```bash
# 1. Download documentation (takes time)
cupertino fetch --type docs --max-pages 15000
cupertino fetch --type evolution

# 2. Build search index
cupertino save

# 3. Start server or use CLI
cupertino serve  # For MCP/AI agents
cupertino search "your query"  # For CLI usage
```

### Search and Read

```bash
# Search returns truncated summaries
cupertino search "MainActor" --limit 5

# Read full document when needed
cupertino read "apple-docs://swift/documentation_swift_mainactor" --format markdown
```

## See Also

- [MCP Tools](../tools/) - Tools available via MCP server
- [Artifacts](../artifacts/) - Downloaded documentation structure

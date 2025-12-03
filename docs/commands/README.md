# Cupertino Commands

CLI commands for the Cupertino documentation server.

## Commands

| Command | Description |
|---------|-------------|
| [fetch](fetch/) | Download documentation from Apple, Swift Evolution, Swift.org, and Apple Archive |
| [save](save/) | Build FTS5 search index from downloaded documentation |
| [index](index/) | Index sample code for full-text search |
| [serve](serve/) | Start MCP server for AI agent access |
| [search](search/) | Search documentation from the command line |
| [read](read/) | Read full document content by URI |
| [list-frameworks](list-frameworks/) | List available frameworks with document counts |
| [list-samples](list-samples/) | List indexed Apple sample code projects |
| [search-samples](search-samples/) | Search Apple sample code projects and files |
| [read-sample](read-sample/) | Read a sample project's README and metadata |
| [read-sample-file](read-sample-file/) | Read a source file from a sample project |
| [doctor](doctor/) | Check server health and configuration |
| [cleanup](cleanup/) | Clean up downloaded sample code archives |

## Quick Reference

```bash
# Download documentation
cupertino fetch --type docs
cupertino fetch --type evolution
cupertino fetch --type archive

# Build search index
cupertino save

# Start MCP server (default command)
cupertino
cupertino serve

# Search documentation
cupertino search "SwiftUI View" --limit 10
cupertino search "async" --source swift-evolution
cupertino search "Core Animation" --include-archive

# Read full document
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown

# List frameworks
cupertino list-frameworks

# Sample code commands
cupertino list-samples --limit 10
cupertino search-samples "SwiftUI" --framework swiftui
cupertino read-sample building-a-document-based-app-with-swiftui
cupertino read-sample-file building-a-document-based-app-with-swiftui ContentView.swift

# Check health
cupertino doctor
```

## Workflow

### Initial Setup

```bash
# 1. Download documentation (takes time)
cupertino fetch --type docs --max-pages 15000
cupertino fetch --type evolution
cupertino fetch --type archive  # Legacy programming guides

# 2. Build search index
cupertino save

# 3. Start server or use CLI
cupertino serve  # For MCP/AI agents
cupertino search "your query"  # For CLI usage
```

### Sample Code Setup

```bash
# Option 1: From GitHub (recommended - faster, no auth)
cupertino fetch --type samples
cupertino index

# Option 2: From Apple (slower, requires Apple ID)
cupertino fetch --type code --authenticate
cupertino cleanup
cupertino index
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

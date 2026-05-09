# Cupertino Commands

CLI commands for the Cupertino documentation server.

## Commands

| Command | Description |
|---------|-------------|
| [setup](setup/) | **Download pre-built databases from GitHub (fastest)** |
| [fetch](fetch/) | Download documentation from Apple, Swift Evolution, Swift.org, HIG, and Apple Archive |
| [save](save/) | Build FTS5 search indexes from downloaded documentation (search.db, samples.db, packages.db) |
| [serve](serve/) | Start MCP server for AI agent access |
| [search](search/) | Search documentation from the command line. Default fan-out across every source (replaces former `ask`); `--source <name>` filters to a single source |
| [package-search](package-search/) | Hidden: smart query scoped to packages.db only |
| [read](read/) | Read full document content by URI |
| [list-frameworks](list-frameworks/) | List available frameworks with document counts |
| [list-samples](list-samples/) | List indexed Apple sample code projects |
| [read-sample](read-sample/) | Read a sample project's README and metadata |
| [read-sample-file](read-sample-file/) | Read a source file from a sample project |
| [resolve-refs](resolve-refs/) | Rewrite unresolved `doc://` markers in saved page rawMarkdown |
| [doctor](doctor/) | Check server health and configuration |
| [cleanup](cleanup/) | Clean up downloaded sample code archives |

## Quick Reference

```bash
# Quick Setup (Recommended) - instant, no crawling
cupertino setup
cupertino serve

# Or download documentation manually
cupertino fetch --type docs
cupertino fetch --type evolution
cupertino fetch --type hig
cupertino fetch --type archive

# Build search index (from local files)
cupertino save

# Start MCP server (default command)
cupertino
cupertino serve

# Search documentation
cupertino search "SwiftUI View" --limit 10
cupertino search "async" --source swift-evolution
cupertino search "Core Animation" --include-archive
cupertino search "Observable" --min-ios 17.0  # Filter by iOS version

# Read full document
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown

# List frameworks
cupertino list-frameworks

# Sample code commands
cupertino list-samples --limit 10
cupertino search "SwiftUI" --source samples --framework swiftui
cupertino read-sample building-a-document-based-app-with-swiftui
cupertino read-sample-file building-a-document-based-app-with-swiftui ContentView.swift

# Check health
cupertino doctor
```

## Workflow

### Quick Setup (Recommended)

```bash
# Download pre-built databases (~30 seconds)
cupertino setup

# Start server
cupertino serve
```

### Manual Setup (Advanced)

```bash
# 1. Download documentation (takes time)
cupertino fetch --type docs      # Apple developer docs (full corpus, ~400k+ pages, multi-hour)
cupertino fetch --type evolution
cupertino fetch --type hig       # Human Interface Guidelines
cupertino fetch --type archive   # Legacy programming guides

# 2. Fetch availability data (adds iOS/macOS version info)
cupertino fetch --type availability

# 3. Build search index
cupertino save

# 4. Start server or use CLI
cupertino serve  # For MCP/AI agents
cupertino search "your query"  # For CLI usage
```

### Sample Code Setup

```bash
# Option 1: From GitHub (recommended - faster, no auth)
cupertino fetch --type samples
cupertino save --samples

# Option 2: From Apple (slower, requires Apple ID)
cupertino fetch --type code
cupertino cleanup
cupertino save --samples
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

# AppleDocsucker - Apple Documentation Crawler & MCP Server

A Swift toolset for downloading Apple documentation and Swift Evolution proposals, then serving them to AI agents via the Model Context Protocol (MCP).

[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15+-blue.svg)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Features

- 📚 **Download Apple Documentation** - Crawl and convert 15,000+ documentation pages to Markdown
- 🚀 **Swift Evolution Proposals** - Download all ~400 Swift Evolution proposals from GitHub
- 🔍 **Full-Text Search** - SQLite FTS5 index with BM25 ranking for fast keyword search
- 🤖 **MCP Server** - Serve documentation to AI agents like Claude via Model Context Protocol
- 💾 **Incremental Updates** - Smart change detection to avoid re-downloading unchanged content
- 📦 **Sample Code** - Download Apple sample code projects (requires Apple Developer account)

## Quick Start

> **Note:** All commands in this guide work from both the **root directory** (`appledocsucker/`) and the **Packages directory** (`appledocsucker/Packages/`). The root Makefile automatically delegates to Packages/Makefile.

### Installation

**Requirements:**
- macOS 15+ (Sequoia)
- Swift 6.2+
- Xcode 16.0+
- ~2-3 GB disk space for full documentation

**Build from source:**

```bash
git clone https://github.com/YOUR_USERNAME/appledocsucker.git
cd appledocsucker

# Option 1: Using Makefile (works from root or Packages directory)
make build                       # Build release binaries
sudo make install                # Install to /usr/local/bin

# Option 2: Using Swift Package Manager directly
cd Packages
swift build -c release

# Install manually (from Packages directory)
sudo ln -sf "$(pwd)/.build/release/appledocsucker" /usr/local/bin/appledocsucker
sudo ln -sf "$(pwd)/.build/release/appledocsucker-mcp" /usr/local/bin/appledocsucker-mcp
```

**Quick development workflow:**

```bash
# One-time setup (works from root or Packages directory)
make build                       # Build binaries
sudo make install                # Install to /usr/local/bin

# After making changes (works from root or Packages directory)
sudo make update                 # Rebuild and reinstall
```

### Download Documentation

```bash
# Download all Apple documentation (~2-4 hours)
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --output-dir ~/.docsucker/docs

# Download Swift Evolution proposals (~2-5 minutes)
appledocsucker crawl-evolution \
  --output-dir ~/.docsucker/swift-evolution

# Build search index (~2-5 minutes)
appledocsucker build-index
```

### Use with Claude Desktop

1. **Configure Claude Desktop** - Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "appledocsucker": {
      "command": "/usr/local/bin/appledocsucker-mcp",
      "args": ["serve"]
    }
  }
}
```

2. **Restart Claude Desktop**

3. **Ask Claude about Apple APIs:**
   - "Show me the documentation for Swift Array"
   - "Search for documentation about SwiftUI animations"
   - "What does Swift Evolution proposal SE-0255 say?"

## Available Commands

### CLI Tool (`appledocsucker`)

| Command | Description |
|---------|-------------|
| `crawl` | Download Apple documentation |
| `crawl-evolution` | Download Swift Evolution proposals |
| `download-samples` | Download Apple sample code projects |
| `build-index` | Build full-text search index |
| `export-pdf` | Export documentation to PDF |
| `update` | Incremental update of existing docs |
| `config` | Manage configuration |

### MCP Server (`appledocsucker-mcp`)

| Command | Description |
|---------|-------------|
| `serve` | Start MCP server for AI agents |

**MCP Resources:**
- `apple://documentation/*` - Read any Apple documentation page
- `evolution://SE-NNNN` - Read Swift Evolution proposals

**MCP Tools (requires search index):**
- `search_docs` - Search documentation by keywords
- `list_frameworks` - List all available frameworks

## Search Features

AppleDocsucker includes a powerful full-text search engine:

- **Technology:** SQLite FTS5 with BM25 ranking
- **Stemming:** Porter stemming for better matches (e.g., "running" matches "run")
- **Performance:** Sub-100ms search across 15,000+ pages
- **Size:** ~50MB index for full documentation

**Example searches:**
- `"async await concurrency"` - Find Swift concurrency documentation
- `"@Observable property wrapper"` - Search for property wrapper docs
- `"framework:swiftui animation"` - Filter by framework

## Build System

AppleDocsucker includes a comprehensive Makefile for easy building and installation.

**Works from either location:**
- Root directory: `cd appledocsucker && make build`
- Packages directory: `cd appledocsucker/Packages && make build`

```bash
# Show all available commands
make help

# Common tasks
make build                  # Build release binaries
sudo make install           # Install to /usr/local/bin
sudo make update            # Rebuild and reinstall
make test                   # Run all tests
make clean                  # Clean build artifacts
```

**Available make targets:**
- `build`, `build-debug`, `build-release` - Build executables
- `install` - Install to /usr/local/bin (requires sudo)
- `install-symlinks` - Install with symlinks (advanced, requires sudo)
- `update` - Quick rebuild for development workflow
- `test`, `test-unit`, `test-integration` - Run tests
- `clean`, `distclean` - Clean build artifacts
- `format`, `lint` - Code quality checks
- `archive`, `bottle` - Create distribution packages

> **Note:** All `make` commands work from both the root directory and the Packages directory. The root Makefile delegates to Packages/Makefile automatically.

## Documentation

- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Detailed build instructions, local development setup, and testing guide
- **[Packages/TESTING_GUIDE.md](Packages/TESTING_GUIDE.md)** - Comprehensive testing documentation
- **[Packages/HOMEBREW.md](Packages/HOMEBREW.md)** - Homebrew formula creation guide
- **[Packages/MCP_SERVER_README.md](Packages/MCP_SERVER_README.md)** - MCP server details
- **[Packages/DOCSUCKER_CLI_README.md](Packages/DOCSUCKER_CLI_README.md)** - CLI documentation

## Architecture

AppleDocsucker uses an **[ExtremePackaging](https://aleahim.com/blog/extreme-packaging/)** architecture with 9 packages:

```
Foundation Layer:
  ├─ MCPShared          # MCP protocol models
  ├─ DocsuckerLogging   # os.log infrastructure
  └─ DocsuckerShared    # Configuration & models

Infrastructure Layer:
  ├─ MCPTransport       # JSON-RPC transport (stdio)
  ├─ MCPServer          # MCP server implementation
  └─ DocsuckerCore      # Crawler & downloaders

Application Layer:
  ├─ DocsuckerSearch    # SQLite FTS5 search
  ├─ DocsuckerMCPSupport # Resource providers
  └─ DocsSearchToolProvider # Search tools

Executables:
  ├─ DocsuckerCLI       # CLI tool
  └─ DocsuckerMCP       # MCP server
```

## Logging

AppleDocsucker uses **os.log** for structured logging across all components:

```bash
# View all logs
log show --predicate 'subsystem == "com.docsucker.appledocsucker"' --last 1h

# View specific category
log show --predicate 'subsystem == "com.docsucker.appledocsucker" AND category == "crawler"' --last 1h

# Stream live logs
log stream --predicate 'subsystem == "com.docsucker.appledocsucker"'
```

**Categories:** crawler, mcp, search, cli, transport, pdf, evolution, samples

## Performance

| Operation | Time | Size |
|-----------|------|------|
| Build CLI | 10-15s | 4.3MB |
| Build MCP | 10-15s | 4.4MB |
| Crawl 15,000 pages | 2-4 hours | 2-3GB |
| Swift Evolution | 2-5 min | 10-20MB |
| Build search index | 2-5 min | ~50MB |
| Search query | <100ms | - |

## Example Use Cases

### 1. Offline Documentation Access

Download all documentation for offline development:

```bash
appledocsucker crawl --max-pages 15000 --output-dir ~/offline-docs
```

### 2. Framework-Specific Research

Download just SwiftUI documentation:

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500 \
  --output-dir ~/swiftui-docs
```

### 3. AI-Assisted Development

Serve documentation to Claude for code assistance:

```bash
appledocsucker-mcp serve
# Then ask Claude: "How do I use @Observable in SwiftUI?"
```

### 4. Documentation Search

Build searchable documentation archive:

```bash
appledocsucker build-index
# MCP server now provides search_docs tool to AI agents
```

## Contributing

Contributions are welcome! Please read [DEVELOPMENT.md](DEVELOPMENT.md) for:
- Local build setup
- Development workflow
- Testing guidelines
- Code style (SwiftFormat, SwiftLint)

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Built with Swift 6.2 and Swift Package Manager
- Uses [swift-argument-parser](https://github.com/apple/swift-argument-parser) for CLI
- Implements [Model Context Protocol](https://modelcontextprotocol.io) specification
- Inspired by the need for offline Apple documentation access

## Support

- **Issues:** [GitHub Issues](https://github.com/YOUR_USERNAME/appledocsucker/issues)
- **Discussions:** [GitHub Discussions](https://github.com/YOUR_USERNAME/appledocsucker/discussions)

---

**Note:** This tool is for educational and development purposes. Respect Apple's Terms of Service when using their documentation.

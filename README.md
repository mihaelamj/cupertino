# 🍎📚 Cupertino

**Apple Documentation Crawler & MCP Server**

A Swift-based tool to crawl, index, and serve Apple's developer documentation to AI agents via the Model Context Protocol (MCP).

[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15+-blue.svg)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## What is Cupertino?

Cupertino is a local, structured, AI-ready documentation system for Apple platforms. It:

- **Crawls** Apple Developer documentation, Swift.org, Swift Evolution proposals, and Swift package metadata
- **Indexes** everything into a fast, searchable SQLite FTS5 database with BM25 ranking
- **Serves** documentation to AI agents like Claude via the Model Context Protocol
- **Provides** offline access to 22,000+ documentation pages across 261 frameworks

### Why Build This?

- **No more hallucinations**: AI agents get accurate, up-to-date Apple API documentation
- **Offline development**: Work with full documentation without internet access
- **Deterministic search**: Same query always returns same results
- **Local control**: Own your documentation, inspect the database, script workflows
- **AI-first design**: Built specifically for AI agent integration via MCP

## Quick Start

> **Note:** All commands must be run from the Packages directory (`cupertino/Packages/`).

### Requirements

- macOS 15+ (Sequoia)
- Swift 6.2+
- Xcode 16.0+
- ~2-3 GB disk space for full documentation

### Installation

```bash
git clone https://github.com/mihaelamj/cupertino.git
cd cupertino

# Using Makefile (recommended)
make build                       # Build release binary
sudo make install                # Install to /usr/local/bin

# Or using Swift Package Manager directly
cd Packages
swift build -c release
sudo ln -sf "$(pwd)/.build/release/cupertino" /usr/local/bin/cupertino
```

### Download Documentation

```bash
# Download Apple documentation (~20-24 hours for 13,000+ pages)
# Takes time due to 0.5s default delay between requests to respect Apple's servers
cupertino fetch --type docs --max-pages 15000

# Download Swift Evolution proposals (~2-5 minutes)
cupertino fetch --type evolution

# Build search index (~2-5 minutes)
cupertino save
```

### Use with Claude Desktop

1. **Configure Claude Desktop** - Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino"
    }
  }
}
```

> **Note:** The `cupertino` command defaults to `cupertino serve` when run without arguments.

2. **Restart Claude Desktop**

3. **Ask Claude about Apple APIs:**
   - "Search for SwiftUI documentation"
   - "What does Swift Evolution proposal SE-0001 propose?"
   - "List available frameworks"

### What You Get

Once configured, Claude Desktop can search your local documentation:

**Search Results Example:**
```
# Search Results for "SwiftUI"

Found **20** results:

## 1. NSHostingView | Apple Developer Documentation
- **Framework:** `swiftui`
- **URI:** `apple-docs://swiftui/documentation_swiftui_nshostingview`
- **Score:** 1.82

An AppKit view that hosts a SwiftUI view hierarchy.

## 2. UIHostingController | Apple Developer Documentation
- **Framework:** `swiftui`
- **URI:** `apple-docs://swiftui/documentation_swiftui_uihostingcontroller`

A UIKit view controller that manages a SwiftUI view hierarchy.
...
```

**Framework Statistics:**
| Framework | Documents |
|-----------|----------:|
| SwiftUI | 5,853 |
| Swift | 2,814 |
| UIKit | 1,906 |
| AppKit | 1,316 |
| Foundation | 1,219 |
| Swift.org | 501 |
| Swift Evolution | 429 |
| ... | ... |
| **Total** | **22,044** |

## Core Features

### 1. Multi-Source Documentation Fetching

- **Apple Developer Documentation** (13,000+ pages)
  - JavaScript-aware rendering via WKWebView
  - HTML to Markdown conversion
  - Smart change detection

- **Swift Evolution Proposals** (~400 proposals)
  - GitHub-based fetching
  - Markdown format
  - Fast downloads

- **Swift.org Documentation**
  - Official Swift language docs
  - Clean HTML structure

- **Swift Package Metadata**
  - Priority package catalogs
  - README files
  - Sample code

### 2. Bundled Resources

Cupertino includes pre-indexed catalog data bundled directly into the application:

- **Swift Packages Catalog** (9,699 packages)
  - Manually curated from Swift Package Index + GitHub API
  - Includes package metadata, stars, licenses, descriptions
  - Updated periodically by maintainers

- **Sample Code Catalog** (606 entries)
  - Apple's official sample code projects
  - Includes titles, descriptions, frameworks, download URLs
  - Bundled because Apple's catalog doesn't change frequently

- **Priority Packages** (36 curated packages)
  - Apple official packages (31) + essential ecosystem packages (5)
  - High-priority Swift packages for quick access

These catalogs are indexed during `cupertino save` and enable instant search without requiring multi-hour downloads. You can still fetch package READMEs and sample code separately via `cupertino fetch` if needed.

### 3. Full-Text Search Engine

- **Technology**: SQLite FTS5 with BM25 ranking
- **Features**:
  - Porter stemming (e.g., "running" matches "run")
  - Framework filtering
  - Snippet generation
  - Sub-100ms query performance
- **Size**: ~160MB index for full documentation (22,000+ documents across 261 frameworks)
- **Storage**: Database must be on local filesystem - SQLite does not work reliably on network drives (NFS/SMB)

### 4. Model Context Protocol Server

- **Resources**: Direct access to documentation pages
  - `apple-docs://{framework}/{page}`
  - `swift-evolution://{proposal-id}`
- **Tools**: Search and read capabilities for AI agents
  - `search_docs` - Full-text search across all documentation
  - `list_frameworks` - List available frameworks
  - `read_document` - Read document by URI with format option
    - Parameters: `uri` (required), `format` (optional: `json` or `markdown`, default: `json`)
    - JSON format returns the full structured document data (recommended for AI)
    - Markdown format returns rendered content for human reading

### 5. Intelligent Crawling

- **Resumable**: Continue interrupted crawls from saved state
- **Change Detection**: Skip unchanged pages on updates
- **Respectful**: 0.5s default delay between requests (configurable)
- **Deduplication**: Automatic URL queue management
- **Priority Queues**: Important content fetched first

## Commands

| Command | Description |
|---------|-------------|
| `cupertino` | Start MCP server (default) |
| `cupertino serve` | Start MCP server |
| `cupertino fetch` | Download documentation |
| `cupertino save` | Build search index |
| `cupertino search` | Search documentation from CLI |
| `cupertino read` | Read full document by URI |
| `cupertino doctor` | Check server health |

See [docs/commands/](docs/commands/) for detailed usage and options.

## Architecture

Cupertino uses an **[ExtremePackaging](https://aleahim.com/blog/extreme-packaging/)** architecture with 9 consolidated packages:

```
Foundation Layer:
  ├─ MCP                    # Consolidated MCP framework (Protocol + Transport + Server)
  ├─ Logging                # os.log infrastructure
  └─ Shared                 # Configuration & models

Infrastructure Layer:
  ├─ Core                   # Crawler & downloaders
  └─ Search                 # SQLite FTS5 search

Application Layer:
  ├─ MCPSupport             # Resource providers
  ├─ SearchToolProvider     # Search tool implementations
  └─ Resources              # Embedded resources

Executables:
  ├─ CLI                    # Unified cupertino binary
  ├─ TUI                    # Terminal UI (cupertino-tui)
  └─ MockAIAgent            # Testing tool (mock-ai-agent)
```

### Data Flow

```
1. Fetch:  cupertino fetch --type docs
   ↓
   WKWebView → HTML → Markdown → disk (~/.cupertino/docs/)

2. Save:   cupertino save
   ↓
   Markdown files → SQLite FTS5 index (~/.cupertino/search.db)

3. Serve:  cupertino serve
   ↓
   MCP Server (stdio) ← JSON-RPC ← Claude Desktop
   ↓
   DocsResourceProvider + CupertinoSearchToolProvider
```

### Key Design Principles

- **Swift 6.2 Concurrency**: 100% strict concurrency checking with actors and async/await
- **Value Semantics**: Immutable structs by default, Sendable conformance
- **Actor Isolation**: @MainActor for WKWebView, actors for shared state
- **Explicit Dependencies**: No singletons, clear dependency injection
- **Separation of Concerns**: Crawling → Indexing → Serving as distinct phases

## Development

### Build System

```bash
# Show all available commands
make help

# Common tasks
make build                  # Build release binaries
sudo make install           # Install to /usr/local/bin
sudo make update            # Rebuild and reinstall
make test                   # Run all tests
make clean                  # Clean build artifacts

# Development workflow
make test-unit              # Fast unit tests only
make test-integration       # All tests (includes network calls)
make format                 # Format code with SwiftFormat
make lint                   # Lint with SwiftLint
```

### Testing

**Test Suite:**
- 93 tests across 7 test suites
- 100% pass rate
- ~350 seconds duration (includes real network crawling)

**Test Categories:**
- Web Crawl Tests - Real Apple documentation fetching
- Fetch Command Tests - Package/code downloading
- Save Command Tests - Search index building
- MCP Tests - Server health, tool/resource providers
- Core Tests - Search, logging, state management

### Logging

Cupertino uses **os.log** for structured logging:

```bash
# View all logs
log show --predicate 'subsystem == "com.cupertino"' --last 1h

# View specific category
log show --predicate 'subsystem == "com.cupertino" AND category == "crawler"' --last 1h

# Stream live logs
log stream --predicate 'subsystem == "com.cupertino"'
```

**Categories**: crawler, mcp, search, cli, transport, pdf, evolution, samples

## Performance

| Operation | Time | Size |
|-----------|------|------|
| Build CLI | 10-15s | 4.3MB |
| Crawl 21,000+ pages | 20-24 hours | 2-3GB |
| Swift Evolution | 2-5 min | 429 proposals |
| Swift.org docs | 5-10 min | 501 pages |
| Build search index | 2-5 min | ~160MB |
| Search query | <100ms | - |

### Why Crawling Takes 20+ Hours

The crawler respects Apple's servers with a **0.5 second default delay between each request** (configurable):
- 13,000 pages × 0.5s = 6,500 seconds (~1.8 hours minimum)
- Plus page rendering, parsing, and saving time
- **Total: ~20-24 hours for initial full crawl**

This is a **one-time operation**. Incremental updates use change detection to skip unchanged pages and complete much faster.

## Example Use Cases

### 1. Offline Documentation Archive

```bash
# Download everything for offline access
cupertino fetch --type docs --max-pages 15000
cupertino fetch --type evolution
cupertino save
```

### 2. Framework-Specific Research

```bash
# Just SwiftUI documentation
cupertino fetch --type docs \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500
```

### 3. AI-Assisted Development

```bash
# Serve documentation to Claude
cupertino serve

# Then ask Claude: "How do I use @Observable in SwiftUI?"
```

### 4. Custom Documentation Workflows

```bash
# Multiple sources with custom paths
cupertino fetch --type docs --output-dir ~/docs/apple
cupertino fetch --type evolution --output-dir ~/docs/evolution
cupertino save --base-dir ~/docs --search-db ~/docs/search.db
cupertino serve --docs-dir ~/docs/apple --search-db ~/docs/search.db
```

## Documentation

- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Build, test, contribute, and release workflow
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Technical deep-dives (Concurrency, MCP, WKWebView testing)
- **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Homebrew distribution and CI/CD setup
- **[docs/commands/](docs/commands/)** - Command-specific documentation

### Command Documentation

Each command has detailed documentation:
- [docs/commands/fetch/](docs/commands/fetch/) - Download documentation
- [docs/commands/save/](docs/commands/save/) - Build search indexes
- [docs/commands/serve/](docs/commands/serve/) - Start MCP server
- [docs/commands/search/](docs/commands/search/) - Search documentation from CLI
- [docs/commands/doctor/](docs/commands/doctor/) - Check server health

## Contributing

Issues and pull requests are welcome! I'd love to hear how you're using Cupertino with your AI workflow.

For questions and discussion, use [GitHub Discussions](https://github.com/mihaelamj/cupertino/discussions).

I prefer collaboration over competition — if you're working on something similar, let's find ways to work together.

Don't hesitate to submit a PR because of code style. I'd rather have your contribution than perfect formatting.

By participating in this project you agree to abide by the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/).

For development setup, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Project Status

**Version:** 0.1.6
**Status:** ✅ Production Ready

- ✅ All core functionality working
- ✅ 93 tests passing (100% pass rate)
- ✅ 0 lint violations
- ✅ Swift 6.2 compliant with 100% strict concurrency checking
- ✅ All production bugs resolved

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Built with Swift 6.2 and Swift Package Manager
- Uses [swift-argument-parser](https://github.com/apple/swift-argument-parser) for CLI
- Implements [Model Context Protocol](https://modelcontextprotocol.io) specification
- Inspired by the need for offline Apple documentation access

## Support

- **Issues:** [GitHub Issues](https://github.com/mihaelamj/cupertino/issues)
- **Discussions:** [GitHub Discussions](https://github.com/mihaelamj/cupertino/discussions)

---

**Note:** This tool is for educational and development purposes. Respect Apple's Terms of Service when using their documentation.

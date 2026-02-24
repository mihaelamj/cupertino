# 🍎📚 Cupertino

**Apple Documentation Crawler & MCP Server**

A Swift-based tool to crawl, index, and serve Apple's developer documentation to AI agents via the Model Context Protocol (MCP).

[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15+-blue.svg)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![PulseMCP](https://img.shields.io/badge/PulseMCP-listed-blue)](https://www.pulsemcp.com/servers/mihaelamj-cupertino)
[![LobeHub](https://img.shields.io/badge/LobeHub-listed-purple)](https://lobehub.com/mcp/mihaelamj-cupertino)

![Cupertino Demo](docs/images/cupertino.gif)

## What is Cupertino?

Cupertino is a local, structured, AI-ready documentation system for Apple platforms. It:

- **Crawls** Apple Developer documentation, Swift.org, Swift Evolution proposals, Human Interface Guidelines, Apple Archive legacy guides, and Swift package metadata
- **Indexes** everything into a fast, searchable SQLite FTS5 database with BM25 ranking
- **Serves** documentation to AI agents like Claude via the Model Context Protocol
- **Provides** offline access to 302,424+ documentation pages across 307 frameworks

### Why Build This?

- **No more hallucinations**: AI agents get accurate, up-to-date Apple API documentation
- **Offline development**: Work with full documentation without internet access
- **Deterministic search**: Same query always returns same results
- **Local control**: Own your documentation, inspect the database, script workflows
- **AI-first design**: Built specifically for AI agent integration via MCP

## Quick Start

> **Note:** When building from source, commands must be run from the `Packages` directory. The one-command install works from anywhere.

### Requirements

- macOS 15+ (Sequoia)
- ~2-3 GB disk space for full documentation

*Building from source additionally requires Swift 6.2+ and Xcode 16.0+*

### Installation

**One-command install (recommended):**

```bash
bash <(curl -sSL https://raw.githubusercontent.com/mihaelamj/cupertino/main/install.sh)
```

This downloads a pre-built, signed, and notarized universal binary, installs it to `/usr/local/bin`, and downloads the documentation databases.

**Or with Homebrew:**

```bash
brew tap mihaelamj/tap
brew install cupertino
cupertino setup
```

**Or build from source:**

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

**Demo Video:** [Watch on YouTube](https://youtu.be/B-mRdainTMA)

### Quick Reference

```bash
# Quick Setup (Recommended) - download pre-built databases (~30 seconds)
cupertino setup                      # Download databases from GitHub
cupertino serve                      # Start MCP server

# Alternative: Build from GitHub (~45 minutes)
cupertino save --remote              # Stream and build locally

# Or fetch documentation yourself
cupertino fetch --type docs          # Apple Developer Documentation
cupertino fetch --type swift         # Swift.org documentation
cupertino fetch --type evolution     # Swift Evolution proposals
cupertino fetch --type packages      # Swift package metadata
cupertino fetch --type package-docs  # Swift package READMEs
cupertino fetch --type code          # Sample code from Apple (requires auth)
cupertino fetch --type samples       # Sample code from GitHub (recommended)
cupertino fetch --type archive       # Apple Archive programming guides
cupertino fetch --type hig           # Human Interface Guidelines
cupertino fetch --type availability  # Platform availability data
cupertino fetch --type all           # All types in parallel

# Build indexes
cupertino save                       # Build documentation search index (from local files)
cupertino save --remote              # Build from GitHub (no local files needed)
cupertino index                      # Index sample code for search

# Start server
cupertino                            # Start MCP server (default command)
cupertino serve                      # Start MCP server (explicit)
```

### Instant Setup (Recommended)

```bash
# Download pre-built databases from GitHub (~30 seconds)
cupertino setup

# Start MCP server
cupertino serve
```

### Alternative: Build from GitHub

```bash
# Stream and build locally (~45 minutes)
# Use this if you want to build the database yourself
cupertino save --remote

# Start MCP server
cupertino serve
```

### Manual Setup (Advanced)

```bash
# Download Apple documentation (~12+ days for 301,000+ pages)
# Takes time due to 0.5s default delay between requests to respect Apple's servers
cupertino fetch --type docs --max-pages 15000

# Download Swift Evolution proposals (~2-5 minutes)
cupertino fetch --type evolution

# Download sample code from GitHub (~4 minutes, 606 projects)
cupertino fetch --type samples

# Build search index (~2-5 minutes)
cupertino save
```

### Use with Claude Desktop

1. **Configure Claude Desktop** - Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

> **Note:** Use `/opt/homebrew/bin/cupertino` for Homebrew on Apple Silicon, `/usr/local/bin/cupertino` for Intel or manual install. Run `which cupertino` to find your path.

2. **Restart Claude Desktop**

3. **Ask Claude about Apple APIs:**
   - "Search for SwiftUI documentation"
   - "What does Swift Evolution proposal SE-0001 propose?"
   - "List available frameworks"

### Use with Claude Code

If you're using [Claude Code](https://code.claude.com/docs/en/overview), you can add Cupertino as an MCP server with a single command:

```bash
claude mcp add cupertino --scope user -- $(which cupertino)
```

This registers Cupertino globally for all your projects. Claude Code will automatically have access to Apple documentation search.

### Use with OpenAI Codex

If you're using [OpenAI Codex](https://github.com/openai/codex), add Cupertino with:

```bash
codex mcp add cupertino -- $(which cupertino) serve
```

Or add directly to `~/.codex/config.toml`:

```toml
[mcp_servers.cupertino]
command = "/opt/homebrew/bin/cupertino"  # Homebrew on Apple Silicon
# command = "/usr/local/bin/cupertino"   # Intel Mac or manual install
args = ["serve"]
```

> **Tip:** Run `which cupertino` to find your installation path.

### Use with Cursor

Add to `.cursor/mcp.json` in your project (or `~/.cursor/mcp.json` for global access):

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

### Use with VS Code (GitHub Copilot)

Add to `.vscode/mcp.json` in your workspace:

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

### Use with Zed

Add to your Zed `settings.json`:

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

### Use with Windsurf

Add to `~/.codeium/windsurf/mcp_config.json`:

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

### Use with opencode

Add to `opencode.jsonc`:

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

> **Note:** All examples use `/opt/homebrew/bin/cupertino` (Homebrew on Apple Silicon). Use `/usr/local/bin/cupertino` for Intel Macs or manual installs. Run `which cupertino` to find your path.

### Use as an Agent Skill (No Server Required)

Cupertino can also be used as a stateless CLI skill without running an MCP server. This is useful for agents that support the [Agent Skills](https://agentskills.io) specification.

**Prerequisites:**

Install cupertino and download the databases first:
```bash
# Install via Homebrew or from source (see Installation above)
cupertino setup
```

**Option A: Install with OpenSkills (Recommended)**

[OpenSkills](https://github.com/numman-ali/openskills) is a universal skills loader that works with Claude Code, Cursor, Windsurf, Aider, and other AI coding agents.

```bash
# Install the cupertino skill from GitHub
npx openskills install mihaelamj/cupertino

# Sync to update AGENTS.md
npx openskills sync
```

For global installation (available in all projects):
```bash
npx openskills install mihaelamj/cupertino --global
```

For multi-agent setups (installs to `.agent/skills/` instead of `.claude/skills/`):
```bash
npx openskills install mihaelamj/cupertino --universal
```

**Option B: Manual Installation**

Copy the skill definition to your project or global skills directory:
```bash
# Clone this repo
git clone https://github.com/mihaelamj/cupertino.git

# For a single project
mkdir -p .claude/skills/cupertino
cp cupertino/.claude/skills/cupertino/SKILL.md .claude/skills/cupertino/

# Or for global use with Claude Code
mkdir -p ~/.claude/skills/cupertino
cp cupertino/.claude/skills/cupertino/SKILL.md ~/.claude/skills/cupertino/
```

**How It Works:**

The skill uses the CLI directly with JSON output, no server process needed:

```bash
# Search documentation
cupertino search "SwiftUI View" --format json

# Filter by source
cupertino search "NavigationStack" --source apple-docs --format json
cupertino search "button styles" --source samples --format json

# Read a document
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format json

# List frameworks
cupertino list-frameworks --format json

# List sample projects
cupertino list-samples --framework swiftui --format json
```

All commands support `--format json` for structured output that agents can parse.

**Available Sources:**
- `apple-docs` - Official Apple documentation (301,000+ pages)
- `samples` - Apple sample code projects
- `hig` - Human Interface Guidelines
- `swift-evolution` - Swift Evolution proposals
- `swift-org` - Swift.org documentation
- `swift-book` - The Swift Programming Language book
- `apple-archive` - Legacy programming guides
- `packages` - Swift package documentation

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
| Kernel | 39,396 |
| Matter | 24,320 |
| Swift | 17,466 |
| AppKit | 12,443 |
| Foundation | 12,423 |
| UIKit | 11,158 |
| Accelerate | 9,114 |
| SwiftUI | 7,062 |
| ... | ... |
| **307 Frameworks** | **302,424** |

## Core Features

### 1. Multi-Source Documentation Fetching

- **Apple Developer Documentation** (301,000+ pages)
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

- **Apple Sample Code** (606 projects)
  - Two fetch methods: GitHub (recommended) or Apple website
  - Full-text search across all source files
  - 18,000+ indexed Swift files

- **Apple Archive Legacy Guides** (~75 pages)
  - Pre-2016 programming guides (Core Animation, Quartz 2D, Core Text, etc.)
  - Deep conceptual knowledge not in modern docs
  - Excluded from search by default (use `--include-archive`)

- **Human Interface Guidelines**
  - Apple's official design guidelines for all platforms
  - Covers iOS, macOS, watchOS, visionOS, and tvOS
  - Design patterns, components, foundations, and best practices

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
  - Platform availability filtering (iOS/macOS version)
  - Snippet generation
  - Sub-100ms query performance
- **Size**: ~2.4GB index for full documentation (302,000+ documents across 307 frameworks)
- **Storage**: Database must be on local filesystem - SQLite does not work reliably on network drives (NFS/SMB)

### 4. Model Context Protocol Server

- **Resources**: Direct access to documentation pages
  - `apple-docs://{framework}/{page}`
  - `swift-evolution://{proposal-id}`
  - `hig://{category}/{page}`
- **Tools**: Search and read capabilities for AI agents
  - **Documentation Tools** (requires `cupertino save`):
    - `search_docs` - Full-text search across all documentation
      - Parameters: `query` (required), `source`, `framework`, `min_ios`, `min_macos`, `include_archive`, `limit` (all optional)
    - `search_hig` - Search Human Interface Guidelines
      - Parameters: `query` (required), `platform` (optional), `category` (optional), `limit` (optional)
    - `list_frameworks` - List available frameworks
    - `read_document` - Read document by URI with format option
      - Parameters: `uri` (required), `format` (optional: `json` or `markdown`, default: `json`)
      - JSON format returns the full structured document data (recommended for AI)
      - Markdown format returns rendered content for human reading
  - **Sample Code Tools** (requires `cupertino index`):
    - `search_samples` - Search sample code projects and files
    - `list_samples` - List all indexed sample projects
    - `read_sample` - Read sample project README and metadata
    - `read_sample_file` - Read specific source file from a sample

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
| `cupertino setup` | Download pre-built databases from GitHub |
| `cupertino serve` | Start MCP server |
| `cupertino fetch` | Download documentation |
| `cupertino save` | Build search index |
| `cupertino search` | Search documentation from CLI |
| `cupertino read` | Read full document by URI |
| `cupertino doctor` | Check server health |
| `cupertino index` | Index sample code for search |
| `cupertino cleanup` | Clean up sample code archives |

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
- 698 tests across 73 test suites
- ~35 seconds duration
- Includes unit tests, integration tests, and formatter tests

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
| Crawl 301,000+ pages | 12+ days | 2-3GB |
| Swift Evolution | 2-5 min | 429 proposals |
| Swift.org docs | 5-10 min | 501 pages |
| Build search index | 2-5 min | ~160MB |
| Search query | <100ms | - |

### Why Crawling Takes 12+ Days

The crawler respects Apple's servers with a **0.5 second default delay between each request** (configurable):
- 301,000 pages × 0.5s = 150,500 seconds (~42 hours minimum)
- Plus page rendering, parsing, and saving time
- Crawl must reach depth 21+ to get all documentation
- **Total: ~12+ days for initial full crawl**

Use `cupertino setup` to download pre-built databases instead (~30 seconds).

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

**Version:** 0.9.1
**Status:** 🚧 Active Development

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

## Related Repositories

- **[cupertino-desktop](https://github.com/mihaelamj/cupertino-desktop)** - Native macOS desktop app with graphical interface
- **[cupertino-docs](https://github.com/mihaelamj/cupertino-docs)** - Pre-built documentation archive for quick installation
- **[cupertino-sample-code](https://github.com/mihaelamj/cupertino-sample-code)** - Apple sample code repository mirror

The docs and sample-code repositories will be used by the planned `make install (full)` command (see [#52](https://github.com/mihaelamj/cupertino/issues/52)), providing pre-built documentation and sample code to avoid the initial 20+ hour crawl.

## Support

- **Issues:** [GitHub Issues](https://github.com/mihaelamj/cupertino/issues)
- **Discussions:** [GitHub Discussions](https://github.com/mihaelamj/cupertino/discussions)

---

**Note:** This tool is for educational and development purposes. Respect Apple's Terms of Service when using their documentation.

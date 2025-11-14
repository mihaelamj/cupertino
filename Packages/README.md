# Docsucker - Apple Documentation Crawler & MCP Server

A comprehensive Swift toolset for downloading Apple documentation and Swift Evolution proposals, then serving them to AI agents via the Model Context Protocol (MCP).

## Overview

Docsucker provides two powerful command-line tools:

1. **`docsucker`** - CLI crawler for downloading and converting Apple docs to Markdown
2. **`docsucker-mcp`** - MCP server for serving documentation to AI agents like Claude

## Quick Start

> **Note**: All commands in this guide assume you're in the `Packages` directory. Alternatively, you can run `make` commands from the **root directory** using the wrapper Makefile (e.g., `make build` instead of `cd Packages && make build`).

### 0.Test Locally

```bash
  # Download everything (will take 2-4 hours total)
  Packages/.build/debug/docsucker crawl \
    --start-url "https://developer.apple.com/documentation/" \
    --max-pages 15000 \
    --output-dir ~/.docsucker/docs

  Packages/.build/debug/docsucker crawl-evolution \
    --output-dir ~/.docsucker/swift-evolution
```

```bash

 # Build first (one time)
  swift build --package-path Packages

  # Then run CLI
  Packages/.build/debug/docsucker --help
  Packages/.build/debug/docsucker --version

  # Download some docs
  Packages/.build/debug/docsucker crawl \
    --start-url "https://developer.apple.com/documentation/swift/array" \
    --max-pages 3 \
    --output-dir ~/docsucker-test

  # Run MCP server
  Packages/.build/debug/docsucker-mcp serve

  # Or if you want shorter commands, you can add these aliases to your ~/.zshrc:

  alias docsucker='Packages/.build/debug/docsucker'
  alias docsucker-mcp='Packages/.build/debug/docsucker-mcp'

  Then just:
  docsucker --help
  docsucker-mcp serve
```

### 1. Build

```bash
cd Packages
swift build
```

### 2. Download Documentation

Download Apple documentation (this will take 2-4 hours for full docs):

```bash
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --output-dir ~/.docsucker/docs
```

Download Swift Evolution proposals (takes 2-5 minutes):

```bash
.build/debug/docsucker crawl-evolution \
  --output-dir ~/.docsucker/swift-evolution
```

Download Apple sample code projects (zip/tar files):

```bash
# First time - authenticate
.build/debug/docsucker download-samples \
  --authenticate \
  --output-dir ~/.docsucker/sample-code \
  --max-samples 100000

# Subsequent runs - reuses saved cookies
.build/debug/docsucker download-samples \
  --output-dir ~/.docsucker/sample-code \
  --max-samples 100
```

> **Note**: Use `--authenticate` flag on first run to sign in with your Apple Developer account. Authentication cookies are saved and reused automatically for subsequent downloads.

### 3. Serve to AI Agents

Start the MCP server:

```bash
.build/debug/docsucker-mcp serve \
  --docs-dir ~/.docsucker/docs \
  --evolution-dir ~/.docsucker/swift-evolution
```

### 4. Configure Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "docsucker": {
      "command": "/usr/local/bin/docsucker-mcp",
      "args": ["serve"]
    }
  }
}
```

## How to Download Documentation

### Complete Download (Everything)

To download all available documentation in one go:

```bash
# 1. Build the tool
cd Packages
swift build

# 2. Download all Apple documentation (~15,000 pages, 2-4 hours)
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --max-depth 15 \
  --output-dir ~/.docsucker/docs

# 3. Download all Swift Evolution proposals (~400 proposals, 2-5 minutes)
.build/debug/docsucker crawl-evolution \
  --output-dir ~/.docsucker/swift-evolution

# 4. Download Apple sample code (first time - requires authentication)
.build/debug/docsucker download-samples \
  --authenticate \
  --output-dir ~/.docsucker/sample-code \
  --max-samples 100
```

**Total time:** ~2-4 hours
**Total disk space:** ~2-3 GB

### Selective Downloads

#### Option 1: Specific Framework Only

Download just the documentation for a specific framework:

```bash
# SwiftUI only (~500 pages, 5-10 minutes)
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500 \
  --output-dir ~/.docsucker/swiftui

# Foundation only (~1000 pages, 10-15 minutes)
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/foundation" \
  --max-pages 1000 \
  --output-dir ~/.docsucker/foundation

# Combine only (~200 pages, 5 minutes)
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/combine" \
  --max-pages 200 \
  --output-dir ~/.docsucker/combine
```

#### Option 2: Limited Sample Set

Download a small number of pages for testing:

```bash
# Just 10 pages for testing
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/swift" \
  --max-pages 10 \
  --output-dir ~/docsucker-test
```

### Authentication Flow for Sample Code Downloads

Sample code downloads require Apple Developer authentication. Here's how it works:

```
┌─────────────────────────────────────────────────────────────────┐
│                   Sample Code Download Flow                      │
└─────────────────────────────────────────────────────────────────┘

First Time Download (with --authenticate flag):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. User runs command:
   $ docsucker download-samples --authenticate --max-samples 10

2. Tool opens visible browser window
   ┌─────────────────────────────────────┐
   │  🌐 Apple Developer Sign In         │
   │                                     │
   │  Username: [____________]           │
   │  Password: [____________]           │
   │                                     │
   │  [Sign In]                          │
   └─────────────────────────────────────┘

3. User manually signs in with Apple ID
   • Enter Apple ID credentials
   • Complete 2FA if required
   • Accept terms if needed

4. Tool waits for user to press ENTER
   "Press ENTER after signing in..."

5. Tool extracts authentication cookies
   • Captures session cookies from WKWebView
   • Saves to: ~/.docsucker/sample-code/.auth-cookies.json

6. Tool proceeds with downloads
   • Uses authenticated session
   • Downloads sample code zip/tar files
   • Shows progress for each file

   ✅ Download completed!
      Total: 10 samples
      Downloaded: 10
      Skipped: 0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Subsequent Downloads (reuses saved cookies):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. User runs command (no --authenticate flag):
   $ docsucker download-samples --max-samples 100

2. Tool loads saved cookies
   📂 Reading: ~/.docsucker/sample-code/.auth-cookies.json

3. Tool creates authenticated WKWebView session
   • Restores all authentication cookies
   • Session is ready to download protected content

4. Tool downloads samples automatically
   • No user interaction required
   • Uses saved authentication
   • Downloads proceed normally

   ✅ Download completed!
      Total: 100 samples
      Downloaded: 95
      Skipped: 5 (already existed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cookie Management:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cookie file location:
  ~/.docsucker/sample-code/.auth-cookies.json

To sign in with different account:
  $ rm ~/.docsucker/sample-code/.auth-cookies.json
  $ docsucker download-samples --authenticate --max-samples 10

Cookie file contains:
  {
    "cookies": [
      {
        "name": "myacinfo",
        "value": "...",
        "domain": ".apple.com",
        "path": "/",
        "expiresDate": 1234567890.0
      },
      ...
    ]
  }

Security notes:
  • Cookies stored in plain JSON (local file only)
  • Contains session tokens - keep secure
  • Delete file to sign out
  • File permissions: 644 (user read/write only)
```

### Export to PDF

After downloading markdown documentation, you can export it to PDF:

```bash
# Export all markdown files to PDF
.build/debug/docsucker export-pdf \
  --input-dir ~/.docsucker/docs \
  --output-dir ~/.docsucker/pdfs

# Export with limit (first 100 files)
.build/debug/docsucker export-pdf \
  --input-dir ~/.docsucker/docs \
  --output-dir ~/.docsucker/pdfs \
  --max-files 100

# Force re-export (overwrite existing PDFs)
.build/debug/docsucker export-pdf \
  --input-dir ~/.docsucker/docs \
  --output-dir ~/.docsucker/pdfs \
  --force
```

**PDF Features:**
- Clean, readable layout with GitHub-style formatting
- Syntax highlighting for code blocks
- A4 page size (595x842 points)
- Preserves headers, links, lists, bold, italic
- ~1 second per file conversion time

### Incremental Updates

To update existing documentation without re-downloading everything:

```bash
# Update Apple docs (only downloads changed pages)
.build/debug/docsucker update \
  --output-dir ~/.docsucker/docs

# Or re-run crawl command (uses cached metadata)
.build/debug/docsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --output-dir ~/.docsucker/docs
```

The tool uses SHA-256 content hashing to detect changes and skip unchanged pages.

## Project Structure

```
Packages/
├── Sources/
│   ├── DocsuckerCLI/          # CLI executable for crawling
│   ├── DocsuckerMCP/          # MCP server executable
│   ├── DocsuckerCore/         # Crawler engine (WKWebView, HTML→Markdown)
│   ├── DocsuckerShared/       # Shared models & configuration
│   ├── DocsuckerMCPSupport/   # MCP resource provider
│   ├── MCPServer/             # Generic MCP server implementation
│   ├── MCPTransport/          # MCP transport layer (Stdio, HTTP/SSE ready)
│   └── MCPShared/             # MCP protocol types (JSON-RPC 2.0)
├── Tests/
│   ├── DocsuckerCoreTests/    # Unit & integration tests
│   ├── DocsuckerSharedTests/  # Configuration tests
│   └── MCP*Tests/             # MCP framework tests
├── DOCSUCKER_CLI_README.md    # CLI documentation
├── MCP_SERVER_README.md       # MCP server documentation
└── README.md                  # This file
```

## Features

### Docsucker CLI

- 🚀 **Fast WKWebView Crawling** - Native WebKit for accurate page rendering
- 📝 **HTML to Markdown** - Clean, readable documentation format with code syntax highlighting
- 🔍 **Smart Change Detection** - SHA-256 hashing to skip unchanged pages
- 📊 **Progress Tracking** - Real-time statistics and progress updates
- 🎯 **Framework Organization** - Automatic categorization by framework
- 🔄 **Incremental Updates** - Only re-download changed content
- 🐙 **Swift Evolution** - Download all accepted proposals from GitHub
- 📦 **Sample Code Downloads** - Download Apple sample code projects (zip/tar files)
- 📄 **PDF Export** - Convert markdown documentation to PDF format

### Docsucker MCP Server

- 🤖 **AI Agent Integration** - Works with Claude, Claude Code, and MCP-compatible agents
- 📚 **Dual Sources** - Serves both Apple docs and Swift Evolution proposals
- 🔍 **Resource Templates** - Easy URI-based access patterns
- 📡 **Stdio Transport** - Standard input/output for seamless integration
- ⚡ **Fast Local Access** - Instant document retrieval from cache

### MCP Framework (Generic & Reusable)

- 📋 **JSON-RPC 2.0** - Standard protocol implementation
- 🔌 **Multiple Transports** - Stdio implemented, HTTP/SSE ready
- 🎨 **Provider System** - Extensible resource/tool/prompt providers
- 🏗️ **Clean Architecture** - Modular design following ExtremePackaging principles
- ✅ **Swift 6 Concurrency** - Actors, Sendable, async/await throughout

## Documentation

### Detailed Guides

- **[CLI Usage Guide](./DOCSUCKER_CLI_README.md)** - Complete docsucker CLI documentation
  - Download all Apple documentation
  - Download Swift Evolution proposals
  - Incremental updates
  - Configuration management

- **[MCP Server Guide](./MCP_SERVER_README.md)** - MCP server setup and integration
  - Claude Desktop integration
  - Claude Code CLI integration
  - Resource URI patterns
  - Troubleshooting

### Quick Examples

#### Download Specific Framework

```bash
# Just SwiftUI docs
docsucker crawl \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500 \
  --output-dir ~/swiftui-docs
```

#### Serve to Claude

```bash
# Start MCP server
docsucker-mcp serve --docs-dir ~/swiftui-docs
```

Then ask Claude: *"Show me the documentation for SwiftUI's View protocol"*

## Architecture

### Layered Design

```
┌────────────────────────────────────────┐
│         Executable Layer               │
│  ┌─────────────┐    ┌────────────────┐ │
│  │DocsuckerCLI │    │ DocsuckerMCP   │ │
│  └──────┬──────┘    └────────┬───────┘ │
└─────────┼───────────────────┼──────────┘
          │                   │
┌─────────▼───────────────────▼─────────┐
│        Application Layer              │
│  ┌──────────────┐  ┌──────────────┐   │
│  │DocsuckerCore │  │ MCP Support  │   │
│  └──────┬───────┘  └──────┬───────┘   │
│  ┌──────▼────────────────┬▼───────┐   │
│  │  DocsuckerShared      │        │   │
│  └───────────────────────┘        │   │
└───────────────────────────────────┼───┘
                                    │
┌───────────────────────────────────▼──┐
│       Infrastructure Layer           │
│  ┌───────────┐  ┌──────────────┐     │
│  │MCPServer  │  │ MCPTransport │     │
│  └─────┬─────┘  └──────┬───────┘     │
│  ┌─────▼────────────────▼───────┐    │
│  │       MCPShared              │    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
```

### Key Components

**DocsuckerCore** - Crawler Engine
- WKWebView-based page loading
- HTML to Markdown conversion
- Change detection with SHA-256
- Framework detection and organization

**DocsuckerShared** - Configuration & Models
- Crawler configuration
- Change detection settings
- Crawl statistics and metadata
- Output format specifications

**DocsuckerMCPSupport** - MCP Integration
- Resource provider implementation
- URI parsing (apple-docs://, swift-evolution://)
- Document serving logic

**MCPServer** - Generic MCP Implementation
- JSON-RPC 2.0 message handling
- Provider registration system
- Capability negotiation
- Request/response routing

**MCPTransport** - Transport Layer
- Stdio transport (implemented)
- HTTP transport (ready for implementation)
- SSE transport (ready for implementation)

**MCPShared** - Protocol Types
- JSON-RPC message types
- Resource, Tool, Prompt types
- Content types (text, image, embedded resources)

## Requirements

- **macOS 15+** (uses WKWebView and FileManager.homeDirectoryForCurrentUser)
- **Swift 6.0+**
- **Xcode 16+** (for building)
- **Internet connection** (for downloading docs)
- **2-3 GB disk space** (for full Apple documentation)

## Installation

### Option 1: Use from Build Directory

```bash
cd Packages
swift build -c release

# Use executables directly
.build/release/docsucker --help
.build/release/docsucker-mcp --help
```

### Option 2: Install to /usr/local/bin

```bash
cd Packages
swift build -c release
cp .build/release/docsucker /usr/local/bin/
cp .build/release/docsucker-mcp /usr/local/bin/
```

### Option 3: Create Symbolic Links

```bash
cd Packages
swift build -c release
ln -s $(pwd)/.build/release/docsucker /usr/local/bin/docsucker
ln -s $(pwd)/.build/release/docsucker-mcp /usr/local/bin/docsucker-mcp
```

## Testing

### Run All Tests

```bash
swift test
```

### Run Integration Test (Downloads Real Docs)

```bash
swift test --filter testDownloadRealAppleDocPage
```

This test:
- Downloads https://developer.apple.com/documentation/swift
- Converts HTML to Markdown
- Verifies file structure and content
- Takes ~6 seconds to complete

### Run Unit Tests Only

```bash
swift test --filter "test" --skip "testDownloadRealAppleDocPage"
```

### Test Results

```
✅ 28/28 tests passed (0 failures)
- 21 SharedModels tests (IBAN validation)
- 7 MCP/Docsucker framework tests
  ✅ testConfiguration
  ✅ testHTMLToMarkdown
  ✅ testRequestIDCoding
  ✅ testServerInitialization
  ✅ testTransportProtocol
  ✅ testDocsuckerMCPSupport
  ✅ testDownloadRealAppleDocPage (integration test)
```

## Development

### Build for Development

```bash
swift build
```

### Build for Release

```bash
swift build -c release
```

### Run Tests

```bash
swift test
```

### Clean Build

```bash
swift package clean
```

## Use Cases

### 1. Offline Documentation Access

Download all Apple docs for offline reference:

```bash
docsucker crawl --max-pages 15000 --output-dir ~/offline-docs
```

### 2. AI-Powered Coding Assistant

Integrate with Claude for context-aware coding help:

```bash
docsucker-mcp serve --docs-dir ~/offline-docs
```

Ask Claude: *"How do I use SwiftUI's @State property wrapper?"*

### 3. Documentation Search & Analysis

Use grep/ripgrep for full-text search:

```bash
rg "async await" ~/.docsucker/docs
```

### 4. Custom Documentation Sites

Build your own documentation viewer:

```bash
docsucker crawl --output-dir ./docs
# Use docs/ to build static site
```

### 5. Version Tracking

Track documentation changes over time:

```bash
# Initial crawl
docsucker crawl --output-dir ~/docs-v1

# Later update
docsucker update --output-dir ~/docs-v1

# Compare changes
diff -r ~/docs-v1 ~/docs-v2
```

## Performance

### Crawling

- **Speed**: ~100-200 pages/minute (with 0.5s delay)
- **Full docs**: 2-4 hours for 15,000 pages
- **Framework**: 5-15 minutes for 500-1000 pages
- **Swift Evolution**: 2-5 minutes for ~400 proposals

### MCP Server

- **Startup**: < 1 second
- **Resource list**: Instant (metadata cached)
- **Document read**: < 100ms (from local disk)
- **Memory**: ~10-50 MB

### Storage

- **Apple docs**: ~2-3 GB (full documentation)
- **Swift Evolution**: ~10-20 MB (all proposals)
- **Metadata**: < 1 MB

## Troubleshooting

### Build Issues

**Error: 'homeDirectoryForCurrentUser' is unavailable in iOS**

Solution: Make sure you're building for macOS:
```bash
swift build --arch arm64-apple-macosx
```

**Error: Cannot find 'ArgumentParser' in scope**

Solution: Clean and rebuild:
```bash
swift package clean
swift build
```

### Runtime Issues

**Crawl shows 0 pages downloaded**

Solution: Check internet connection and URL:
```bash
curl -I https://developer.apple.com/documentation/
```

**MCP server won't start**

Solution: Verify documentation directories exist:
```bash
ls ~/.docsucker/docs
ls ~/.docsucker/swift-evolution
```

**Claude can't connect to server**

Solution: Check Claude config and binary path:
```bash
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json
which docsucker-mcp
```

## Contributing

This is a personal project, but suggestions and improvements are welcome!

### Potential Enhancements

- [ ] HTTP/SSE transport for MCP server
- [ ] Tool support in MCP (search, summarize, etc.)
- [ ] Prompt support in MCP (templates for common queries)
- [ ] PDF export option
- [ ] Web UI for browsing documentation
- [ ] Docker container for MCP server
- [ ] Linux support (requires WebKit alternative)
- [ ] Incremental crawl scheduling (cron job)

## License

See LICENSE file for details.

## Credits

Built with:
- [Swift](https://swift.org) - Programming language
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) - CLI framework
- [WebKit](https://webkit.org) - Web rendering engine
- [Model Context Protocol](https://modelcontextprotocol.io) - AI agent protocol

Inspired by the need for offline Apple documentation and better AI integration.

## See Also

- **[CLI Documentation](./DOCSUCKER_CLI_README.md)** - Detailed CLI usage guide
- **[MCP Server Documentation](./MCP_SERVER_README.md)** - MCP server setup and integration
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [Swift Evolution](https://github.com/swiftlang/swift-evolution)
- [MCP Specification](https://spec.modelcontextprotocol.io/)

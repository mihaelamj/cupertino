# Cupertino Architecture

**Version:** v0.2.0
**Last Updated:** 2025-11-22
**Swift Version:** 6.2
**Language Mode:** Swift 6 with Strict Concurrency Checking

---

## Table of Contents

1. [Overview & Package Structure](#overview--package-structure)
2. [Error Handling Patterns](#error-handling-patterns)
3. [JSON Coding Standards](#json-coding-standards)
4. [MCP Server Implementation](#mcp-server-implementation)
5. [CLI Architecture](#cli-architecture)
6. [WKWebView Testing](#wkwebview-testing)
7. [MCP Testing Guide](#mcp-testing-guide)

---

## Overview & Package Structure

Cupertino is a Swift-based Apple documentation crawler and MCP (Model Context Protocol) server. The project uses **ExtremePackaging** architecture to organize code into focused, reusable modules.

### Package Structure (v0.2.0)

Cupertino uses **ExtremePackaging** architecture with 10 consolidated packages:

```
Foundation Layer:
  ├─ MCP                    # Consolidated MCP framework (Protocol + Transport + Server)
  ├─ Logging                # os.log infrastructure
  └─ Shared                 # Configuration & models

Infrastructure Layer:
  ├─ Core                   # Crawler & downloaders
  ├─ Search                 # SQLite FTS5 search for documentation
  └─ SampleIndex            # SQLite FTS5 search for sample code

Application Layer:
  ├─ MCPSupport             # Resource providers
  ├─ SearchToolProvider     # Search tool implementations
  └─ Resources              # Embedded resources

Executables:
  ├─ CLI                    # Unified cupertino binary
  ├─ TUI                    # Terminal UI (cupertino-tui)
  └─ MockAIAgent            # Testing tool (mock-ai-agent)
```

**v0.2 Package Changes:**
- **Consolidated MCP:** MCPShared + MCPTransport + MCPServer → MCP
- **Namespaced Types:** CupertinoLogging → Logging, CupertinoShared → Shared, etc.
- **Unified Binary:** Single `cupertino` binary (no separate `cupertino-mcp`)

### Key Features

- **WKWebView-based crawling** - Uses native WebKit for accurate JavaScript rendering
- **HTML to Markdown conversion** - Clean, readable documentation with code syntax highlighting
- **Smart change detection** - SHA-256 content hashing to skip unchanged pages
- **Full-text search** - SQLite FTS5 search index for instant documentation lookup
- **MCP server** - Serves documentation to AI agents like Claude
- **Swift Evolution proposals** - Downloads all accepted Swift Evolution proposals
- **Sample code downloads** - Downloads Apple sample code projects

### Technology Stack

- **Swift 6.2** with strict concurrency checking
- **WKWebView** for web page rendering
- **SQLite FTS5** for full-text search
- **ArgumentParser** for CLI interface
- **MCP Protocol** for AI agent integration
- **JSON-RPC 2.0** for MCP communication

---

## Error Handling Patterns

**Based on:** [ERROR_HANDLING.md](documents/ERROR_HANDLING.md)

This section defines the error handling and functional programming patterns used in Cupertino. The goal is to maintain clean, idiomatic Swift 6 code while incorporating practical functional programming concepts where they provide clear value.

### Philosophy

- **Pragmatic over theoretical** - Use patterns that solve real problems
- **Swift-first** - Prefer Swift stdlib and language features over custom abstractions
- **Modern async/await** - Leverage Swift 6 concurrency for error handling
- **Minimal abstractions** - Only introduce patterns that reduce boilerplate or improve safety

### Modern Swift Error Handling

#### 1. Use `async throws` for Most Code (Priority: HIGH)

**Purpose**: Clean, idiomatic error handling for async/await

**Use cases**: 95% of our code
- Sequential operations
- Single async calls
- Normal error flows
- Any code that can propagate errors synchronously

**Why**: Apple's recommended pattern for Swift 6 concurrency

#### 2. Built-in Result Type - ONLY for Specific Cases (Priority: LOW)

**IMPORTANT**: Use Swift stdlib `Result<Success, Failure>` - don't create custom implementation

**Apple's guidance**: "Use when you can't return errors synchronously"

**When to use**:
- Collecting errors from parallel operations with `TaskGroup`
- Serialization/memoization of throwing operations
- Converting between throwing and non-throwing APIs

**When NOT to use**:
- Sequential operations → use `async throws`
- Normal async/await code → use `async throws`
- Callback-based APIs → use async/await instead

### Functional Programming Patterns

#### Sum Types - Enums with Associated Values

**Purpose**: Model mutually exclusive states and detailed error cases

**Current usage**: 13 error enums in codebase
- `SearchError`
- `PackageFetchError`
- `CrawlerError`
- `SampleCodeError`
- And 9 more...

This approach provides type-safe error handling with associated context for each error case.

#### Product Types - Immutable Structs

**Purpose**: Model data with multiple fields

**Current usage**: All models use immutable `struct` with `let`, `Sendable`, `Codable`

This ensures thread-safe data sharing across concurrency boundaries and prevents unintended mutations.

#### Functors & Monads - map/flatMap

**Purpose**: Transform and chain operations on wrapped values

**Current usage**: Swift stdlib implementations
- `Array.map`, `Array.flatMap`
- `Optional.map`, `Optional.flatMap`
- `Result.map`, `Result.flatMap`
- `AsyncSequence.map`, `AsyncSequence.flatMap`

These standard library functions enable functional composition patterns for transforming and chaining operations.

### Summary

#### Primary Approach
**Use `async throws` for 95% of code** - This is Apple's modern Swift 6 pattern for error handling.

#### Result Type
**Only use Swift stdlib `Result` for `TaskGroup.nextResult()`** - For parallel error collection, not sequential code.

#### FP Patterns
**Focus on practical patterns we're already using**:
- Sum types (enums with associated values)
- Product types (immutable structs)
- map/flatMap from Swift stdlib

#### Avoid
- Heavy category theory abstractions
- Custom Result implementations
- Haskell-style naming
- IO monads (use actors + async/await)

---

## JSON Coding Standards

**Based on:** [UNIFIED_JSON_CODING.md](documents/UNIFIED_JSON_CODING.md)

A unified `JSONCoding` utility ensures consistent JSON encoding/decoding across the entire codebase, especially for date handling.

### Problem Solved

**Before:** Date encoding/decoding strategies were scattered and inconsistent:
- Some places used ISO8601
- Some places used default (Double timestamps)
- Some places forgot to set any strategy
- Led to "Expected Double but found String" errors

**After:** All code that handles dates uses the unified `JSONCoding` utility:
- Consistent ISO8601 date format everywhere
- Single source of truth for encoding/decoding configuration
- Easy to update date strategy project-wide if needed

### API

The `JSONCoding` utility provides:

#### Encoders
- Standard encoder with ISO8601 dates
- Pretty-printed encoder with ISO8601 dates

#### Decoders
- Standard decoder with ISO8601 dates

#### Convenience Methods
- Encode to Data
- Encode pretty-printed to Data
- Decode from Data
- Decode from file
- Encode to file (auto-creates directory, pretty-printed)

### Benefits

#### 1. Consistency
All date-related JSON operations use ISO8601 format

#### 2. Maintainability
Single place to change date strategy if needed in future

#### 3. Less Code
Convenience methods reduce boilerplate significantly

#### 4. Error Prevention
Impossible to forget date strategy when using `JSONCoding`

---

## MCP Server Implementation

**Based on:** [MCP_SERVER_README.md](documents/MCP_SERVER_README.md) and [MCP_SERVER_USAGE.md](documents/MCP_SERVER_USAGE.md)

An MCP (Model Context Protocol) server that provides Apple documentation and Swift Evolution proposals to AI agents like Claude.

### What is MCP?

MCP (Model Context Protocol) is a standardized protocol for providing context to AI models. It allows AI agents to:
- Browse available documentation resources
- Read specific documentation pages
- Search through documentation collections
- Access up-to-date information from your local documentation cache

### v0.2 Architecture

In v0.2, the MCP server is integrated into the main `cupertino` binary. The binary defaults to starting the MCP server when run without arguments, making configuration simpler.

### Features

- **AI Agent Integration** - Works with Claude, Claude Code, and other MCP-compatible agents
- **Dual Documentation Sources** - Serves both Apple docs and Swift Evolution proposals
- **Resource Templates** - Easy URI-based access patterns
- **Stdio Transport** - Standard input/output for seamless integration
- **Fast Access** - Instant document retrieval from local cache

### Prerequisites

Before starting the MCP server, you need to download documentation using the fetch commands for Apple documentation and Swift Evolution proposals.

### Integration with Claude Desktop

Configure Claude Desktop by editing the configuration file at the appropriate location for your platform:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

**Linux**: `~/.config/Claude/claude_desktop_config.json`

**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

Add the Cupertino MCP server configuration with the path to your binary. The `cupertino` binary defaults to serving the MCP protocol, so no additional arguments are needed.

After editing the config, restart Claude Desktop for changes to take effect.

### Resource URI Patterns

#### Apple Documentation

Pattern: `apple-docs://{framework}/{page}`

Examples include swift/array, swiftui/view, foundation/url

#### Swift Evolution Proposals

Pattern: `swift-evolution://{proposalID}`

Examples include SE-0001, SE-0255, SE-0400

### Available MCP Operations

#### 1. List Resources

The server provides a list of all available documentation resources with their URIs.

#### 2. Read Resource

Fetch specific documentation content by URI, returning the full markdown content of the documentation page.

#### 3. List Resource Templates

Get available URI patterns with descriptions for accessing documentation.

### Architecture

The architecture follows a layered approach:
- AI agents connect to the cupertino MCP server via JSON-RPC 2.0
- The server reads from local documentation directories
- Apple docs are organized by framework
- Swift Evolution proposals are stored as individual markdown files

### Performance

- **Startup time**: < 1 second
- **Resource list**: Instant (metadata cached)
- **Document read**: < 100ms (from local disk)
- **Memory usage**: ~10-50 MB

### Security Notes

- Server only reads local files (no network access)
- Only serves files from specified directories
- No write operations performed
- Uses stdio (no network ports exposed)

---

## CLI Architecture

**Based on:** [CUPERTINO_CLI_README.md](documents/CUPERTINO_CLI_README.md)

A Swift command-line tool for downloading and converting Apple documentation to Markdown format.

### Features

- **Fast WKWebView-based crawling** - Uses native WebKit for accurate rendering
- **HTML to Markdown conversion** - Clean, readable documentation in Markdown format with code syntax highlighting
- **Smart change detection** - SHA-256 content hashing to skip unchanged pages
- **Progress tracking** - Real-time statistics and progress updates
- **Framework organization** - Automatically organizes docs by framework
- **Incremental updates** - Only re-downloads changed content
- **Swift Evolution proposals** - Download all accepted Swift Evolution proposals from GitHub
- **Sample code downloads** - Download Apple sample code projects as zip/tar files
- **PDF export** - Convert markdown documentation to beautifully formatted PDF files

### Commands

#### 1. Download All Apple Documentation

Downloads the complete Apple documentation library with configurable parameters for:
- Starting URL to crawl from
- Maximum number of pages to download (default: 15000)
- Maximum link depth to follow (default: 15)
- Output directory location (default: `~/.cupertino/docs`)
- Force recrawl option to ignore cache

Estimated time: 2-4 hours for full documentation
Estimated size: ~2-3 GB

#### 2. Download Specific Framework Documentation

Download documentation for specific frameworks like SwiftUI by targeting the framework's documentation URL.

#### 3. Download All Swift Evolution Proposals

Downloads all accepted Swift Evolution proposals from GitHub, including:
- Fetching the list of all proposals from swift-evolution GitHub repo
- Downloading each markdown file from the proposals directory
- Saving them with original filenames
- Tracking which proposals are new/updated

Estimated time: 2-5 minutes
Estimated size: ~10-20 MB

#### 4. Download Apple Sample Code Projects

Downloads Apple sample code projects as zip/tar files. First-time use requires authentication with Apple ID, after which authentication cookies are saved for subsequent downloads.

#### 5. Clean Up Sample Code Archives

Cleans up downloaded sample code ZIP archives by removing unnecessary files like .git folders, xcuserdata, and build artifacts. This significantly reduces storage (from ~26GB to ~2-3GB) and improves indexing quality.

#### 6. Index Sample Code for Search

Indexes sample code projects for full-text search using a separate SQLite FTS5 database (`~/.cupertino/samples.db`). The index includes:
- Project metadata (title, description, frameworks)
- README content
- Source files (Swift, Objective-C, Metal, etc.)

**Important:** Run cleanup before indexing to remove unnecessary files.

#### 7. Build Search Index

Builds a full-text search index from downloaded documentation with parameters for:
- Directory containing Apple documentation
- Directory containing Swift Evolution proposals
- Output database path
- Option to clear existing index

Creates a SQLite FTS5 search index enabling fast full-text search across all documentation.

Estimated time: ~2-5 minutes
Estimated size: ~50MB

### Output Format

#### Directory Structure

Documentation is organized hierarchically:
- Top level organized by framework (swift, swiftui, foundation, etc.)
- Each framework contains markdown files for individual documentation pages
- Metadata stored in hidden .cupertino directory
- File naming follows consistent pattern based on URL structure

#### Markdown Format

Each page includes YAML front matter with source URL and crawl timestamp, followed by the markdown-converted documentation content with proper heading hierarchy and code formatting.

### Statistics & Progress

During crawling, real-time progress is displayed showing:
- Current page being processed with depth and framework
- Save status (new, updated, or skipped)
- Progress percentage and page title
- Final statistics including total pages, new/updated/skipped counts, errors, and duration

---

## WKWebView Testing

**Based on:** [WKWEBVIEW_HEADLESS_TESTING.md](documents/WKWEBVIEW_HEADLESS_TESTING.md)

This section explains how to test WKWebView-based code in headless Swift tests without a GUI.

### The Problem: WKWebView Tests Crash in `swift test`

When running tests that use WKWebView through `swift test`, the test runner exits with signal 11 (segmentation fault).

This is confusing because:
1. Production code works perfectly when run as a CLI executable
2. No GUI is displayed - the app runs headless in terminal
3. Tests crash even though they do the exact same thing

### Understanding the Root Cause

#### WKWebView's Hidden Requirements

WKWebView is part of WebKit, a complex framework that requires:

1. **NSApplication singleton** - The application object
2. **Main run loop** - For processing events and async operations
3. **App bundle context** - Metadata about the running application
4. **Proper thread isolation** - Must run on main thread (@MainActor)

Even though WKWebView runs "headless" (no visible window), it still needs the application infrastructure.

#### Why CLI Executables Work

When you run a Swift executable from the terminal, Swift's runtime automatically initializes:
- NSApplication.shared
- Main run loop
- Event handling system
- App bundle context

#### Why `swift test` Crashes

The test runner is optimized for speed and isolation. The test framework provides:
- Basic process execution
- Test discovery and running
- Assertion checking
- But NO macOS application infrastructure

When WKWebView tries to initialize without these prerequisites, it crashes.

### The Solution: Bootstrap NSApplication

#### The Fix

The solution is to initialize NSApplication before using WKWebView in tests. Accessing `NSApplication.shared` for the first time triggers initialization:

1. Creates the singleton NSApplication instance
2. Sets up the main run loop (CFRunLoop)
3. Initializes event handling infrastructure
4. Creates app bundle context
5. Registers event handlers

After this initialization, WKWebView can initialize successfully.

### Important Considerations

#### 1. Thread Safety: Always Use @MainActor

WKWebView operations must run on the main thread. The `@MainActor` annotation ensures this requirement is met.

#### 2. Test Tags for Separation

Using test tags allows separating WKWebView integration tests from fast unit tests. This enables running unit tests quickly while keeping slower integration tests separate.

### Best Practices

Complete integration tests should:
- Import AppKit for NSApplication access
- Use the integration test tag
- Apply @MainActor annotation
- Initialize NSApplication before WKWebView usage

Tests missing critical components will crash:
- Missing @MainActor annotation
- Missing async throws
- Missing NSApplication initialization

### Key Takeaways

1. **WKWebView requires application infrastructure** even when running headless
2. **CLI executables get NSApplication automatically**, tests don't
3. **NSApplication must be initialized** before WKWebView usage in tests
4. **Thread safety matters**: Always use `@MainActor`
5. **Tagging helps**: Separate integration tests from unit tests

---

## MCP Testing Guide

**Based on:** [MCP_TEST_SERVERS.md](documents/MCP_TEST_SERVERS.md) and [TESTING_MCP_SERVERS.md](documents/TESTING_MCP_SERVERS.md)

This section explains how to test MCP servers from the command line using the `mock-ai-agent` tool.

### Quick Start

The mock AI agent is a Swift-based MCP client that demonstrates the complete request/response cycle with detailed JSON logging. It helps you verify that your MCP server implements the stdio transport correctly.

### What the Mock Agent Does

The mock agent executes a complete MCP interaction flow:

1. **Initialize** - Establishes connection and exchanges capabilities
2. **List Tools** - Retrieves available tools from the server
3. **Call Tool** - Executes a tool (search_nodes for memory server, search for cupertino)
4. **List Resources** - Gets available resources (skipped for servers without resources)
5. **Read Resource** - Reads a specific resource (skipped for servers without resources)
6. **Shutdown** - Sends cleanup notification

### Available Test Servers

#### 1. MCP Memory Server (TypeScript)

**Description**: Knowledge graph-based persistent memory system that demonstrates basic MCP capabilities including tools and resources.

**Features**:
- Tools for storing and retrieving information
- Knowledge graph relationships
- Persistent memory across sessions

#### 2. MCP Filesystem Server (TypeScript)

**Description**: Secure file operations with configurable access controls. Demonstrates resource-based MCP interactions.

**Features**:
- Secure file reading/writing
- Directory listing
- Configurable access boundaries
- File search capabilities

#### 3. GitHub MCP Server (Go)

**Description**: GitHub's official MCP server providing repository management, issue tracking, and code operations.

**Prerequisites**:
- Docker installed and running
- GitHub Personal Access Token with required scopes: `repo`, `read:packages`, `read:org`

**Features**:
- Repository operations (read files, search code)
- Issue management (list, create, update)
- Pull request operations
- GitHub Actions integration
- User and organization queries

### Quick Comparison

| Server | Language | Complexity | Auth Required | Best For |
|--------|----------|------------|---------------|----------|
| Memory | TypeScript | Simple | No | Basic tool/resource testing |
| Filesystem | TypeScript | Simple | No | File operations, resources |
| GitHub | Go | Medium | Yes (PAT) | Real-world API integration |

### Verifying MCP Stdio Compliance

The mock agent helps verify your MCP server follows the stdio transport specification:

#### What to Look For

1. **Server starts successfully** with process ID and startup messages
2. **Initialize response received** with protocol version and server information
3. **Tools are listed** with names and descriptions
4. **Tool execution succeeds** with expected content

### MCP Stdio Transport Specification

#### Message Framing Rules

Per the MCP specification, messages are delimited by newlines and must not contain embedded newlines.

Correct format: Complete JSON-RPC 2.0 message on a single line followed by newline delimiter.

Incorrect format: Pretty-printed JSON with embedded newlines.

#### Wire Protocol

Communication flows in both directions using compact JSON messages, where each line contains:
1. A complete JSON-RPC 2.0 message
2. Single-line format (no embedded newlines)
3. Exactly one newline delimiter at the end

### Common Server Implementation Patterns

MCP servers across different languages follow similar patterns:

**Node.js**: Use readline interface to process line-by-line input, parse JSON, handle requests, and output compact JSON responses.

**Python**: Iterate over stdin lines, parse JSON, handle requests, and print compact JSON with flush.

**Swift**: Read lines in a loop, decode JSON-RPC messages, handle requests, encode responses, and print compact JSON.

### Troubleshooting Checklist

- Server starts without errors
- Server logs appear correctly
- Initialize response received within timeout
- Response is valid JSON-RPC 2.0 format
- Response contains required fields (result or error)
- Tools are listed correctly
- Tool execution returns expected content
- No timeout or hanging
- Clean shutdown without errors

---

## Further Reading

### Swift Concurrency
- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Swift Evolution SE-0296: Async/await](https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md)
- [Swift Evolution SE-0306: Actors](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- [Swift Evolution SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-sendable-and-sendable-closures.md)

### MCP Protocol
- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [MCP Stdio Transport](https://spec.modelcontextprotocol.io/specification/basic/transports/#stdio)
- [Official MCP Servers](https://github.com/modelcontextprotocol/servers)

### WKWebView
- [WKWebView Documentation](https://developer.apple.com/documentation/webkit/wkwebview)
- [NSApplication Documentation](https://developer.apple.com/documentation/appkit/nsapplication)
- [Swift Testing Framework](https://developer.apple.com/documentation/testing)

---

**Document Version:** 1.0
**Created:** 2025-11-22
**Author:** Claude (Anthropic)
**Project:** Cupertino - Apple Documentation CLI & MCP Server


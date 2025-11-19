# Cupertino CLI Command Analysis & Refactoring Recommendations

> **⚠️ NOTICE: This document is now outdated.**
> This analysis was written for v0.1.5. The v0.2 refactoring has been **completed**.
> For current command structure, see:
> - [README.md](../README.md) - Current command reference
> - [REFACTORING_v0.2_PLAN.md](REFACTORING_v0.2_PLAN.md) - Implementation details
> - [MCP_SERVER_README.md](MCP_SERVER_README.md) - MCP server usage
> - [CUPERTINO_CLI_README.md](CUPERTINO_CLI_README.md) - CLI command usage

**Version:** 1.0 (Historical)
**Last Updated:** 2025-11-18
**Analyzed CLI Version:** 0.1.5 (Pre-refactoring)
**Current CLI Version:** 0.2.0

---

## Table of Contents

1. [Current State](#current-state)
2. [Command Inventory](#command-inventory)
3. [Problem Analysis](#problem-analysis)
4. [Refactoring Recommendations](#refactoring-recommendations)
5. [Proposed Command Structure](#proposed-command-structure)

---

## Current State

### Overview

Cupertino currently has **2 separate CLI binaries**:

1. **`cupertino`** - Main CLI (crawl, fetch, index)
2. **`cupertino-mcp`** - MCP server CLI (serve)

Total: **4 primary commands** with **27 options/flags**

### Command Inventory

| Binary | Command | Purpose | Default |
|--------|---------|---------|---------|
| `cupertino` | `crawl` | Crawl documentation | ✅ Yes |
| `cupertino` | `fetch` | Fetch resources | No |
| `cupertino` | `index` | Build search index | No |
| `cupertino-mcp` | `serve` | Start MCP server | ✅ Yes |

---

## Command Inventory

### 1. CRAWL Command

**Purpose:** Crawl documentation from web sources

**Location:** `Sources/CupertinoCLI/Commands.swift:10-296`

#### All Options (9 total)

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--type` | Enum | `docs` | No | Source: `docs`, `swift`, `evolution`, `packages`, `all` |
| `--start-url` | String | nil | No | Override starting URL |
| `--max-pages` | Int | 15000 | No | Maximum pages to crawl |
| `--max-depth` | Int | 15 | No | Maximum depth from start URL |
| `--output-dir` | String | nil | No | Output directory (auto-determined by type) |
| `--allowed-prefixes` | String | nil | No | Comma-separated URL prefixes |
| `--force` | Flag | false | No | Force recrawl, ignore cache |
| `--resume` | Flag | false | No | Resume from saved session |
| `--only-accepted` | Flag | false | No | Evolution only: accepted proposals |

#### Type Variations (5 total)

```swift
enum CrawlType {
    case docs        // Apple Developer Documentation
    case swift       // Swift.org Documentation
    case evolution   // Swift Evolution Proposals
    case packages    // Swift Package Documentation (not implemented)
    case all         // Runs docs + swift + evolution in parallel
}
```

**Default URLs:**
- `docs` → `https://developer.apple.com/documentation/`
- `swift` → `https://docs.swift.org/swift-book/...`
- `evolution` → (uses different crawler)
- `packages` → Not implemented
- `all` → N/A

**Default Output Dirs:**
- `docs` → `~/.cupertino/docs`
- `swift` → `~/.cupertino/swift-org`
- `evolution` → `~/.cupertino/swift-evolution`
- `packages` → `~/.cupertino/packages`

#### Special Behaviors

**`--type all`:**
- Runs 3 crawls in parallel: docs, swift, evolution
- Does NOT include packages (not implemented)
- Uses `TaskGroup` for concurrency

**`--type evolution`:**
- Uses `SwiftEvolutionCrawler` (different implementation)
- `--only-accepted` flag only works with this type
- Fetches proposals from GitHub

#### Examples

```bash
# Default crawl (Apple docs)
cupertino fetch

# Crawl everything
cupertino fetch --type all

# Evolution proposals (accepted only)
cupertino fetch --type evolution --only-accepted

# Resume interrupted crawl
cupertino fetch --resume

# Force full recrawl with custom limit
cupertino fetch --force --max-pages 5000
```

---

### 2. FETCH Command

**Purpose:** Fetch resources without web crawling (API-based)

**Location:** `Sources/CupertinoCLI/Commands.swift:301-400`

#### All Options (6 total)

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--type` | Enum | — | **YES** | Resource: `packages`, `code` |
| `--output-dir` | String | nil | No | Output directory |
| `--limit` | Int | nil | No | Maximum items to fetch |
| `--force` | Flag | false | No | Force re-download |
| `--resume` | Flag | false | No | Resume from checkpoint |
| `--authenticate` | Flag | false | No | Launch browser for auth (code only) |

#### Type Variations (2 total)

```swift
enum FetchType {
    case packages    // Swift package metadata (API-based)
    case code        // Apple sample code (web-based)
}
```

**Default Output Dirs:**
- `packages` → `~/.cupertino/packages`
- `code` → `~/.cupertino/sample-code`

#### Special Behaviors

**`--type packages`:**
- Requires `GITHUB_TOKEN` env var for higher rate limits
- Creates `swift-packages-with-stars.json`
- Supports checkpointing with `checkpoint.json`

**`--type code`:**
- Downloads Apple sample code
- `--authenticate` launches visible browser
- Uses embedded `sample-code-catalog.json` as source

#### Examples

```bash
# Fetch Swift packages
cupertino fetch --type packages

# Fetch sample code with authentication
cupertino fetch --type code --authenticate

# Fetch with limit and resume
cupertino fetch --type packages --limit 1000 --resume

# With GitHub token (higher rate limit)
export GITHUB_TOKEN=your_token
cupertino fetch --type packages
```

---

### 3. INDEX Command

**Purpose:** Build FTS5 search index from crawled documentation

**Location:** `Sources/CupertinoCLI/Commands.swift:405-503`

#### All Options (5 total)

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--docs-dir` | String | `~/.cupertino/docs` | No | Apple documentation directory |
| `--evolution-dir` | String | `~/.cupertino/swift-evolution` | No | Evolution proposals directory |
| `--metadata-file` | String | `~/.cupertino/metadata.json` | No | Metadata file path |
| `--search-db` | String | `~/.cupertino/search.db` | No | Output database path |
| `--clear` | Flag | false | No | Clear existing index first |

#### Dependencies

**Hard Requirement:**
- `metadata.json` must exist (from `crawl` command)
- Fails with error if missing

**Soft Requirement:**
- Evolution directory (optional, skips if missing)

#### Output

Creates: `search.db` (SQLite with FTS5 extension)

**Tables:**
- `docs_fts` - Full text search
- `docs_metadata` - Document metadata
- `packages` - Package information
- `package_dependencies` - Package dependencies

#### Examples

```bash
# Build index with defaults
cupertino save

# Clear and rebuild
cupertino save --clear

# Custom paths
cupertino save --docs-dir ~/my-docs --search-db ~/my-search.db

# Skip evolution proposals
cupertino save --evolution-dir /nonexistent
```

---

### 4. SERVE Command (MCP Server)

**Purpose:** Start Model Context Protocol server for Claude integration

**Location:** `Sources/CupertinoMCP/ServeCommand.swift:14-119`

#### All Options (3 total)

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--docs-dir` | String | `~/.cupertino/docs` | No | Apple documentation directory |
| `--evolution-dir` | String | `~/.cupertino/swift-evolution` | No | Evolution proposals directory |
| `--search-db` | String | `~/.cupertino/search.db` | No | Search database path |

#### Dependencies

**Soft Requirements:**
- `docs-dir` or `evolution-dir` (at least one recommended)
- `search.db` (optional, warns if missing)

**Graceful Degradation:**
- Starts without search database (search tools unavailable)
- Continues with only resource provider

#### Provides

**Resource Provider:**
- URI: `apple-docs://{framework}/{page}`
- URI: `swift-evolution://{proposalID}`

**Tool Provider (if search.db exists):**
- `search_docs` - Search documentation
- `list_frameworks` - List available frameworks

#### Examples

```bash
# Start MCP server
cupertino-mcp serve

# Or just:
cupertino-mcp

# Custom paths
cupertino-mcp serve --docs-dir ~/my-docs --search-db ~/my-search.db
```

---

## Problem Analysis

### 1. Redundancy Issues

#### ❌ Duplicate Directory Options

**Problem:** Same directories specified in multiple commands

```bash
# Index command
cupertino save --docs-dir ~/.cupertino/docs --evolution-dir ~/.cupertino/swift-evolution

# Serve command (must repeat same paths!)
cupertino-mcp serve --docs-dir ~/.cupertino/docs --evolution-dir ~/.cupertino/swift-evolution
```

**Impact:**
- User must remember same paths for both commands
- No single source of truth for configuration
- Prone to inconsistency

**Better approach:**
- Global config file or environment variables
- Or: Serve command inherits from Index command output

---

#### ❌ Overlapping Functionality

**Problem:** `crawl --type packages` vs `fetch --type packages`

```swift
// In CrawlType enum
case packages    // "Swift Package Documentation" - NOT IMPLEMENTED

// In FetchType enum
case packages    // "Swift package metadata" - IMPLEMENTED
```

**Current state:**
- `crawl --type packages` exists in enum but does nothing
- `fetch --type packages` is the working implementation
- Confusing: Which one should users use?

**Impact:**
- Users try `crawl --type packages` and it fails silently
- Documentation mentions packages in both places

---

#### ❌ Two CLIs for Related Functionality

**Problem:** `cupertino` vs `cupertino-mcp` split

```bash
# Setup workflow requires switching binaries
cupertino fetch --type all
cupertino save
cupertino-mcp serve    # ← Different binary!
```

**Impact:**
- Cognitive overhead (two commands to remember)
- Installation complexity (two binaries)
- Could be subcommands of one CLI

---

### 2. Verbosity Issues

#### ❌ Too Many Type Variations

**`crawl` command has 5 types:**
- `docs`, `swift`, `evolution`, `packages`, `all`

**Issues:**
- `packages` type doesn't work (not implemented)
- `all` doesn't include packages (inconsistent naming)
- User confusion: "Does `all` really mean all?"

---

#### ❌ Excessive Options for Simple Tasks

**Index command has 5 options just for paths:**

```bash
cupertino save \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir ~/.cupertino/swift-evolution \
  --metadata-file ~/.cupertino/metadata.json \
  --search-db ~/.cupertino/search.db
```

**Impact:**
- Default use case requires zero flags, but advanced use is verbose
- Could use config file or conventions to reduce flags

---

#### ❌ Inconsistent Option Naming

**Directory options use 3 different patterns:**

```bash
# Crawl command
--output-dir          # Generic name

# Index command
--docs-dir            # Specific purpose name
--evolution-dir

# Serve command
--docs-dir            # Same as Index
--evolution-dir
```

**Impact:**
- Harder to remember which command uses which naming
- `--output-dir` vs `--docs-dir` for same concept

---

### 3. Missing Commands

#### ❌ No `fetch --type all`

**Problem:** Must run fetch twice for complete setup

```bash
# Current workflow
cupertino fetch --type packages
cupertino fetch --type code

# Wanted workflow
cupertino fetch --type all
```

**Impact:**
- Tedious for users wanting everything
- Inconsistent with `crawl --type all`

---

#### ❌ No "Do Everything" Command

**Problem:** Multi-step workflow for initial setup

```bash
# Current: 3-4 separate commands
cupertino fetch --type all
cupertino fetch --type packages
cupertino fetch --type code
cupertino save
cupertino-mcp serve
```

**Wanted:**

```bash
# One command to rule them all
cupertino setup --all

# Or even simpler
cupertino init
```

**Impact:**
- Poor first-time user experience
- Documentation needs to explain multi-step process

---

#### ❌ No Update/Refresh Command

**Problem:** No way to update just catalogs without full crawl

**Current workaround:**
- Delete directories and re-crawl
- Or manually update embedded resources

**Wanted:**

```bash
# Update embedded catalogs
cupertino update-catalogs

# Or: Incremental update
cupertino refresh --type docs
```

**Impact:**
- Users can't easily keep data fresh
- Related to TODO #7

---

#### ❌ No Validation Command

**Problem:** No way to check if setup is complete

**Wanted:**

```bash
# Check installation
cupertino doctor

# Output:
✅ cupertino binary found
✅ Crawled documentation exists (5000 pages)
✅ Search index exists (search.db)
❌ Sample code missing - run: cupertino fetch --type code
```

**Impact:**
- Users don't know if they have complete setup
- Hard to diagnose missing components

---

#### ❌ No Cleanup Command

**Problem:** No way to selectively clean data

**Wanted:**

```bash
# Clean specific data
cupertino clean --type docs

# Clean everything
cupertino clean --all

# Show what would be deleted
cupertino clean --dry-run
```

**Impact:**
- Must manually delete `~/.cupertino/*` directories
- Risk of deleting wrong files

---

### 4. Missing Convenience Features

#### ❌ No Shorthand Flags

**Problem:** All options use long form only

```bash
# Current: verbose
cupertino fetch --type docs --max-pages 1000 --output-dir ~/docs

# Wanted: concise
cupertino fetch -t docs -m 1000 -o ~/docs
```

---

#### ❌ No Progress Reporting Levels

**Problem:** Can't control output verbosity

**Wanted:**

```bash
# Quiet mode
cupertino fetch --quiet

# Verbose mode
cupertino fetch --verbose

# JSON output for scripting
cupertino fetch --json
```

---

#### ❌ No Config File Support

**Problem:** Must specify same options repeatedly

**Wanted:**

```toml
# ~/.cupertino/config.toml
[directories]
docs = "~/my-docs"
evolution = "~/my-evolution"
search_db = "~/my-search.db"

[limits]
max_pages = 5000
max_depth = 10
```

```bash
# Uses config automatically
cupertino fetch
```

---

## Refactoring Recommendations

### Priority 1: Critical Fixes

#### 1. Merge CLIs into Single Binary

**Current:**
```bash
cupertino fetch
cupertino-mcp serve
```

**Proposed:**
```bash
cupertino fetch
cupertino serve    # Or: cupertino serve
```

**Benefits:**
- Single installation
- Consistent user experience
- Easier documentation

**Implementation:**
```swift
// In Cupertino.swift
subcommands: [
    Crawl.self,
    Fetch.self,
    Index.self,
    Serve.self    // ← Move from cupertino-mcp
]
```

---

#### 2. Remove Non-functional `packages` Type from Crawl

**Current (broken):**
```swift
enum CrawlType {
    case packages    // ← Doesn't work
}
```

**Proposed:**
```swift
enum CrawlType {
    case docs
    case swift
    case evolution
    case all       // Rename to 'web' for clarity?
}
```

**Rationale:**
- Removes confusion
- Users directed to `fetch --type packages` instead

---

#### 3. Add `fetch --type all`

**Current:**
```bash
cupertino fetch --type packages
cupertino fetch --type code
```

**Proposed:**
```bash
cupertino fetch --type all

# Or just:
cupertino fetch    # Default to 'all'
```

**Implementation:**
```swift
enum FetchType {
    case packages
    case code
    case all       // ← New: runs both in parallel
}
```

---

#### 4. Standardize Option Naming

**Current inconsistency:**
```bash
--output-dir      # Crawl, Fetch
--docs-dir        # Index, Serve
```

**Proposed standard:**
```bash
# Always use specific names
--docs-dir         # For Apple docs
--evolution-dir    # For Swift Evolution
--packages-dir     # For packages
--sample-code-dir  # For sample code
--search-db        # For database
```

**Or use generic names:**
```bash
# Always use generic names
--output-dir       # All output locations
--index-db        # Search database
```

**Recommendation:** Use specific names (first option)
- More explicit
- Reduces ambiguity
- Aligns with current Index/Serve commands

---

### Priority 2: High-Value Additions

#### 5. Add "Do Everything" Command

**Proposed:**

```bash
# New command: setup
cupertino setup [--type TYPE]

# Runs in sequence:
# 1. crawl --type all
# 2. fetch --type all
# 3. index
```

**With options:**
```bash
# Full setup
cupertino setup --all

# Minimal setup (docs only)
cupertino setup --minimal

# Custom
cupertino setup --crawl-only
```

**Implementation:**
```swift
struct Setup: AsyncParsableCommand {
    enum SetupType: String, ExpressibleByArgument {
        case all      // Everything
        case minimal  // Just docs + index
        case docs     // Only documentation
    }

    @Option var type: SetupType = .all

    func run() async throws {
        // Run commands in sequence
        try await crawl()
        try await fetch()
        try await index()
    }
}
```

---

#### 6. Add Validation Command

**Proposed:**

```bash
cupertino doctor [--verbose]

# Output example:
🏥 Cupertino Health Check

✅ Installation
   ✓ cupertino binary: v0.1.5
   ✓ SQLite FTS5 support: available

✅ Documentation
   ✓ Apple docs: 5,234 pages in ~/.cupertino/docs
   ✓ Swift.org: 1,456 pages in ~/.cupertino/swift-org
   ✓ Swift Evolution: 412 proposals in ~/.cupertino/swift-evolution

✅ Resources
   ✓ Sample code catalog: 607 entries (embedded)
   ✓ Packages catalog: 5,847 packages (embedded)

✅ Search Index
   ✓ Database: ~/.cupertino/search.db (45 MB)
   ✓ Indexed documents: 7,102
   ✓ Frameworks: 156

❌ Sample Code
   ✗ No sample code downloaded
   → Run: cupertino fetch --type code

Summary: 4/5 components ready
```

**Implementation:**
```swift
struct Doctor: AsyncParsableCommand {
    @Flag var verbose: Bool = false

    func run() async throws {
        // Check binary version
        // Check docs directories
        // Check search.db
        // Check embedded resources
        // Report status
    }
}
```

---

#### 7. Add Cleanup Command

**Proposed:**

```bash
cupertino clean [--type TYPE] [--dry-run]

# Clean specific type
cupertino clean --type docs

# Clean everything
cupertino clean --all

# Show what would be deleted
cupertino clean --dry-run
```

**Implementation:**
```swift
struct Clean: AsyncParsableCommand {
    enum CleanType: String, ExpressibleByArgument {
        case docs
        case evolution
        case packages
        case sampleCode = "sample-code"
        case index
        case all
    }

    @Option var type: CleanType = .all
    @Flag var dryRun: Bool = false

    func run() async throws {
        // Delete specified directories/files
        // Show what was deleted
    }
}
```

---

#### 8. Add Update Command

**Proposed:**

```bash
# Update embedded catalogs
cupertino update-catalogs

# Incremental update (only changed docs)
cupertino update --type docs --incremental

# Force full update
cupertino update --type all --force
```

**Benefits:**
- Addresses TODO #7
- Better user experience for keeping data fresh

---

### Priority 3: Nice-to-Have Improvements

#### 9. Add Shorthand Flags

**Proposed:**

```bash
cupertino fetch -t docs -m 1000 -o ~/docs
# Instead of:
cupertino fetch --type docs --max-pages 1000 --output-dir ~/docs
```

**Mapping:**
```swift
@Option(name: [.short("t"), .long("type")])
var type: CrawlType = .docs

@Option(name: [.short("m"), .long("max-pages")])
var maxPages: Int = 15000

@Option(name: [.short("o"), .long("output-dir")])
var outputDir: String?
```

---

#### 10. Add Progress/Verbosity Control

**Proposed:**

```bash
# Quiet mode (errors only)
cupertino fetch --quiet

# Verbose mode (detailed progress)
cupertino fetch --verbose

# JSON output (machine-readable)
cupertino fetch --json > output.json
```

**Implementation:**
```swift
enum OutputMode: String, ExpressibleByArgument {
    case normal
    case quiet
    case verbose
    case json
}

@Option var output: OutputMode = .normal
```

---

#### 11. Add Config File Support

**Proposed config:** `~/.cupertino/config.toml`

```toml
[directories]
docs = "~/Developer/cupertino/docs"
evolution = "~/Developer/cupertino/evolution"
search_db = "~/Developer/cupertino/search.db"

[limits]
max_pages = 10000
max_depth = 12

[github]
token = "${GITHUB_TOKEN}"

[output]
mode = "verbose"
```

**Usage:**
```bash
# Uses config automatically
cupertino fetch

# Override config
cupertino fetch --max-pages 5000
```

---

## Proposed Command Structure

### New Command Hierarchy

```
cupertino [COMMAND] [OPTIONS]

Commands:
  crawl          Crawl documentation from web sources
  fetch          Fetch resources via APIs
  index          Build search index
  serve          Start MCP server
  setup          Run complete setup (crawl + fetch + index)
  update         Update existing data incrementally
  update-catalogs Update embedded resource catalogs
  clean          Remove downloaded data
  doctor         Check installation health
  help           Show help information
```

### Comparison: Current vs Proposed

| Feature | Current | Proposed |
|---------|---------|----------|
| **Binaries** | 2 (`cupertino`, `cupertino-mcp`) | 1 (`cupertino`) |
| **Commands** | 4 (crawl, fetch, index, serve) | 9 (+setup, update, clean, doctor, update-catalogs) |
| **Total Options** | 27 | ~35 (with new commands) |
| **Config File** | ❌ No | ✅ Yes |
| **Shorthand Flags** | ❌ No | ✅ Yes |
| **Verbosity Control** | ❌ No | ✅ Yes (--quiet, --verbose, --json) |
| **Do Everything** | ❌ Manual | ✅ `setup` command |
| **Validation** | ❌ Manual | ✅ `doctor` command |
| **Cleanup** | ❌ Manual | ✅ `clean` command |

---

## Migration Path

### Phase 1: Critical Fixes (v0.2.0)

1. ✅ Merge `cupertino-mcp` into `cupertino`
   - `cupertino serve` replaces `cupertino-mcp serve`
   - Keep `cupertino-mcp` as deprecated alias for one version

2. ✅ Remove `crawl --type packages`
   - Update documentation to use `fetch --type packages`

3. ✅ Add `fetch --type all`
   - Parallel fetch of packages + code

4. ✅ Standardize option naming
   - Use `--docs-dir`, `--evolution-dir` everywhere
   - Deprecate `--output-dir` in crawl/fetch (but keep for compatibility)

### Phase 2: High-Value Additions (v0.3.0)

1. ✅ Add `setup` command
   - `cupertino setup --all` for first-time users

2. ✅ Add `doctor` command
   - Health check and validation

3. ✅ Add `clean` command
   - Safe data cleanup

4. ✅ Add `update-catalogs` command
   - Address TODO #7

### Phase 3: Polish (v0.4.0)

1. ✅ Add config file support
2. ✅ Add shorthand flags
3. ✅ Add verbosity control (--quiet, --verbose, --json)
4. ✅ Add `update` command for incremental updates

---

## Example User Workflows

### Workflow 1: First-Time Setup (Proposed)

**Current (4 commands, 2 binaries):**
```bash
cupertino fetch --type all
cupertino fetch --type packages
cupertino fetch --type code
cupertino save
cupertino-mcp serve
```

**Proposed (2 commands, 1 binary):**
```bash
cupertino setup --all
cupertino serve
```

---

### Workflow 2: Update Documentation (Proposed)

**Current:**
```bash
# Delete old data manually
rm -rf ~/.cupertino/docs
rm -rf ~/.cupertino/swift-evolution

# Recrawl everything
cupertino fetch --type all --force

# Rebuild index
cupertino save --clear
```

**Proposed:**
```bash
# Incremental update
cupertino update --type all

# Or force full refresh
cupertino update --type all --force
```

---

### Workflow 3: Troubleshooting (Proposed)

**Current:**
```bash
# Manually check directories
ls -lh ~/.cupertino/docs
ls -lh ~/.cupertino/search.db

# No automated validation
```

**Proposed:**
```bash
cupertino doctor

# Output shows missing components
# Suggests exact commands to fix
```

---

## Implementation Priority

### Must Have (v0.2.0)
- [ ] Merge CLIs into single binary
- [ ] Remove broken `crawl --type packages`
- [ ] Add `fetch --type all`
- [ ] Standardize option naming

### Should Have (v0.3.0)
- [ ] Add `setup` command
- [ ] Add `doctor` command
- [ ] Add `clean` command
- [ ] Add `update-catalogs` command

### Nice to Have (v0.4.0)
- [ ] Config file support
- [ ] Shorthand flags (-t, -o, -m)
- [ ] Verbosity control (--quiet, --verbose)
- [ ] JSON output mode
- [ ] `update` command for incremental updates

---

## Open Questions

1. **Command naming:** Should MCP server be `serve` or `mcp serve`?
   - Recommendation: Just `serve` (simpler)

2. **Default behavior:** Should `cupertino` with no args show help or run `setup`?
   - Current: Runs `crawl` (default subcommand)
   - Recommendation: Keep current behavior, add `setup` as explicit command

3. **Config file format:** TOML, YAML, or JSON?
   - Recommendation: TOML (human-friendly, widely supported)

4. **Update strategy:** Full replacement or incremental?
   - Recommendation: Both - default incremental, `--force` for full

5. **Backward compatibility:** Keep deprecated options for how long?
   - Recommendation: 2 versions (deprecate in v0.2, remove in v0.4)

---

## Summary

### Current Problems
1. ❌ Two separate CLIs (`cupertino` + `cupertino-mcp`)
2. ❌ Broken `crawl --type packages`
3. ❌ No `fetch --type all`
4. ❌ Inconsistent option naming
5. ❌ No "do everything" command
6. ❌ No validation/health check
7. ❌ No cleanup command
8. ❌ Verbose multi-step workflows

### Proposed Solutions
1. ✅ Merge into single CLI
2. ✅ Remove broken features
3. ✅ Add missing convenience commands
4. ✅ Standardize naming
5. ✅ Add `setup`, `doctor`, `clean`, `update-catalogs`
6. ✅ Support config files
7. ✅ Add verbosity control

### Impact
- **Better UX:** One command for setup instead of 5
- **Less confusion:** Single binary, clear commands
- **More powerful:** Health checks, cleanup, incremental updates
- **More flexible:** Config files, output modes

---

**Next Steps:** Review with maintainer, prioritize features, implement Phase 1

**Document Version:** 1.0
**Created:** 2025-11-18
**Author:** Claude (Anthropic)
**Project:** Cupertino - Apple Documentation CLI & MCP Server

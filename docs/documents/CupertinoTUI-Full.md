# Cupertino TUI - Complete Design Specification

## Overview

`cupertino-tui` is a Terminal User Interface for interacting with all Cupertino functionality. It provides real-time monitoring, interactive control, and a unified interface for documentation crawling, search indexing, MCP server management, and package curation.

## Architecture

### Package Structure

```swift
// Package.swift additions
.executable(name: "cupertino-tui", targets: ["CupertinoTUI"]),

let tuiTarget = Target.executableTarget(
    name: "CupertinoTUI",
    dependencies: [
        "Shared",
        "Core",        // For crawling functionality
        "Search",      // For search index operations
        "MCP",         // For MCP server control
        "MCPSupport",  // For resource providers
        "Resources",   // For package catalogs
        "Logging",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ]
)
```

### File Structure

```
Sources/CupertinoTUI/
├── main.swift                  # Entry point
├── CupertinoTUIApp.swift       # Main application logic
├── TUI/
│   ├── Screen.swift            # Terminal control & ANSI codes
│   ├── Colors.swift            # Color definitions
│   ├── Input.swift             # Keyboard input handling
│   └── Layout.swift            # Box drawing & layout
├── Models/
│   ├── AppState.swift          # Application state
│   ├── ViewMode.swift          # View navigation
│   └── StatusInfo.swift        # System status tracking
└── Views/
    ├── MainMenuView.swift      # Main navigation menu
    ├── DashboardView.swift     # System overview
    ├── FetchView.swift         # Fetch command UI (was: CrawlManagerView)
    ├── SaveView.swift          # Save command UI (was: SearchIndexView)
    ├── ServeView.swift         # Serve command UI (was: MCPServerView)
    ├── DoctorView.swift        # Doctor command UI
    ├── PackageView.swift       # Package curation
    ├── ConfigView.swift        # Configuration editor
    └── LogsView.swift          # Log viewer
```

## CLI Command Mapping

The TUI provides interactive interfaces for all CLI commands:

| CLI Command | TUI View | Key | Description |
|-------------|----------|-----|-------------|
| `cupertino fetch` | FetchView | `f` | Fetch documentation and resources |
| `cupertino save` | SaveView | `s` | Build search indexes |
| `cupertino serve` | ServeView | `m` | Control MCP server |
| `cupertino doctor` | DoctorView | `d` | System health checks |
| (none) | PackageView | `p` | Curate package catalog |
| (none) | ConfigView | `c` | Edit configuration |
| (none) | LogsView | `l` | View logs |

---

## View Specifications

### Main Menu

```
┌─ Cupertino TUI ─────────────────────────────────────────────────────┐
│ Status: ● MCP Server Running (PID 12345)      Docs: 13,842 indexed  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  1  Dashboard        System status & statistics overview            │
│  2  Fetch            Fetch documentation (fetch command)            │
│  3  Save             Build search indexes (save command)            │
│  4  Serve            Control MCP server (serve command)             │
│  5  Doctor           System health checks (doctor command)          │
│  6  Packages         Curate Swift packages catalog                  │
│  7  Configuration    View and edit settings                         │
│  8  Logs             View application logs                          │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ ↑↓:Navigate  Enter:Select  q:Quit  ?:Help                          │
└──────────────────────────────────────────────────────────────────────┘
```

---

### 1. Dashboard View

**Purpose:** Overview of all Cupertino subsystems

```
┌─ Dashboard ──────────────────────────────────────────────────────────┐
│                                                                       │
│  Documentation Status                                                │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Apple Docs:     13,842 pages    Last fetched: 2 hours ago      │ │
│  │ Swift Evolution:   414 proposals Last fetched: 1 day ago       │ │
│  │ Swift Packages:     46 priority  Last fetched: Never           │ │
│  │ Sample Code:         8 samples   Last fetched: Never           │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Search Index                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Total Documents: 14,256                                         │ │
│  │ Index Size:      52.3 MB                                        │ │
│  │ Last Build:      3 hours ago                                    │ │
│  │ Status:          ✓ Healthy                                      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  MCP Server                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Status:          ● Running (PID 12345)                          │ │
│  │ Transport:       stdio                                           │ │
│  │ Requests Today:  127 requests                                   │ │
│  │ Uptime:          4h 23m                                         │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Quick Actions                                                       │
│  [f] Fetch Docs    [s] Build Index    [m] MCP Server    [d] Doctor  │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ r:Refresh  Esc:Menu                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `r` - Refresh dashboard
- `f` - Jump to Fetch view
- `s` - Jump to Save view
- `m` - Jump to Serve view
- `d` - Jump to Doctor view
- `Esc` - Return to main menu

---

### 2. Fetch View

**Purpose:** Interactive interface for `cupertino fetch` command

```
┌─ Fetch Documentation ────────────────────────────────────────────────┐
│ Type: docs    Status: Crawling    Progress: 1,234/13,842 (8.9%)     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Fetch Type Selection                                                │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ► [docs]      Apple Documentation (developer.apple.com)         │ │
│  │   [swift]     Swift.org Documentation                           │ │
│  │   [evolution] Swift Evolution Proposals                         │ │
│  │   [packages]  Swift Packages Metadata                           │ │
│  │   [code]      Sample Code (requires authentication)             │ │
│  │   [all]       All types in parallel                             │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Options                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Max Pages:        13,000                                        │ │
│  │ Max Depth:        15                                            │ │
│  │ Force Recrawl:    [ ] (unchecked)                               │ │
│  │ Resume Session:   [✓] (checked)                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Current Operation                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ [████████░░░░░░░░░░░░░░░░░░░░] 8.9%                             │ │
│  │                                                                  │ │
│  │ Current: Foundation/NSString                                    │ │
│  │ Speed:   12.3 pages/min                                         │ │
│  │ ETA:     1h 42m remaining                                       │ │
│  │                                                                  │ │
│  │ Stats:   1,234 crawled  |  89 new  |  12 updated  |  0 errors  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Recent Pages (Last 5)                                               │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ Foundation/NSString                            12.3 KB  0.8s  │ │
│  │ ✓ Foundation/NSArray                             8.7 KB   0.6s  │ │
│  │ ✗ UIKit/UIViewController (timeout)               -        5.0s  │ │
│  │ ✓ Combine/Publisher                              18.9 KB  1.3s  │ │
│  │ ✓ SwiftUI/View                                   15.2 KB  1.1s  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ Enter:Start  p:Pause  x:Stop  t:Type  o:Options  l:Logs  Esc:Menu  │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `Enter` - Start fetch with current settings
- `t` - Change fetch type (cycles through docs/swift/evolution/packages/code/all)
- `o` - Edit options (opens options dialog)
- `p` - Pause active fetch
- `r` - Resume paused fetch
- `x` - Stop/cancel fetch
- `l` - View detailed logs
- `Esc` - Return to menu

**Fetch Types (matches CLI --type):**
- `docs` - Apple Documentation
- `swift` - Swift.org Documentation
- `evolution` - Swift Evolution Proposals
- `packages` - Swift Packages Metadata
- `code` - Sample Code
- `all` - All types in parallel

---

### 3. Save View

**Purpose:** Interactive interface for `cupertino save` command (build search index)

```
┌─ Build Search Index ─────────────────────────────────────────────────┐
│ Status: Building Index    Progress: 4,523/14,256 (31.7%)            │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Source Directories                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Docs:      ~/.cupertino/docs/           13,842 pages            │ │
│  │ Evolution: ~/.cupertino/swift-evolution/   414 proposals        │ │
│  │ Database:  ~/.cupertino/search.db                               │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Options                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Clear Existing Index:  [ ] (rebuild only changed documents)     │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Build Progress                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ [████████████░░░░░░░░░░░░░░░░░] 31.7%                           │ │
│  │                                                                  │ │
│  │ Processing: SwiftUI/View.md                                     │ │
│  │ Speed:      127 docs/sec                                        │ │
│  │ ETA:        1m 23s remaining                                    │ │
│  │                                                                  │ │
│  │ Processed:  4,523 / 14,256 documents                            │ │
│  │ Added:      4,401 new entries                                   │ │
│  │ Updated:    122 modified entries                                │ │
│  │ Errors:     0                                                   │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Index Statistics                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Total Documents:  4,523 (building...)                           │ │
│  │ Frameworks:       142                                           │ │
│  │ Index Size:       18.7 MB (growing...)                          │ │
│  │ Average Doc Size: 4.2 KB                                        │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ Enter:Start Build  c:Clear & Rebuild  x:Cancel  l:Logs  Esc:Menu   │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `Enter` - Start build with current settings
- `c` - Toggle "Clear Existing Index" option
- `x` - Cancel build operation
- `t` - Test search (opens search dialog)
- `l` - View detailed logs
- `Esc` - Return to menu

**Post-Build View:**

```
┌─ Search Index ───────────────────────────────────────────────────────┐
│ Status: Ready                                                        │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ✅ Index Build Complete!                                            │
│                                                                       │
│  Statistics                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Total Documents:  14,256                                        │ │
│  │ Frameworks:       287                                           │ │
│  │ Index Size:       52.3 MB                                       │ │
│  │ Build Time:       2m 34s                                        │ │
│  │ Last Build:       Just now                                      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Test Search                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Query: async await                                    [Enter]   │ │
│  │                                                                  │ │
│  │ Results: 14 documents found                                     │ │
│  │   1. Swift.Concurrency/Task                       Score: 0.89   │ │
│  │   2. Combine/Publisher                             Score: 0.82  │ │
│  │   3. SwiftUI/View                                  Score: 0.76  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ r:Rebuild  t:Test Search  f:List Frameworks  Esc:Menu              │
└──────────────────────────────────────────────────────────────────────┘
```

---

### 4. Serve View

**Purpose:** Interactive interface for `cupertino serve` command (MCP server control)

```
┌─ MCP Server Control ─────────────────────────────────────────────────┐
│ Status: ● Running                              Uptime: 4h 23m 12s   │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Server Information                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ PID:         12345                                              │ │
│  │ Transport:   stdio                                              │ │
│  │ Started:     2025-11-19 10:30:45                               │ │
│  │ Requests:    127 total  (0.5/min average)                      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Capabilities                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ Resources                                                     │ │
│  │   • apple-docs://{framework}/{page}                             │ │
│  │   • swift-evolution://{proposal-id}                             │ │
│  │                                                                  │ │
│  │ ✓ Tools                                                         │ │
│  │   • search_docs(query, limit, framework)                        │ │
│  │   • list_frameworks()                                           │ │
│  │                                                                  │ │
│  │ ✗ Prompts                                                       │ │
│  │   (none configured)                                             │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Recent Requests (Last 10)                                           │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ 10:45:23  tools/call      search_docs("async await")      142ms│ │
│  │ 10:44:18  resources/read  apple-docs://SwiftUI/View        89ms│ │
│  │ 10:43:05  tools/call      list_frameworks()                 12ms│ │
│  │ 10:42:33  resources/list                                    45ms│ │
│  │ 10:41:20  resources/read  swift-evolution://SE-0296         67ms│ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Statistics                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Total Requests:      127                                        │ │
│  │ Avg Response Time:   89ms                                       │ │
│  │ Errors:              0                                          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ s:Start  x:Stop  r:Restart  l:View Logs  t:Test Tool  Esc:Menu     │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `s` - Start MCP server
- `x` - Stop MCP server
- `r` - Restart MCP server
- `t` - Test tool (opens tool test dialog)
- `l` - View detailed logs
- `Esc` - Return to menu

**Note:** When the TUI is running, it cannot simultaneously run the MCP server in stdio mode. Options:
1. Display status of external server process
2. Run server in background and monitor via IPC/file
3. Show "Server managed externally" message

---

### 5. Doctor View

**Purpose:** Interactive interface for `cupertino doctor` command (health checks)

```
┌─ System Health Check ────────────────────────────────────────────────┐
│ Status: All Checks Passed ✓                                         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Environment                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ macOS Version:     15.1 (Sequoia)                             │ │
│  │ ✓ Swift Version:     6.2                                        │ │
│  │ ✓ Architecture:      arm64                                      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Directories                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ Base Directory:    ~/.cupertino/             [exists, 245 MB] │ │
│  │ ✓ Docs Directory:    ~/.cupertino/docs/        [13,842 files]  │ │
│  │ ✓ Evolution Dir:     ~/.cupertino/swift-evolution/ [414 files] │ │
│  │ ✓ Packages Dir:      ~/.cupertino/packages/    [46 files]      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Database                                                            │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ Search Database:   ~/.cupertino/search.db    [52.3 MB]       │ │
│  │ ✓ FTS5 Table:        docs_fts                   [14,256 docs]   │ │
│  │ ✓ Metadata Table:    docs_metadata              [valid schema]  │ │
│  │ ✓ Index Integrity:   All indexes valid                          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Configuration                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ Metadata File:     ~/.cupertino/docs/metadata.json [valid]   │ │
│  │ ✓ Priority Packages: Resources/priority-packages.json [46]     │ │
│  │ ⚠ GitHub Token:      Not set (rate limits apply)               │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  MCP Server                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ✓ Binary:            /usr/local/bin/cupertino   [executable]   │ │
│  │ ✗ Server Status:     Not running                                │ │
│  │ ✓ Claude Config:     ~/Library/Application Support/Claude/...  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ r:Re-run Checks  f:Fix Issues  v:Verbose  Esc:Menu                 │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `r` - Re-run health checks
- `f` - Attempt to fix common issues
- `v` - Toggle verbose output
- `Esc` - Return to menu

**Health Check Categories:**
1. **Environment** - macOS version, Swift version, architecture
2. **Directories** - All data directories exist and are readable
3. **Database** - Search database exists, schema valid, FTS5 working
4. **Configuration** - Metadata files valid, configs parseable
5. **MCP Server** - Binary exists, Claude Desktop configured

---

### 6. Packages View

**Purpose:** Curate Swift packages catalog (unique to TUI, no CLI equivalent)

```
┌─ Swift Packages Curator ─────────────────────────────────────────────┐
│ Sort: Stars ▼     Search: [          ]     Selected: 46/1,234      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  [★] pointfreeco/swift-composable-architecture         ⭐ 12,456    │
│      A library for building applications in a consistent way         │
│                                                                       │
│  [★] Alamofire/Alamofire                                ⭐ 89,855    │
│      Elegant HTTP Networking in Swift                                │
│                                                                       │
│  ► [ ] SwiftyJSON/SwiftyJSON                            ⭐ 22,134    │
│      The better way to deal with JSON data in Swift                  │
│                                                                       │
│  [ ] onevcat/Kingfisher                                 ⭐ 23,102    │
│      A lightweight, pure-Swift library for downloading images        │
│                                                                       │
│  [ ] ReactiveCocoa/ReactiveCocoa                        ⭐ 20,018    │
│      Cocoa framework for functional reactive programming             │
│                                                                       │
│  [ ] Quick/Quick                                        ⭐ 9,789     │
│      The Swift (and Objective-C) testing framework                   │
│                                                                       │
│  [ ] Quick/Nimble                                       ⭐ 4,823     │
│      A Matcher Framework for Swift and Objective-C                   │
│                                                                       │
│  [ ] realm/SwiftLint                                    ⭐ 18,456    │
│      A tool to enforce Swift style and conventions                   │
│                                                                       │
│  [ ] nicklockwood/SwiftFormat                           ⭐ 7,654     │
│      A command-line tool and Xcode Extension for formatting Swift    │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ Space:Toggle  g:GitHub  s:Sort  /:Search  w:Save  v:Selected  Esc  │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `↑`/`↓` or `k`/`j` - Navigate list
- `Space` - Toggle package selection
- `g` - Open package GitHub page in browser
- `s` - Cycle sort mode (Stars ▼ / Name ▲ / Recent ▼)
- `/` - Enter search mode
- `v` - Toggle "show only selected" filter
- `w` - Save selections to priority-packages.json
- `r` - Refresh package list from catalog
- `Esc` - Return to menu

**Sort Modes:**
- **Stars ▼** - Sort by GitHub stars (descending)
- **Name ▲** - Sort alphabetically by name
- **Recent ▼** - Sort by last update date

---

### 7. Configuration View

**Purpose:** View and edit Cupertino configuration

```
┌─ Configuration ──────────────────────────────────────────────────────┐
│                                                                       │
│  Fetch Settings                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ ► Delay Between Requests:  0.5 seconds                          │ │
│  │   Max Concurrent Pages:    1                                    │ │
│  │   Timeout Per Page:        30 seconds                           │ │
│  │   Auto-save Session:       Every 100 pages                      │ │
│  │   Max Pages (default):     13,000                               │ │
│  │   Max Depth (default):     15                                   │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Search Settings                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │   FTS5 Tokenizer:          porter                               │ │
│  │   Max Results:             50                                   │ │
│  │   Ranking Algorithm:       BM25                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Paths                                                               │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │   Base Directory:          ~/.cupertino/                        │ │
│  │   Docs Directory:          ~/.cupertino/docs/                   │ │
│  │   Evolution Directory:     ~/.cupertino/swift-evolution/        │ │
│  │   Packages Directory:      ~/.cupertino/packages/               │ │
│  │   Search Database:         ~/.cupertino/search.db               │ │
│  │   Metadata File:           ~/.cupertino/docs/metadata.json      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Environment                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │   GITHUB_TOKEN:            ⚠ Not set                            │ │
│  │   AUDIO_MUTED:             false                                │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ e:Edit  r:Reset to Defaults  s:Save  Esc:Menu                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `↑`/`↓` - Navigate settings
- `e` - Edit selected setting
- `r` - Reset all to defaults
- `s` - Save configuration
- `Esc` - Return to menu (prompts if unsaved)

**Editable Settings:**
- Fetch: delay, max concurrent, timeout, auto-save interval
- Search: max results, ranking algorithm
- Paths: all directory paths (with validation)

---

### 8. Logs View

**Purpose:** Real-time log viewer with filtering

```
┌─ Logs ───────────────────────────────────────────────────────────────┐
│ Filter: [All]  Level: [Info]  Category: [All]      Auto-scroll: ON  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  10:45:23 [INFO]  [crawler]   Starting fetch session...             │
│  10:45:24 [INFO]  [crawler]   Loaded 12,608 URLs from queue         │
│  10:45:25 [DEBUG] [crawler]   Fetching Foundation/NSString          │
│  10:45:26 [INFO]  [crawler]   Downloaded Foundation/NSString (12 KB)│
│  10:45:27 [DEBUG] [crawler]   Converting HTML to Markdown...        │
│  10:45:27 [INFO]  [crawler]   Saved Foundation/NSString.md          │
│  10:45:28 [WARN]  [crawler]   Slow page: UIKit/UIViewController     │
│  10:45:33 [ERROR] [crawler]   Timeout: UIKit/UIViewController (5s)  │
│  10:45:34 [INFO]  [crawler]   Fetching Combine/Publisher            │
│  10:45:35 [INFO]  [crawler]   Downloaded Combine/Publisher (18 KB)  │
│  10:45:36 [DEBUG] [search]    Building FTS5 index...                │
│  10:45:37 [INFO]  [search]    Indexed 1,234 documents               │
│  10:45:38 [INFO]  [mcp]       Server started on stdio               │
│  10:45:39 [DEBUG] [transport] Received JSON-RPC request             │
│  10:45:40 [INFO]  [mcp]       tools/call: search_docs               │
│                                                                       │
│  [Showing last 100 lines, 45,678 total]                             │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│ f:Filter  l:Level  c:Category  a:Auto-scroll  x:Clear  Esc:Menu    │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
- `f` - Filter by text (opens input dialog)
- `l` - Cycle log level filter (All/Debug/Info/Warn/Error)
- `c` - Cycle category filter (All/crawler/mcp/search/cli/transport)
- `a` - Toggle auto-scroll
- `x` - Clear log buffer
- `↑`/`↓` - Scroll (when auto-scroll off)
- `Esc` - Return to menu

**Log Categories (from Logging package):**
- `crawler` - Fetch/crawl operations
- `mcp` - MCP server operations
- `search` - Search index operations
- `cli` - CLI command execution
- `transport` - MCP transport layer
- `pdf` - PDF operations
- `evolution` - Swift Evolution operations
- `samples` - Sample code operations

---

## Core Components Implementation

### Screen.swift - Terminal Control

```swift
import Foundation

actor Screen {
    // ANSI escape codes
    static let ESC = "\u{001B}["
    static let clearScreen = "\(ESC)2J"
    static let hideCursor = "\(ESC)?25l"
    static let showCursor = "\(ESC)?25h"
    static let home = "\(ESC)H"
    static let altScreenOn = "\(ESC)?1049h"
    static let altScreenOff = "\(ESC)?1049l"

    // Terminal size
    func getSize() -> (rows: Int, cols: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
            return (Int(w.ws_row), Int(w.ws_col))
        }
        return (24, 80)
    }

    // Raw mode (no buffering, no echo)
    func enableRawMode() -> termios {
        var original = termios()
        tcgetattr(STDIN_FILENO, &original)

        var raw = original
        raw.c_lflag &= ~(UInt(ECHO | ICANON | ISIG | IEXTEN))
        raw.c_iflag &= ~(UInt(IXON | ICRNL | BRKINT | INPCK | ISTRIP))
        raw.c_oflag &= ~(UInt(OPOST))
        raw.c_cflag |= UInt(CS8)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        return original
    }

    func disableRawMode(_ original: termios) {
        var orig = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
    }

    // Cursor positioning
    func moveTo(row: Int, col: Int) -> String {
        "\(Screen.ESC)\(row);\(col)H"
    }

    // Rendering
    func render(_ content: String) {
        print(Screen.clearScreen + Screen.home + content, terminator: "")
        fflush(stdout)
    }

    // Enter/exit alternate screen buffer
    func enterAltScreen() {
        print(Screen.altScreenOn, terminator: "")
        fflush(stdout)
    }

    func exitAltScreen() {
        print(Screen.altScreenOff, terminator: "")
        fflush(stdout)
    }
}
```

### Input.swift - Keyboard Handling

```swift
import Foundation

enum Key {
    case up, down, left, right
    case pageUp, pageDown
    case home, end
    case space, tab, enter, escape
    case char(Character)
    case ctrl(Character)
    case delete, backspace
    case unknown
}

class Input {
    func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 8)
        let count = read(STDIN_FILENO, &buffer, 8)

        if count == 1 {
            switch buffer[0] {
            case 27: return .escape
            case 32: return .space
            case 9: return .tab
            case 13: return .enter
            case 127: return .backspace
            case 3: return .ctrl("c")
            case 4: return .ctrl("d")
            case 1...26:
                let char = Character(UnicodeScalar(buffer[0] + 96))
                return .ctrl(char)
            case 65...90, 97...122:
                return .char(Character(UnicodeScalar(buffer[0])))
            case 48...57:
                return .char(Character(UnicodeScalar(buffer[0])))
            case 47: return .char("/")
            default: return .unknown
            }
        }

        // Arrow keys: ESC [ A/B/C/D
        if count >= 3 && buffer[0] == 27 && buffer[1] == 91 {
            switch buffer[2] {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            case 53: return .pageUp    // ESC [ 5 ~
            case 54: return .pageDown  // ESC [ 6 ~
            case 72: return .home
            case 70: return .end
            default: return .unknown
            }
        }

        return .unknown
    }
}
```

### Layout.swift - Box Drawing

```swift
struct Box {
    // Box drawing characters (UTF-8)
    static let topLeft = "┌"
    static let topRight = "┐"
    static let bottomLeft = "└"
    static let bottomRight = "┘"
    static let horizontal = "─"
    static let vertical = "│"
    static let teeDown = "┬"
    static let teeUp = "┴"
    static let teeRight = "├"
    static let teeLeft = "┤"
    static let cross = "┼"

    static func draw(width: Int, height: Int, title: String? = nil) -> String {
        var result = ""

        // Top border
        result += topLeft
        if let title = title {
            let titleText = " \(title) "
            let remaining = width - 2 - titleText.count
            result += String(repeating: horizontal, count: remaining / 2)
            result += titleText
            result += String(repeating: horizontal, count: remaining - remaining / 2)
        } else {
            result += String(repeating: horizontal, count: width - 2)
        }
        result += topRight + "\n"

        // Middle (empty lines)
        for _ in 0..<(height - 2) {
            result += vertical + String(repeating: " ", count: width - 2) + vertical + "\n"
        }

        // Bottom border
        result += bottomLeft + String(repeating: horizontal, count: width - 2) + bottomRight + "\n"

        return result
    }

    static func horizontalLine(width: Int, title: String? = nil) -> String {
        var result = teeRight
        if let title = title {
            let titleText = " \(title) "
            let remaining = width - 2 - titleText.count
            result += String(repeating: horizontal, count: remaining / 2)
            result += titleText
            result += String(repeating: horizontal, count: remaining - remaining / 2)
        } else {
            result += String(repeating: horizontal, count: width - 2)
        }
        result += teeLeft
        return result
    }
}
```

### Colors.swift - ANSI Colors

```swift
struct Colors {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let italic = "\u{001B}[3m"
    static let underline = "\u{001B}[4m"
    static let invert = "\u{001B}[7m"

    // Foreground colors
    static let black = "\u{001B}[30m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let white = "\u{001B}[37m"
    static let gray = "\u{001B}[90m"

    // Bright foreground colors
    static let brightRed = "\u{001B}[91m"
    static let brightGreen = "\u{001B}[92m"
    static let brightYellow = "\u{001B}[93m"
    static let brightBlue = "\u{001B}[94m"
    static let brightMagenta = "\u{001B}[95m"
    static let brightCyan = "\u{001B}[96m"
    static let brightWhite = "\u{001B}[97m"

    // Status indicators
    static let success = brightGreen + "✓" + reset
    static let failure = brightRed + "✗" + reset
    static let warning = brightYellow + "⚠" + reset
    static let info = brightBlue + "ℹ" + reset
    static let running = brightGreen + "●" + reset
    static let stopped = gray + "○" + reset
}
```

---

## Application State Management

### AppState.swift

```swift
enum ViewMode {
    case mainMenu
    case dashboard
    case fetch
    case save
    case serve
    case doctor
    case packages
    case configuration
    case logs
}

@MainActor
class AppState: ObservableObject {
    var currentView: ViewMode = .mainMenu
    var selectedMenuItem: Int = 0

    // Fetch state
    var fetchType: FetchType = .docs
    var fetchInProgress: Bool = false
    var fetchProgress: Double = 0.0
    var fetchStats: FetchStatistics?

    // Save state
    var saveInProgress: Bool = false
    var saveProgress: Double = 0.0
    var indexStats: IndexStatistics?

    // Serve state
    var serverRunning: Bool = false
    var serverPID: Int32?
    var serverUptime: TimeInterval = 0
    var serverStats: ServerStatistics?

    // Doctor state
    var healthChecks: [HealthCheck] = []

    // Package state
    var packages: [PackageEntry] = []
    var packageCursor: Int = 0
    var packageFilter: String = ""

    // Configuration state
    var config: Configuration
    var configModified: Bool = false

    // Logs state
    var logs: [LogEntry] = []
    var logFilter: LogFilter = .all
    var autoScroll: Bool = true

    init() {
        self.config = Configuration.loadDefault()
    }
}
```

---

## Main Application Loop

### CupertinoTUIApp.swift

```swift
@main
struct CupertinoTUIApp {
    static func main() async throws {
        let state = AppState()
        let screen = Screen()
        let input = Input()

        // Setup terminal
        let originalTermios = await screen.enableRawMode()
        await screen.enterAltScreen()
        print(Screen.hideCursor, terminator: "")

        defer {
            Task {
                await screen.exitAltScreen()
                await screen.disableRawMode(originalTermios)
                print(Screen.showCursor)
            }
        }

        var running = true
        while running {
            // Render current view
            let (rows, cols) = await screen.getSize()
            let content = renderView(state: state, width: cols, height: rows)
            await screen.render(content)

            // Handle input
            if let key = input.readKey() {
                switch state.currentView {
                case .mainMenu:
                    running = handleMainMenuInput(key: key, state: state)
                case .dashboard:
                    handleDashboardInput(key: key, state: state)
                case .fetch:
                    await handleFetchInput(key: key, state: state)
                case .save:
                    await handleSaveInput(key: key, state: state)
                case .serve:
                    await handleServeInput(key: key, state: state)
                case .doctor:
                    await handleDoctorInput(key: key, state: state)
                case .packages:
                    handlePackagesInput(key: key, state: state)
                case .configuration:
                    handleConfigurationInput(key: key, state: state)
                case .logs:
                    handleLogsInput(key: key, state: state)
                }
            }

            // Update background tasks
            await updateState(state: state)

            // Small delay to avoid busy loop
            try await Task.sleep(nanoseconds: 16_000_000) // ~60 FPS
        }
    }

    private static func renderView(state: AppState, width: Int, height: Int) -> String {
        switch state.currentView {
        case .mainMenu:
            return MainMenuView.render(state: state, width: width, height: height)
        case .dashboard:
            return DashboardView.render(state: state, width: width, height: height)
        case .fetch:
            return FetchView.render(state: state, width: width, height: height)
        case .save:
            return SaveView.render(state: state, width: width, height: height)
        case .serve:
            return ServeView.render(state: state, width: width, height: height)
        case .doctor:
            return DoctorView.render(state: state, width: width, height: height)
        case .packages:
            return PackageView.render(state: state, width: width, height: height)
        case .configuration:
            return ConfigView.render(state: state, width: width, height: height)
        case .logs:
            return LogsView.render(state: state, width: width, height: height)
        }
    }
}
```

---

## Testing Strategy

### Phase 1: Basic Structure (Week 1)
1. Implement Screen, Input, Layout, Colors
2. Create main menu with navigation
3. Test keyboard input handling
4. Verify box drawing renders correctly

### Phase 2: Static Views (Week 2)
1. Implement all view render functions with mock data
2. Test view switching
3. Verify layout at different terminal sizes
4. Add color scheme

### Phase 3: Integration (Week 3)
1. Connect FetchView to Core.Crawler
2. Connect SaveView to Search.IndexBuilder
3. Connect ServeView to MCP server monitoring
4. Connect DoctorView to health check logic

### Phase 4: Interactive Features (Week 4)
1. Implement real-time progress updates
2. Add log streaming to LogsView
3. Implement package selection in PackageView
4. Add configuration editing

### Phase 5: Polish (Week 5)
1. Handle terminal resize gracefully
2. Add error handling and recovery
3. Improve performance (reduce redraws)
4. Add keyboard shortcuts help screen

---

## Build and Installation

### Makefile Addition

```makefile
# Build TUI binary
build-tui:
	cd Packages && swift build -c release --product cupertino-tui

# Install TUI binary
install-tui: build-tui
	sudo cp Packages/.build/release/cupertino-tui /usr/local/bin/

# Install both CLI and TUI
install-all: install install-tui
```

### Usage

```bash
# Build TUI
make build-tui

# Install TUI
sudo make install-tui

# Run TUI
cupertino-tui
```

---

## Summary

This design provides:

1. **Complete CLI Parity** - Every CLI command has a TUI interface
2. **Command Name Alignment** - Views named after CLI commands (fetch, save, serve, doctor)
3. **Real-time Monitoring** - Live progress updates for long-running operations
4. **Interactive Control** - Start/stop/pause operations from TUI
5. **Package Curation** - Visual interface for managing priority packages
6. **Configuration Management** - Edit settings without touching JSON
7. **Health Monitoring** - System checks and diagnostics
8. **Log Viewing** - Integrated log viewer with filtering

The TUI complements the CLI by providing:
- Better visibility during long operations
- Easier exploration and discovery
- Visual package curation
- Integrated monitoring dashboard
- Real-time log viewing

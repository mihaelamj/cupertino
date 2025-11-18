# Cupertino v0.2.0 Refactoring Plan

**Date:** 2025-11-18
**Status:** 🚧 IN PROGRESS
**Estimated Duration:** 21 days
**Breaking Changes:** YES

---

## 📋 **Table of Contents**

1. [Overview](#overview)
2. [Current State](#current-state)
3. [Target State](#target-state)
4. [Package Dependency Map](#package-dependency-map)
5. [API Changes](#api-changes)
6. [Implementation Phases](#implementation-phases)
7. [Testing Strategy](#testing-strategy)
8. [Rollback Plan](#rollback-plan)

---

## 📊 **Overview**

This refactoring combines two major architectural improvements:

### **1. Namespace-Based Command Structure**
```
cupertino
 ├─ mcp serve / doctor
 ├─ data crawl / fetch / index
 ├─ db init / migrate / vacuum
 ├─ config show / edit
 ├─ doctor
 └─ clean
```

### **2. Swift Namespace Pattern for Packages**
```swift
// Before
import CupertinoLogging
let logger = CupertinoLogger.crawler

// After
import Logging
let logger = Logging.Logger.crawler
```

---

## 🔍 **Current State**

### **Package Structure**

| Package | Type | Dependencies | LOC (est) |
|---------|------|--------------|-----------|
| `MCPShared` | Library | None | ~200 |
| `MCPTransport` | Library | MCPShared, CupertinoShared | ~300 |
| `MCPServer` | Library | MCPShared, MCPTransport, CupertinoShared | ~500 |
| `CupertinoLogging` | Library | CupertinoShared | ~100 |
| `CupertinoShared` | Library | MCPShared | ~1000 |
| `CupertinoCore` | Library | CupertinoShared, CupertinoLogging, CupertinoResources | ~2000 |
| `CupertinoSearch` | Library | CupertinoShared, CupertinoLogging | ~800 |
| `CupertinoResources` | Library | None (resources only) | 0 |
| `CupertinoMCPSupport` | Library | MCPServer, MCPShared, CupertinoShared, CupertinoLogging | ~300 |
| `CupertinoSearchToolProvider` | Library | MCPServer, MCPShared, CupertinoSearch | ~200 |
| `CupertinoCLI` | Executable | CupertinoShared, CupertinoCore, CupertinoSearch, CupertinoLogging | ~500 |
| `CupertinoMCP` | Executable | MCPServer, MCPTransport, CupertinoShared, CupertinoCore, CupertinoSearch, CupertinoMCPSupport, CupertinoSearchToolProvider, CupertinoLogging | ~150 |

**Total Packages:** 12
**Total LOC:** ~6,050

### **Dependency Graph**

```
MCPShared (foundation)
  ↓
├─ MCPTransport → CupertinoShared
│    ↓
└─ MCPServer → CupertinoShared
     ↓
     ├─ CupertinoMCPSupport
     └─ CupertinoSearchToolProvider

CupertinoShared (foundation)
  ↓
├─ CupertinoLogging
├─ CupertinoCore → CupertinoResources
└─ CupertinoSearch

CupertinoCLI (executable)
  ↓ (depends on)
  CupertinoShared, CupertinoCore, CupertinoSearch, CupertinoLogging

CupertinoMCP (executable)
  ↓ (depends on)
  All of the above
```

---

## 🎯 **Target State**

### **New Package Structure**

| New Name | Old Name(s) | Type | Purpose |
|----------|-------------|------|---------|
| `MCP` | MCPShared + MCPTransport + MCPServer | Library | Consolidated MCP framework |
| `Logging` | CupertinoLogging | Library | Logging utilities |
| `Shared` | CupertinoShared | Library | Shared types and constants |
| `Core` | CupertinoCore | Library | Core crawling logic |
| `Search` | CupertinoSearch | Library | Search indexing |
| `Resources` | CupertinoResources | Library | Static resources |
| `MCPSupport` | CupertinoMCPSupport | Library | MCP integration support |
| `SearchToolProvider` | CupertinoSearchToolProvider | Library | MCP search tools |
| `CLI` | CupertinoCLI | Executable | Main CLI binary |

**Total Packages:** 9 (reduced from 12)
**Consolidations:**
- MCPShared + MCPTransport + MCPServer → MCP
- CupertinoMCP removed (merged into CLI as `mcp serve` command)

### **New Dependency Graph**

```
MCP (foundation - consolidated)
  ↓
├─ MCPSupport → Shared, Logging
└─ SearchToolProvider → Search

Shared (foundation)
  ↓
├─ Logging
├─ Core → Resources
└─ Search

CLI (executable)
  ↓ (depends on)
  All of the above
```

---

## 🔄 **Package Dependency Map**

### **MCP Module (Consolidated)**

**Old Structure:**
- `MCPShared` (foundation)
  - No dependencies
- `MCPTransport`
  - Depends on: MCPShared, CupertinoShared
- `MCPServer`
  - Depends on: MCPShared, MCPTransport, CupertinoShared

**New Structure:**
- `MCP` (single module)
  - Depends on: Shared
  - Sub-namespaces:
    - `MCP.Protocol` (from MCPShared)
    - `MCP.Transport` (from MCPTransport)
    - `MCP.Server` (from MCPServer)

### **Cupertino Modules**

| Old Name | New Name | Dependencies (Old) | Dependencies (New) |
|----------|----------|-------------------|-------------------|
| CupertinoLogging | Logging | CupertinoShared | Shared |
| CupertinoShared | Shared | MCPShared | MCP |
| CupertinoCore | Core | CupertinoShared, CupertinoLogging, CupertinoResources | Shared, Logging, Resources |
| CupertinoSearch | Search | CupertinoShared, CupertinoLogging | Shared, Logging |
| CupertinoResources | Resources | None | None |
| CupertinoMCPSupport | MCPSupport | MCPServer, MCPShared, CupertinoShared, CupertinoLogging | MCP, Shared, Logging |
| CupertinoSearchToolProvider | SearchToolProvider | MCPServer, MCPShared, CupertinoSearch | MCP, Search |
| CupertinoCLI | CLI | CupertinoShared, CupertinoCore, CupertinoSearch, CupertinoLogging | Shared, Core, Search, Logging, MCP, MCPSupport, SearchToolProvider |

---

## 📝 **API Changes**

### **Import Changes**

```swift
// BEFORE
import CupertinoLogging
import CupertinoShared
import CupertinoCore
import CupertinoSearch
import MCPServer
import MCPTransport
import MCPShared

// AFTER
import Logging
import Shared
import Core
import Search
import MCP
```

### **Type Reference Changes**

#### **Logging Module**

```swift
// BEFORE
CupertinoLogger.crawler
CupertinoLogger.evolution
CupertinoLogger.search
CupertinoLogger.mcp

// AFTER
Logging.Logger.crawler
Logging.Logger.evolution
Logging.Logger.search
Logging.Logger.mcp
```

#### **Shared Module**

```swift
// BEFORE
CupertinoConfiguration
CupertinoConstants.App.commandName
CupertinoConstants.Directory.docs
DocumentationPage
CrawlMetadata
PageMetadata

// AFTER
Shared.Configuration
Shared.Constants.App.commandName
Shared.Constants.Directory.docs
Shared.DocumentationPage
Shared.CrawlMetadata
Shared.PageMetadata
```

#### **Core Module**

```swift
// BEFORE
DocumentationCrawler(configuration: ...)
CrawlerState
SwiftEvolutionCrawler
PackageFetcher

// AFTER
Core.Crawler(configuration: ...)
Core.CrawlerState
Core.EvolutionCrawler
Core.PackageFetcher
```

#### **Search Module**

```swift
// BEFORE
SearchIndex(dbPath: ...)
SearchResult
SampleCodeSearchResult
SearchIndexBuilder

// AFTER
Search.Index(dbPath: ...)
Search.Result
Search.SampleCodeResult
Search.IndexBuilder
```

#### **MCP Module**

```swift
// BEFORE
import MCPServer
import MCPTransport
import MCPShared

let server = MCPServer(name: "...", version: "...")
let transport = StdioTransport()
let request = InitializeRequest(...)

// AFTER
import MCP

let server = MCP.Server(name: "...", version: "...")
let transport = MCP.Transport.Stdio()
let request = MCP.Protocol.InitializeRequest(...)
```

---

## 🗂️ **File Structure Changes**

### **Before**

```
Packages/Sources/
├── MCPShared/
├── MCPTransport/
├── MCPServer/
├── CupertinoLogging/
├── CupertinoShared/
├── CupertinoCore/
├── CupertinoSearch/
├── CupertinoResources/
├── CupertinoMCPSupport/
├── CupertinoSearchToolProvider/
├── CupertinoCLI/
└── CupertinoMCP/
```

### **After**

```
Packages/Sources/
├── MCP/
│   ├── MCP.swift              # Namespace root
│   ├── Protocol/              # From MCPShared
│   ├── Transport/             # From MCPTransport
│   └── Server/                # From MCPServer
├── Logging/
│   ├── Logging.swift          # Namespace root
│   └── Logger.swift
├── Shared/
│   ├── Shared.swift           # Namespace root
│   ├── Configuration.swift
│   ├── Constants.swift
│   └── Models.swift
├── Core/
│   ├── Core.swift             # Namespace root
│   ├── Crawler.swift
│   ├── CrawlerState.swift
│   ├── EvolutionCrawler.swift
│   └── PackageFetcher.swift
├── Search/
│   ├── Search.swift           # Namespace root
│   ├── Index.swift
│   ├── IndexBuilder.swift
│   └── Result.swift
├── Resources/
│   └── Resources/
├── MCPSupport/
│   └── (MCP integration)
├── SearchToolProvider/
│   └── (Search MCP tools)
└── CLI/
    ├── CLI.swift
    └── Commands/
        ├── MCP/
        ├── Data/
        ├── DB/
        ├── Config/
        └── Utilities/
```

---

## 🚀 **Implementation Phases**

### **Phase 0: Preparation** ✅ CURRENT
- [x] Document current state
- [x] Create refactoring plan
- [ ] Create backup branch
- [ ] Run full test suite (baseline)

### **Phase 1: Rename & Namespace** (Days 2-4)
- [ ] Rename package directories
- [ ] Update Package.swift
- [ ] Add namespace enums
- [ ] Test compilation

### **Phase 2: Migrate Types** (Days 5-8)
- [ ] Migrate Logging types
- [ ] Migrate Shared types
- [ ] Migrate Core types
- [ ] Migrate Search types
- [ ] Consolidate MCP types
- [ ] Update all imports

### **Phase 3: Commands** (Days 9-12)
- [ ] Create command structure
- [ ] Implement MCP commands
- [ ] Implement Data commands
- [ ] Implement DB commands
- [ ] Implement Config commands
- [ ] Implement Utility commands

### **Phase 4: Entry Point** (Day 13)
- [ ] Update CLI.swift
- [ ] Register all commands
- [ ] Test help output

### **Phase 5: Tests** (Days 14-16)
- [ ] Update test imports
- [ ] Update test assertions
- [ ] Run full test suite
- [ ] Fix failing tests

### **Phase 6: Documentation** (Days 17-18)
- [ ] Update README
- [ ] Create migration guide
- [ ] Update command docs
- [ ] Update API docs

### **Phase 7: Testing** (Days 19-20)
- [ ] Integration testing
- [ ] Real workflow testing
- [ ] Performance testing
- [ ] Lint & format

### **Phase 8: Release** (Day 21)
- [ ] Version bump
- [ ] Changelog
- [ ] Git tag
- [ ] Release notes

---

## 🧪 **Testing Strategy**

### **Unit Tests**
- All existing tests must pass with new namespaces
- Test each module independently

### **Integration Tests**
- Full crawl → fetch → index → serve workflow
- Command execution tests
- MCP server connectivity tests

### **Regression Tests**
- Compare output with v0.1.5
- Ensure no functionality lost
- Verify resume capability

### **Performance Tests**
- Build time comparison
- Runtime performance comparison
- Memory usage comparison

---

## 🔙 **Rollback Plan**

### **Git Strategy**
```bash
# Create backup branch before starting
git checkout -b backup/pre-v0.2-refactor

# Create feature branch for work
git checkout -b feature/v0.2-refactor

# If rollback needed
git checkout main
git merge backup/pre-v0.2-refactor
```

### **Rollback Triggers**
- Tests fail after 3 attempts to fix
- Performance degradation >20%
- Build time increase >50%
- Critical bugs discovered

---

## ✅ **Success Criteria**

- [ ] All packages renamed and namespaced
- [ ] All commands working with new structure
- [ ] All tests passing (100%)
- [ ] No lint violations
- [ ] Documentation complete
- [ ] Migration guide ready
- [ ] Performance maintained or improved
- [ ] Build time ≤ current + 10%

---

## 📊 **Progress Tracking**

**Current Phase:** Phase 0 (Preparation)
**Completion:** 10%
**Blockers:** None
**Risks:** Breaking changes require careful migration

---

**Last Updated:** 2025-11-18
**Next Review:** Start of each phase

# Binary & Command Renaming Strategy

**Version:** 1.0
**Last Updated:** 2025-11-18
**Current Version:** 0.1.5
**Target Version:** 0.2.0 (Breaking Changes)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State](#current-state)
3. [Strategic Vision](#strategic-vision)
4. [Proposed Renaming](#proposed-renaming)
5. [Implementation Plan](#implementation-plan)
6. [Migration Guide](#migration-guide)

---

## Executive Summary

### The Problem

Current naming reflects development priorities, not user priorities:
- **`cupertino`** = Data management tools (crawl, fetch, index)
- **`cupertino-mcp`** = MCP server (the actual product)

### The Vision

Users should interact primarily with the MCP server, with all data pre-embedded in a SQLite database. Data management tools are for maintainers only.

### The Solution

**Flip the naming to reflect user priorities:**
- **`cupertino`** = MCP server (main product, what users install)
- **`cupertino-tools`** = Data management (optional, for maintainers)

---

## Current State

### Binary Inventory

| Binary | Purpose | Target Users | Install Priority |
|--------|---------|--------------|------------------|
| `cupertino` | Data management (crawl/fetch/index) | Developers, maintainers | Primary |
| `cupertino-mcp` | MCP server for Claude | End users | Secondary |

### Current User Workflow

```bash
# Step 1: Install both binaries
brew install cupertino
brew install cupertino-mcp

# Step 2: Build database (complex, time-consuming)
cupertino fetch --type all
cupertino fetch --type packages
cupertino fetch --type code
cupertino save

# Step 3: Finally use the product
cupertino-mcp serve
```

**Problem:** Multi-step setup, two binaries, unclear which is "the product"

---

## Strategic Vision

### Target Architecture

**Embedded Database Distribution:**
- All documentation data pre-indexed in SQLite database
- Database embedded in `cupertino` binary (or separate download)
- Users run `cupertino` → MCP server starts → Data ready immediately

### Target User Workflow

```bash
# Install
brew install cupertino

# Run (that's it!)
cupertino

# MCP server starts with pre-embedded database
# No crawling, no fetching, no indexing needed
```

### Target User Personas

**Primary Users (95%):** Claude/MCP users
- Want: Documentation access via MCP
- Don't want: Complex setup, database building
- Interaction: `cupertino` (that's it)

**Secondary Users (5%):** Maintainers, contributors
- Want: Update documentation, rebuild database
- Don't mind: Complex tooling, multi-step processes
- Interaction: `cupertino-tools` commands

---

## Proposed Renaming

### Option 1: cupertino + cupertino-tools (Recommended)

| New Name | Old Name | Purpose | Users |
|----------|----------|---------|-------|
| **`cupertino`** | `cupertino-mcp` | MCP server with embedded database | 95% (end users) |
| **`cupertino-tools`** | `cupertino` | Data management (crawl/fetch/index) | 5% (maintainers) |

**Rationale:**
- Clear: "tools" signals optional, advanced functionality
- Familiar pattern: `docker` vs `docker-compose`, `git` vs `git-lfs`
- Not too specialized: Works for both developers and admins

---

### Option 2: cupertino + cupertino-dev

| New Name | Old Name | Purpose |
|----------|----------|---------|
| **`cupertino`** | `cupertino-mcp` | MCP server |
| **`cupertino-dev`** | `cupertino` | Development tools |

**Rationale:**
- Signals "development/maintenance" tools
- Shorter than "tools"
- Pattern: `npm run dev`, `vite dev`

---

### Option 3: cupertino + cupertino-admin

| New Name | Old Name | Purpose |
|----------|----------|---------|
| **`cupertino`** | `cupertino-mcp` | MCP server |
| **`cupertino-admin`** | `cupertino` | Admin tools |

**Rationale:**
- Clearly for administration/maintenance
- Implies elevated/special purpose
- Pattern: `postgres` vs `postgres-admin`

---

### Option 4: cupertino + cupertino-build

| New Name | Old Name | Purpose |
|----------|----------|---------|
| **`cupertino`** | `cupertino-mcp` | MCP server |
| **`cupertino-build`** | `cupertino` | Build tools |

**Rationale:**
- Emphasizes "building" the database
- Clear purpose: construction/generation
- Pattern: `docker build`, `npm run build`

---

### Recommendation: Option 1 (`cupertino-tools`)

**Why:**
1. ✅ Not too specialized (works for dev, admin, build use cases)
2. ✅ Clear signal: optional, advanced functionality
3. ✅ Common pattern in CLI ecosystems
4. ✅ Future-proof: Can add more tools without rename

---

## Command Renaming Strategy

### Current Command Structure

**`cupertino` binary:**
```
cupertino [default: crawl]
├── crawl   - Crawl documentation
├── fetch   - Fetch resources
└── index   - Build search index
```

**`cupertino-mcp` binary:**
```
cupertino-mcp [default: serve]
└── serve   - Start MCP server
```

---

### Proposed Command Structure

**`cupertino` binary (new main):**
```
cupertino [default: serve]
└── serve   - Start MCP server with embedded database
```

**`cupertino-tools` binary (new tools):**
```
cupertino-tools [no default - must specify]
├── crawl          - Crawl documentation
├── fetch          - Fetch resources
├── index          - Build search index
├── build          - Build complete database (crawl + fetch + index)
├── update         - Update existing database
├── update-catalogs - Update embedded catalogs
├── validate       - Validate database integrity
└── export         - Export database for distribution
```

---

### Command Naming Considerations

#### Keep Internal Names?

**Option A: Keep exact names internally**
- `crawl`, `fetch`, `index` stay as-is
- Only binary name changes
- Minimal code changes

**Option B: Rename commands to reflect new context**
- `crawl` → `cupertino-tools crawl` (same name, different context)
- `fetch` → `cupertino-tools fetch` (same name, different context)
- `index` → `cupertino-tools build-index` (more descriptive)

**Recommendation: Option A**
- Less breaking change
- Internal command names can stay the same
- Binary prefix provides context

---

### New Commands for `cupertino-tools`

#### 1. `build` - Complete Database Build

**Purpose:** One command to build entire database

**Current workflow:**
```bash
cupertino fetch --type all
cupertino fetch --type packages
cupertino fetch --type code
cupertino save
```

**New workflow:**
```bash
cupertino-tools build --all
```

**Implementation:**
- Runs crawl + fetch + index in sequence
- Progress reporting
- Error handling and resume capability
- Outputs: Complete `cupertino.db` (SQLite)

---

#### 2. `update` - Incremental Update

**Purpose:** Update existing database with new data

```bash
# Update specific type
cupertino-tools update --type docs

# Update everything
cupertino-tools update --all

# Check what would be updated
cupertino-tools update --dry-run
```

**Implementation:**
- Downloads only changed documentation
- Incremental index updates
- Preserves existing data

---

#### 3. `update-catalogs` - Refresh Embedded Catalogs

**Purpose:** Update embedded resource catalogs (TODO #7)

```bash
cupertino-tools update-catalogs
```

**Outputs:**
- `sample-code-catalog.json`
- `swift-packages-catalog.json`
- `priority-packages.json`

---

#### 4. `validate` - Database Health Check

**Purpose:** Verify database integrity

```bash
cupertino-tools validate

# Output:
✅ Database file: cupertino.db (512 MB)
✅ Schema version: 1.0
✅ Documents: 10,234
✅ Frameworks: 156
✅ Search index: healthy
✅ Checksums: valid
```

---

#### 5. `export` - Prepare Database for Distribution

**Purpose:** Package database for embedding in binary

```bash
cupertino-tools export --output cupertino-data.db --compress
```

**Features:**
- Optimizes database (VACUUM)
- Optional compression
- Generates checksums
- Creates metadata file

---

## Implementation Plan

### Phase 1: Preparation (v0.2.0-alpha)

**Goals:**
- Create `cupertino-tools` binary (copy of current `cupertino`)
- Keep both binaries working
- Add deprecation warnings

**Changes:**
```swift
// In old cupertino binary
print("⚠️  Warning: 'cupertino' will be renamed to 'cupertino-tools' in v0.2.0")
print("   The new 'cupertino' will be the MCP server")
print("   Update your scripts accordingly")
```

**Testing:**
- Verify both binaries work
- Update CI/CD for both
- Beta testing period: 2-4 weeks

---

### Phase 2: Transition (v0.2.0-beta)

**Goals:**
- Swap binary purposes
- Maintain backward compatibility
- Update documentation

**Changes:**
1. Rename `cupertino-mcp` → `cupertino`
2. Rename `cupertino` → `cupertino-tools`
3. Keep old names as symlinks/aliases (deprecated)

**Compatibility:**
```bash
# Old commands still work (with warning)
cupertino fetch          # → shows deprecation, runs cupertino-tools crawl
cupertino-mcp serve      # → shows deprecation, runs cupertino serve
```

**Documentation:**
- Migration guide
- Breaking changes announcement
- Updated README and docs

---

### Phase 3: Finalization (v0.2.0)

**Goals:**
- Official release with new names
- Remove deprecated aliases (or keep for one more version)

**Release notes:**
```markdown
## Breaking Changes in v0.2.0

### Binary Renaming

**Old → New:**
- `cupertino` → `cupertino-tools` (data management)
- `cupertino-mcp` → `cupertino` (main binary)

**Migration:**
Replace in your scripts:
- `cupertino fetch` → `cupertino-tools crawl`
- `cupertino fetch` → `cupertino-tools fetch`
- `cupertino save` → `cupertino-tools index`
- `cupertino-mcp serve` → `cupertino serve`

**Why?**
- Cupertino is now primarily an MCP server with embedded data
- Tools are for maintainers rebuilding the database
- Simpler user experience: just run `cupertino`
```

---

### Phase 4: Distribution (v0.3.0)

**Goals:**
- Distribute with embedded database
- Most users never need `cupertino-tools`

**Installation:**
```bash
# Primary installation (includes database)
brew install cupertino

# Optional: tools for maintainers
brew install cupertino-tools
```

**First-run experience:**
```bash
$ cupertino
🚀 Cupertino MCP Server v0.3.0

✅ Embedded database loaded (512 MB, 10,234 documents)
✅ Search index ready (156 frameworks)
📚 Documentation: developer.apple.com/documentation
🔍 Search: Available
🎯 Waiting for MCP client connection...
```

---

## Migration Guide

### For End Users (95%)

**If you only use the MCP server:**

**Old workflow (v0.1.x):**
```bash
brew install cupertino-mcp
cupertino-mcp serve
```

**New workflow (v0.2.0+):**
```bash
brew install cupertino
cupertino
```

**That's it!** Database is pre-embedded.

---

### For Maintainers (5%)

**If you rebuild the database:**

**Old workflow (v0.1.x):**
```bash
cupertino fetch --type all
cupertino fetch --type packages
cupertino save
cupertino-mcp serve
```

**New workflow (v0.2.0+):**
```bash
cupertino-tools build --all
cupertino
```

---

### For CI/CD Pipelines

**Database building pipeline:**

```yaml
# Old (.github/workflows/build-database.yml)
- name: Crawl documentation
  run: cupertino fetch --type all

- name: Fetch resources
  run: cupertino fetch --type packages

- name: Build index
  run: cupertino save

# New (.github/workflows/build-database.yml)
- name: Build database
  run: cupertino-tools build --all

- name: Export for distribution
  run: cupertino-tools export --output cupertino-data.db
```

---

### For Package Managers

**Homebrew formula changes:**

```ruby
# Old: Two separate formulas
class Cupertino < Formula
  desc "Apple documentation crawler and indexer"
  # ...
end

class CupertinoMcp < Formula
  desc "MCP server for Apple documentation"
  # ...
end

# New: Swap purposes
class Cupertino < Formula
  desc "MCP server for Apple documentation with embedded database"
  homepage "https://github.com/user/cupertino"
  # Includes embedded database
  # Main user-facing product
end

class CupertinoTools < Formula
  desc "Developer tools for building Cupertino database"
  homepage "https://github.com/user/cupertino"
  # Optional install
  # For maintainers only
end
```

---

## Impact Analysis

### Breaking Changes

**High Impact:**
- ❌ Binary names change
- ❌ Scripts must be updated
- ❌ CI/CD pipelines must be updated

**Mitigation:**
- Deprecation warnings in v0.1.x
- Compatibility aliases in v0.2.0-beta
- Clear migration guide
- Automated migration script

---

### Benefits

**User Experience:**
- ✅ Simple: `brew install cupertino` + `cupertino` = done
- ✅ Clear purpose: Cupertino = MCP server
- ✅ No multi-step setup for end users
- ✅ Database pre-embedded

**Architecture:**
- ✅ Better separation: product vs tooling
- ✅ Clearer naming reflects actual priorities
- ✅ Easier to distribute and install
- ✅ Scalable for future features

**Maintenance:**
- ✅ Binary distribution simpler (database included)
- ✅ Tools isolated for developer use
- ✅ Can update tooling without affecting users

---

## Open Questions

### 1. Database Size & Distribution

**Question:** Should embedded database be:
- **Option A:** Bundled in binary (larger download, works offline)
- **Option B:** Downloaded on first run (smaller binary, needs internet)
- **Option C:** Separate download (flexible, manual step)

**Recommendation:** Option A (bundled) for best UX

---

### 2. Update Strategy

**Question:** How should users update database?

**Options:**
- **Auto-update:** `cupertino` checks for updates, downloads automatically
- **Manual update:** User runs `cupertino update` to refresh
- **App store model:** Binary updates include database updates

**Recommendation:** App store model - binary releases include updated database

---

### 3. Backward Compatibility Duration

**Question:** How long to maintain old binary names?

**Options:**
- **0 releases:** Hard break in v0.2.0
- **1 release:** Deprecated in v0.2.0, removed in v0.3.0
- **2 releases:** Deprecated in v0.2.0, removed in v0.4.0

**Recommendation:** 1 release (remove in v0.3.0)

---

### 4. Tool Names

**Question:** Which name for the tools binary?

**Options ranked:**
1. ✅ **`cupertino-tools`** (recommended - clear, flexible)
2. ✅ **`cupertino-dev`** (shorter, implies development)
3. ⚠️ **`cupertino-admin`** (implies admin-only)
4. ⚠️ **`cupertino-build`** (too specific)

**Recommendation:** `cupertino-tools`

---

## Success Criteria

### v0.2.0 Release Goals

**Must Have:**
- [ ] Binary names swapped
- [ ] Both binaries functional
- [ ] Migration guide published
- [ ] Breaking changes documented

**Should Have:**
- [ ] Deprecation warnings in place
- [ ] Automated migration script
- [ ] Updated homebrew formulas
- [ ] CI/CD pipelines updated

**Nice to Have:**
- [ ] Embedded database in `cupertino`
- [ ] New `cupertino-tools build` command
- [ ] Database export functionality

---

### v0.3.0 Release Goals

**Must Have:**
- [ ] Embedded database distributed
- [ ] Old binary names removed (or deprecated)
- [ ] Full documentation updates
- [ ] User testimonials (smooth migration)

---

## Timeline

### Proposed Schedule

| Phase | Version | Timeline | Status |
|-------|---------|----------|--------|
| **Planning** | — | Week 1-2 | ← Current |
| **Alpha** | v0.2.0-alpha | Week 3-4 | Upcoming |
| **Beta** | v0.2.0-beta | Week 5-6 | Upcoming |
| **Release** | v0.2.0 | Week 7 | Upcoming |
| **Distribution** | v0.3.0 | Week 10 | Future |

---

## Next Steps

1. ✅ **Approve naming strategy** (`cupertino` + `cupertino-tools`)
2. ⏳ **Create database export functionality**
3. ⏳ **Build embedded database distribution**
4. ⏳ **Update package manager formulas**
5. ⏳ **Write migration scripts**
6. ⏳ **Update all documentation**
7. ⏳ **Release v0.2.0-alpha** for testing

---

## Summary

### Current State
- `cupertino` = data tools (wrong priority)
- `cupertino-mcp` = MCP server (main product)

### Future State
- `cupertino` = MCP server (main product) ✅
- `cupertino-tools` = data tools (optional) ✅

### Benefits
- Simpler user experience
- Clearer naming reflects priorities
- Pre-embedded database
- Optional tooling for maintainers

### Migration
- Phased approach over 2-3 releases
- Deprecation warnings
- Clear migration guide
- Backward compatibility period

---

**Document Version:** 1.0
**Created:** 2025-11-18
**Author:** Claude (Anthropic)
**Project:** Cupertino - Apple Documentation CLI & MCP Server
**Decision Required:** Approve naming strategy before implementation

# Cupertino - TODO List

*Last updated: 2024-11-16*
*Current crawl status: 19,970 pages (114 MB) - Evaluating depth strategy*

---

## Actually Do Next

### 0. Immediate

#### 0.1 ✅ Make a list of found bugs
- Created BUGS.md with 20 bugs categorized by priority
- 5 Critical (P0), 5 High (P1), 7 Medium (P2), 3 Low (P3)

#### 0.2 Make tests for found bugs
- [ ] Write tests for P0 Critical bugs (5 tests)
  - [ ] Test #1: Resume detection with file paths
  - [ ] Test #2: MCP server stdin blocking
  - [ ] Test #3: Page load timeout handling
  - [ ] Test #4: WKWebView error continuation resume
  - [ ] Test #5: SearchError enum existence
- [ ] Write tests for P1 High Priority bugs (5 tests)
  - [ ] Test #6: Database connection cleanup
  - [ ] Test #7: Auto-save error handling
  - [ ] Test #8: Queue deduplication
  - [ ] Test #9: GitHub API call count
  - [ ] Test #10: Network retry logic
- [ ] Write tests for P2 Medium Priority bugs (7 tests)
- [ ] Write tests for P3 Low Priority issues (3 tests)
    

### 1. **IMMEDIATE: Decide on Crawl Depth Strategy**
   - Currently have 19,970 markdown files (114 MB) in docs/
   - Console shows: Page 11,584, but actual files are 19,970 (metadata tracking behind)
   - Crawl is still running (started Nov 15, 2024 ~7:58 PM)
   - **Decision needed:**
     - [ ] Option A: Stop now at 19,970 files (recommended)
     - [ ] Option B: Let run overnight for deeper depth 4 analysis (~27K files)
     - [ ] Option C: Continue to 150K limit (not recommended - 9 days, mostly duplicates)
   - **Action after decision:**
     - [ ] Stop crawler if stopping
     - [ ] Analyze actual depth distribution from crawled files
     - [ ] Make evidence-based recommendation on depth value

### 2. **Process Package Documentation**
   - We have gathered data for packages from GitHub, but not yet added package documentation
   - **Curation requirements:**
     - [ ] I am the curator of final packages for inclusion
     - [x] Apple packages automatically included (with dependencies)
     - [ ] Exclude deprecated packages (AFNetworking, RxSwift, etc.) - don't pollute docs
     - [ ] Include current swift-on-the-server packages (Vapor, Hummingbird)
     - [ ] Ignore "hip" or "trendy" packages - we're not into trends
   - **Related:** See Phase 3 below for detailed implementation plan

### 3. **Check Platform Dependencies**
   - [ ] Add `#if` checks and `canImport` guards for cross-platform builds
   - [ ] Enable building on Linux
   - [ ] Disable platform-specific commands (e.g., PDF export on Linux - requires AppKit)

### 4. **Build Search Index** (After crawl decision)
   - [ ] Rebuild search index with all downloaded documentation
   ```bash
   cupertino build-index \
     --docs-dir /Volumes/Code/DeveloperExt/private/cupertino/docs \
     --evolution-dir /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution \
     --search-db /Volumes/Code/DeveloperExt/private/cupertino/search.db
   ```
   - [ ] Test MCP server with full index
   - [ ] Verify performance with actual dataset

---

## Hardcoded Directory Structure

**IMPORTANT: All paths are hardcoded to ensure consistency**

```
/Volumes/Code/DeveloperExt/private/cupertino/
├── docs/                    # Crawled Apple documentation (markdown)
├── swift-evolution/         # Swift Evolution proposals (markdown)
├── sample-code/            # Sample code .zip files (607 samples)
└── search.db               # SQLite FTS5 search index
```

**What's in each folder:**
- `docs/`: 19,970 markdown files organized by framework (114 MB) ← UPDATED
- `swift-evolution/`: 429 proposal markdown files (8.2 MB)
- `sample-code/`: 607 .zip files (26 GB total)
- `search.db`: SQLite database with FTS5 search index (~100 MB when fully indexed)

---

## Current Status

**In Progress:**
- ⏳ **Documentation Crawl** - Currently at 19,970 files (114 MB) - Evaluating depth strategy
  - Started: Nov 15, 2024 ~7:58 PM
  - Current console: Page 11,584 (metadata behind actual file count)
  - Location: /Volumes/Code/DeveloperExt/appledocsucker/docs/
  - Frameworks: 259 frameworks covered
  - Top frameworks: SwiftUI (5,852), Swift (2,814), UIKit (1,567), Foundation (1,016)
  - Status: Running, evaluating whether to continue or stop for depth analysis
  - Note: Metadata tracking is behind actual crawl by ~8,000 files

**Completed:**
- ✅ CLI crawler with resume capability
- ✅ HTML to Markdown conversion  
- ✅ SQLite FTS5 search indexing
- ✅ MCP server for AI agents
- ✅ Homebrew installation
- ✅ Swift Evolution proposal indexing (429 proposals)
- ✅ Sample code download (607 projects, 26GB)
- ✅ Sample README verification (100% have README.md)
- ✅ SwiftLint compliance
- ✅ os.log logging implementation
- ✅ Directory structure documentation (hardcoded paths)
- ✅ Incremental update/refresh capability (`cupertino update` command)

---

## Phase 1: Finalize Documentation Crawl

**Priority: IMMEDIATE**

**Current Decision Point:**
- [x] Crawl started and running
- [ ] **DECIDE:** Stop at 19,970 pages or continue?
  - Analysis shows 19,970 files is 70% more than estimated "complete depth 3"
  - Continuing to 150K would add 9 days for mostly duplicate content
  - Recommendation: Stop now or run overnight for depth 4 sample analysis

**After decision:**
- [ ] Stop crawler if stopping (find process, kill it)
- [ ] Analyze actual depth distribution from crawled markdown files
- [ ] Count files by depth from file paths/names
- [ ] Sample depth 4 content quality (duplicates vs genuinely new)
- [ ] Make final evidence-based recommendation
- [ ] Build search index with finalized dataset
- [ ] Verify search performance
- [ ] Test MCP server
- [ ] Document crawl metadata (dates, pages, frameworks, depth distribution)

**Estimated Time:** Decision + analysis (1-2 hours) + indexing (1 hour)

---

## Phase 2: Sample Code Integration

**Priority: HIGH**
**Estimated Time:** 6-8 hours

### Implementation Strategy - HYBRID APPROACH
- Index README content only (<1 GB in database)
- Store Apple docs URLs + GitHub URLs in database
- **Keep existing .zip files** (cannot re-download without Apple ID login)
- Track local availability vs manual download needed

### Tasks:
- [ ] Add `samples` table to search.db
- [ ] Add `samples_fts` virtual table for full-text search
- [ ] Create `SampleMetadataExtractor.swift`
- [ ] Parse 607 sample .zip filenames to extract metadata
- [ ] For each sample:
  - [ ] Extract README.md only (using `unzip -p`)
  - [ ] Index full README content for FTS5
  - [ ] Parse first paragraph as description
  - [ ] Construct Apple docs URL
  - [ ] Extract GitHub links from README
  - [ ] Mark as `locally_available: true`
- [ ] Add MCP tools:
  - [ ] `search_samples` - Search by framework/title/content
  - [ ] `get_sample_info` - Get metadata and README
  - [ ] `extract_sample` - Extract specific files from .zip (optional)

---

## Phase 3: Third-Party Package Documentation

**Priority: HIGH**
**Estimated Time:** 12-15 hours

### Curation Strategy (from "Actually Do Next"):
- **Automatic inclusion:** All Apple packages + their dependencies
- **Manual curation required:** Review Tier 2 packages for relevance
- **Exclusion criteria:**
  - Deprecated packages (AFNetworking, RxSwift, PromiseKit, SwiftyJSON)
  - "Hip" or "trendy" packages (we're not into trends)
- **Inclusion criteria:**
  - Active maintenance (commits in last 6 months)
  - Modern Swift (5.5+ features)
  - Fills gaps not in stdlib/Foundation
  - Actually used in production
  - Swift-on-the-server: Vapor, Hummingbird (mandatory)

### Tasks:
- [ ] Run package analysis script
- [ ] Create curated `tier2-packages.json` with rationale
- [ ] Add `packages` table to search.db
- [ ] Add `package_dependencies` table
- [ ] Create `PackageDocsCrawler.swift`
- [ ] Implement `crawl-package` command
- [ ] Support DocC archives
- [ ] Support custom doc sites (Vapor, Hummingbird)
- [ ] Fallback to README parsing
- [ ] Add MCP integration for package search

---

## Phase 4: Cross-Platform Support

**Priority: HIGH** (from "Actually Do Next")
**Estimated Time:** 3-4 hours

- [ ] Add `#if canImport()` checks for platform-specific code
- [ ] Identify AppKit dependencies (PDF export, etc.)
- [ ] Add conditional compilation for Linux builds
- [ ] Disable unavailable commands on non-macOS platforms
- [ ] Test build on Linux
- [ ] Update documentation with platform requirements

---

## Phase 5: API-Level Granular Indexing

**Priority: MEDIUM**
**Estimated Time:** 6-8 hours

- [ ] Design API element extraction parser
- [ ] Add `api_elements` table to search.db
- [ ] Add `api_elements_fts` virtual table
- [ ] Parse markdown code blocks for API definitions
- [ ] Extract classes, structs, enums, protocols, methods, properties
- [ ] Index ~678K API elements (similar to Dash)
- [ ] Add `search_api` MCP tool

---

## Phase 6: Historical Delta Tracking

**Priority: MEDIUM**
**Estimated Time:** 6-9 hours

**Note:** Basic refresh works via `cupertino update`. This adds historical tracking.

- [ ] Create `CrawlSnapshot` struct
- [ ] Implement snapshot generation
- [ ] Add `crawl_history` table
- [ ] Store crawl dates (started_at, completed_at)
- [ ] Add `cupertino check` command (fast check mode, no delays)
- [ ] Add `cupertino compare` command (delta calculation)
- [ ] Add `get_documentation_changes` MCP tool

---

## Phase 7: Native macOS GUI

**Priority: MEDIUM**
**Estimated Time:** 6-8 hours

- [ ] Create CupertinoGUI SwiftUI app target
- [ ] Implement CrawlerView with live progress
- [ ] Implement SearchView
- [ ] Implement StatsView
- [ ] Add preferences panel
- [ ] Create .dmg installer

---

## Consider for Later

- [ ] Localization (extract messages/strings)
- [ ] Web interface (alternative to native GUI)
- [ ] VS Code extension
- [ ] Xcode source editor extension
- [ ] Integration with Dash (docset export)
- [ ] GitHub Actions for automated daily checks
- [ ] Docker container

---

## Maybe / Probably Not

- [ ] Abstract out SampleCodeDownloader & SwiftEvolutionCrawler
- [ ] Add ability to create other downloaders/crawlers
- [ ] RSS feed for documentation changes
- [ ] Email digest
- [ ] Browser extension

---

## Known Issues / Tech Debt

- [ ] **Swift Evolution proposal listing bug** - CupertinoResourceProvider.swift:51 looks for `hasPrefix("SE-")` but actual files are `0001-*.md` (without "SE-" prefix). MCP resource listing returns zero proposals. Fix: Remove "SE-" prefix check.
- [ ] Metadata tracking falls behind actual crawl (8K file discrepancy currently)
- [ ] SwiftLint type_body_length warning in HTMLToMarkdown.swift (disabled)
- [ ] No retry logic for failed HTTP requests
- [ ] Progress persistence for interrupted crawls is basic

---

## Time Budget Summary

| Phase | Estimated Time | Priority |
|-------|---------------|----------|
| Phase 1: Finalize Crawl | 2-3 hours | IMMEDIATE |
| Phase 2: Sample Code | 6-8 hours | HIGH |
| Phase 3: Package Docs | 12-15 hours | HIGH |
| Phase 4: Cross-Platform | 3-4 hours | HIGH |
| Phase 5: API Indexing | 6-8 hours | MEDIUM |
| Phase 6: Delta Tracking | 6-9 hours | MEDIUM |
| Phase 7: Native GUI | 6-8 hours | MEDIUM |
| **Total** | **~45-60 hours** | |

---

## Storage Requirements

**Current (with all sample .zips):**
```
Markdown files:      ~114 MB   ✅ KEEP
Search database:     ~100 MB   ✅ KEEP  
Sample code .zips:   ~27 GB    ✅ KEEP (can't re-download without Apple ID login)
Third-party pkgs:    ~5-10 GB  (future)

Total: ~32-37 GB
```

**Note:** Sample .zips cannot be deleted - downloads require manual Apple ID login

---

*Current focus: Evaluating crawl depth strategy (19,970 files @ 114 MB)*
*Decision needed: Stop now vs continue for depth 4 analysis*

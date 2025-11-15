# AppleDocsucker - TODO List

claude code --continue

## Hardcoded Directory Structure

**IMPORTANT: All paths are hardcoded to ensure consistency**

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── docs/                    # Crawled Apple documentation (markdown)
├── swift-evolution/         # Swift Evolution proposals (markdown)
├── sample-code/            # Sample code .zip files (607 samples)
└── search.db               # SQLite FTS5 search index
```

**Hardcoded paths used in code:**
- Base: `/Volumes/Code/DeveloperExt/appledocsucker`
- Docs: `/Volumes/Code/DeveloperExt/appledocsucker/docs`
- Evolution: `/Volumes/Code/DeveloperExt/appledocsucker/swift-evolution`
- Samples: `/Volumes/Code/DeveloperExt/appledocsucker/sample-code`
- Search DB: `/Volumes/Code/DeveloperExt/appledocsucker/search.db`

**What's in each folder:**
- `docs/`: ~10,099+ markdown files organized by framework (61 MB)
- `swift-evolution/`: 429 proposal markdown files (8.2 MB)
- `sample-code/`: 607 .zip files (26 GB total)
- `search.db`: SQLite database with FTS5 search index (~100 MB when fully indexed)

---

## Current Status

**In Progress:**
- ⏳ **Documentation Crawl** - Currently at ~8,421 pages (64.8% of ~13,000 total)
  - ETA: Tonight ~10 PM (Nov 15)
  - Command: `appledocsucker --start-url https://developer.apple.com/documentation/swift --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs --max-pages 150000 --force`

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

---

## Phase 1: Complete Current Crawl

**Priority: IMMEDIATE (waiting for completion)**

- [ ] Wait for crawl to complete (~13,000 pages)
- [ ] Rebuild search index with all downloaded documentation
  ```bash
  appledocsucker build-index \
    --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
    --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
    --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db
  ```
- [ ] Verify search index statistics
- [ ] Test MCP server with full index
- [ ] Create initial snapshot for delta tracking

**Estimated Time:** Wait time + 1 hour for indexing/verification

---

## Phase 2: Sample Code Integration

**Priority: HIGH**
**Reference:** `SAMPLE_CODE_PLAN.md` Phases 1-3
**Estimated Time:** 6-8 hours

### Phase 2a: Infrastructure (2-3 hours)
- [ ] Add `samples` table to `search.db`
  ```sql
  CREATE TABLE samples (
    slug TEXT PRIMARY KEY,
    framework TEXT,
    title TEXT,
    description TEXT,
    readme_content TEXT,
    zip_path TEXT,
    locally_available BOOLEAN DEFAULT 0,
    apple_docs_url TEXT,
    github_url TEXT,
    file_count INTEGER,
    related_docs TEXT,
    last_accessed INTEGER
  );
  ```
- [ ] Add `samples_fts` virtual table for full-text search
- [ ] Create `SampleMetadataExtractor.swift`

### Phase 2b: Extraction & Indexing - HYBRID APPROACH (2-3 hours)

**Strategy:** Index README content + URLs, keep .zip files locally

**IMPORTANT:**
- Sample code downloads require Apple ID login - cannot automate downloads!
- All 607 samples have README.md files (verified 100% coverage)
- Never extract or access .git folders (they stay in .zips)

**What we index for each sample:**
1. Metadata from filename (framework, title, slug)
2. Full README.md content (for FTS5 search)
3. Description (first paragraph of README)
4. Apple docs URL (where it would be downloaded)
5. GitHub URL (if sample is on GitHub)
6. Related documentation (links from README to our crawled docs)
7. Local availability (we have all 607 .zips)

**Implementation:**
- [ ] Parse sample .zip filenames to extract metadata (framework, title, slug)
- [ ] For each of the 607 samples in `sample-code/`:
  - [ ] Extract README.md only using `unzip -p` (no .git folders touched)
  - [ ] Parse first paragraph as description
  - [ ] Index full README content for FTS5 search
  - [ ] Construct Apple docs URL: `https://developer.apple.com/documentation/{framework}/{slug}`
  - [ ] Check README for GitHub links
  - [ ] Extract related doc links from README (references to Apple APIs)
  - [ ] Mark sample as `locally_available: true`
  - [ ] Store local zip_path
- [ ] Keep all existing .zip files (27 GB, cannot re-download without login)
- [ ] Never extract full contents or access .git folders

**Result:** <1 GB README index + 27 GB zips (no .git folders extracted)

### Phase 2c: GitHub URL Discovery (1-2 hours)
- [ ] For each sample README, extract GitHub links:
  - Parse README for `github.com` URLs
  - Common patterns: "Download from GitHub", "Source code available at"
  - Store GitHub URL if found
- [ ] For samples without GitHub links:
  - Try searching GitHub: `https://github.com/apple/{slug}`
  - Check if repo exists and is a sample code project
  - Store URL if valid match found
- [ ] Track URL availability:
  - `apple_docs_url`: Always construct (may require login to download)
  - `github_url`: Only if found in README or verified on GitHub
  - All 607 samples: `locally_available: true` (we have the .zips)

### Phase 2d: MCP Integration (1-2 hours)
- [ ] Add `search_samples` MCP tool:
  - Search by framework, title, or README content
  - Use FTS5 on `samples_fts` table
  - Return matching samples with metadata
- [ ] Add `get_sample_info` MCP tool returns:
  - Title, framework, slug
  - Description (first paragraph of README)
  - Full README content
  - Related documentation links
  - Download status: "Locally available" (all 607 are local)
  - Local .zip path: `/Volumes/Code/.../sample-code/{slug}.zip`
  - Apple docs URL: `https://developer.apple.com/documentation/{framework}/{slug}`
  - GitHub URL (if found): `https://github.com/apple/{repo}`
  - Note: "Apple download requires login. GitHub URL available for direct access (if listed)."
- [ ] Add `extract_sample` MCP tool (optional):
  - Extract specific files from local .zip (avoiding .git)
  - Return extracted content
  - Useful for agents that want to read source code
- [ ] Test with agent queries:
  - "Find SwiftUI samples about animations"
  - "Get README for blurring-an-image sample"
  - "Show me Core Data concurrency examples"

---

## Phase 3: Third-Party Package Documentation

**Priority: HIGH**
**Reference:** `SAMPLE_CODE_PLAN.md` Phase 7
**Estimated Time:** 12-15 hours

### Phase 3a: Research & Planning (2 hours)
- [ ] Run package analysis script:
  ```bash
  cd /Volumes/Code/DeveloperExt/appledocsucker
  mkdir -p scripts
  # Copy script from WARMUP.md
  chmod +x scripts/analyze-top-swift-packages.sh
  ./scripts/analyze-top-swift-packages.sh
  ```
- [ ] Review `top-swift-repos-YYYY-MM-DD.json` output
- [ ] Verify all Apple official packages are captured
- [ ] **MANUAL CURATION REQUIRED:** Review Tier 2 packages for modern relevance
  - ❌ **Exclude outdated packages** (even if high stars):
    - Alamofire (URLSession + async/await is sufficient now)
    - RxSwift (replaced by async/await)
    - PromiseKit (replaced by async/await)
    - SwiftyJSON (Codable is built-in)
  - ✅ **Include modern, actively maintained packages:**
    - Server-side: Vapor, Hummingbird
    - Architecture: TCA (Composable Architecture)
    - CLI: Swift Argument Parser (Apple)
    - Testing: Quick/Nimble (if still maintained)
    - UI utilities that add real value
  - **Criteria for inclusion:**
    1. Active maintenance (commits in last 6 months)
    2. Modern Swift (uses Swift 5.5+ features)
    3. Fills a gap not covered by stdlib/Foundation
    4. Actually used in production (check dependents on GitHub)
    5. Has good documentation to index
- [ ] Create curated `tier2-packages.json` with rationale for each
- [ ] Document why certain popular packages were excluded

### Phase 3b: Database Schema (1-2 hours)
- [ ] Add `packages` table to `search.db`
  ```sql
  CREATE TABLE packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    owner TEXT NOT NULL,
    repository_url TEXT NOT NULL,
    documentation_url TEXT,
    stars INTEGER,
    last_updated INTEGER,
    is_apple_official BOOLEAN DEFAULT 0,
    UNIQUE(owner, name)
  );
  ```
- [ ] Add `package_dependencies` table for dependency tracking
- [ ] Add `source_type` column to `docs_metadata`
- [ ] Add `package_id` foreign key to `docs_metadata`

### Phase 3c: Crawling Implementation (4-5 hours)
- [ ] Create `PackageDocsCrawler.swift`
- [ ] Implement `crawl-package` command
- [ ] Implement `crawl-packages --apple-official` (auto-fetch all Apple packages)
- [ ] Implement `crawl-packages --curated` (predefined Tier 2 list)
- [ ] Support DocC archives
- [ ] Support custom doc sites (Vapor, Hummingbird)
- [ ] Fallback to README parsing

### Phase 3d: Dependency Resolution (2-3 hours)
- [ ] Implement Package.swift parsing from GitHub
- [ ] Recursive dependency crawling (max depth: 2)
- [ ] De-duplication logic (skip already-indexed packages)
- [ ] Track relationships in `package_dependencies` table

### Phase 3e: MCP Integration (2-3 hours)
- [ ] Add `search_package_docs` MCP tool
- [ ] Update `search_docs` to include third-party results
- [ ] Implement clear source labeling:
  - "Apple Official" for apple/* packages
  - "Community Package: owner/repo" for others
- [ ] Add `used_by` field for dependency relationships
- [ ] Test with agent queries

---

## Phase 4: API-Level Granular Indexing

**Priority: MEDIUM**
**Reference:** `SAMPLE_CODE_PLAN.md` Phase 4
**Estimated Time:** 6-8 hours

- [ ] Design API element extraction parser
- [ ] Add `api_elements` table to `search.db`
  ```sql
  CREATE TABLE api_elements (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    parent TEXT,
    framework TEXT NOT NULL,
    language TEXT,
    signature TEXT,
    description TEXT,
    page_uri TEXT NOT NULL,
    FOREIGN KEY (page_uri) REFERENCES docs_metadata(uri)
  );
  ```
- [ ] Add `api_elements_fts` virtual table
- [ ] Parse markdown code blocks for API definitions
- [ ] Extract classes, structs, enums, protocols, methods, properties
- [ ] Index ~678K API elements (similar to Dash)
- [ ] Add `search_api` MCP tool
- [ ] Test with specific API queries

---

## Phase 5: Delta Tracking & Change Detection

**Priority: MEDIUM**
**Reference:** `SAMPLE_CODE_PLAN.md` Phase 6
**Estimated Time:** 5-7 hours

### Phase 5a: Snapshot Infrastructure (2-3 hours)
- [ ] Create `CrawlSnapshot` struct
- [ ] Implement snapshot generation in `SearchIndex`
- [ ] Add `--create-snapshot` flag to `build-index` command
- [ ] Add `crawl_history` table to track snapshots

### Phase 5b: Delta Calculation (2-3 hours)
- [ ] Create `appledocsucker compare` command
- [ ] Implement delta calculation (added/modified/removed)
- [ ] Generate delta JSON files
- [ ] Store in `/Volumes/Code/DeveloperExt/appledocsucker/deltas/`

### Phase 5c: MCP Integration (1 hour)
- [ ] Add `get_documentation_changes` MCP tool
- [ ] Support filtering by framework, date range
- [ ] Test change detection queries

---

## Phase 6: Native macOS GUI

**Priority: MEDIUM**
**Reference:** `GUI_PROPOSAL.md`
**Estimated Time:** 6-8 hours (realistic) / 40-60 hours (professional)

### Phase 6a: Basic GUI (2-4 hours)
- [ ] Create DocsuckerGUI SwiftUI app target
- [ ] Import existing packages (Core, Search)
- [ ] Implement CrawlerView with live progress
- [ ] Implement basic SearchView
- [ ] Implement StatsView with database info

### Phase 6b: Polish & Features (2-3 hours)
- [ ] Add preferences/settings panel
- [ ] Improve UI/UX layouts
- [ ] Add error handling
- [ ] Basic testing

### Phase 6c: CLI Integration (1-2 hours, optional)
- [ ] Create XPC service for bidirectional control
- [ ] Add `gui` subcommand to CLI
- [ ] Implement simple shared state file approach

### Phase 6d: Distribution (1 hour)
- [ ] Create .dmg installer
- [ ] Update documentation
- [ ] Test installation flow

---

## Phase 7: Documentation & Polish

**Priority: LOW**
**Estimated Time:** 3-4 hours

- [ ] Update README.md with full feature list
- [ ] Create user guide
- [ ] Add screenshots/demo video
- [ ] Document MCP tools for AI agents
- [ ] Create troubleshooting guide
- [ ] Write blog post / announcement

---

## Research Tasks

**Can be done while waiting for crawl:**

- [x] ~~Create package analysis script~~
- [ ] Run package analysis script to identify top Swift packages
- [ ] Review SwiftPackageIndex API for automation
- [ ] Investigate DocC archive format
- [ ] Test Vapor/Hummingbird doc crawling manually
- [ ] Benchmark search performance with full 13K docs
- [ ] Profile memory usage during indexing

---

## Future Ideas (Not Prioritized)

- [ ] Web interface (alternative to native GUI)
- [ ] VS Code extension for inline documentation
- [ ] Xcode source editor extension
- [ ] RSS feed for documentation changes
- [ ] Email digest of weekly changes
- [ ] Integration with Dash (export to docset format)
- [ ] GitHub Action for automated daily crawls
- [ ] Docker container for easy deployment
- [ ] API server (REST/GraphQL) for remote access
- [ ] Slack/Discord bot for documentation queries
- [ ] Browser extension for inline Apple doc links

---

## Storage & Cleanup

**IMPORTANT: Keep markdown files after indexing!**

The search database contains:
- ✅ FTS5 search index (for finding documents)
- ✅ Metadata (hashes, dates, word counts)
- ❌ **NOT the full markdown content**

**You NEED the markdown files for:**
1. MCP `get_doc_content` tool (agents read actual files)
2. Delta detection (compare new vs old content)
3. Re-indexing without re-crawling
4. Future exports (PDF, HTML, etc.)

**Storage breakdown (with Hybrid Sample Approach):**
```
Markdown files:           ~200 MB   ✅ KEEP
Search database:          ~100 MB   ✅ KEEP (includes sample metadata + URLs)
Sample code .zip:         ~27 GB    ✅ KEEP (can't re-download without Apple ID login)
Third-party packages:     ~5-10 GB  ✅ KEEP (curated packages)

Total: ~32-37 GB (sample zips must be kept, cannot automate downloads)
```

**Hybrid Sample Code Strategy (UPDATED):**
- Index README summaries only (<1 GB in database)
- Store Apple docs URLs + GitHub URLs (when available) in database
- **Keep existing .zip files** - cannot re-download without manual login
- Track which samples are locally available vs need manual download
- For samples with GitHub repos, provide GitHub URL (no login required)
- Search results indicate: "Locally available" or "Manual download required"

**Implementation approach:**
```bash
# Index all already-downloaded sample READMEs
cd /Volumes/Code/DeveloperExt/appledocsucker

# 1. Index all sample READMEs (extracts temp, indexes, deletes extraction)
appledocsucker index-samples \
  --samples-dir sample-code \
  --docs-dir docs \
  --search-db search.db

# 2. KEEP .zip files (can't re-download without login)
# 3. Database tracks:
#    - locally_available: true (we have it)
#    - apple_docs_url: https://developer.apple.com/... (requires login)
#    - github_url: https://github.com/... (if available, no login)
```

**Total essential storage:** ~32-37 GB
**Cannot reduce further:** Apple sample downloads require manual login

---

## Known Issues / Tech Debt

- [ ] SwiftLint type_body_length warning in HTMLToMarkdown.swift (disabled)
- [ ] Error handling could be more granular
- [ ] No retry logic for failed HTTP requests
- [ ] Crawl metadata could track more statistics
- [ ] No progress persistence for interrupted crawls (resume works, but state is basic)
- [ ] Consider storing full content in database to avoid file dependency (future optimization)

---

## Next Steps (Immediate)

1. **Tonight:** Wait for documentation crawl to complete (~13,000 pages)
2. **Tomorrow:** Rebuild search index with full docs
3. **This Weekend:** Run package analysis script
4. **Next Week:** Start Phase 2 (Sample Code Integration)

---

## Time Budget Summary

| Phase | Estimated Time | Priority |
|-------|---------------|----------|
| Phase 1: Complete Crawl | Wait + 1h | IMMEDIATE |
| Phase 2: Sample Code | 6-8 hours | HIGH |
| Phase 3: Third-Party Packages | 12-15 hours | HIGH |
| Phase 4: API Indexing | 6-8 hours | MEDIUM |
| Phase 5: Delta Tracking | 5-7 hours | MEDIUM |
| Phase 6: Native GUI | 6-8 hours | MEDIUM |
| Phase 7: Documentation | 3-4 hours | LOW |
| **Total** | **~45-60 hours** | |

**Realistic full implementation:** 1-2 weeks of focused work
**Professional client project:** 6-8 weeks with meetings, iterations, QA

---

*Last updated: 2024-11-15 03:30 AM*
*Current crawl: 8,421 pages (64.8% complete)*

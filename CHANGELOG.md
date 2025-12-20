## 0.8.0 (2025-12-20)

### Added
- **Doctor Command Enhanced** - Package diagnostics (#81)
  - Shows user selections file status and package count
  - Shows downloaded README count
  - Warns about orphaned READMEs (packages no longer selected)
  - Displays priority package breakdown (Apple vs ecosystem)
- **String Formatter Tests** - 34 unit tests for display formatting (#81)
  - `StringFormatterTests.swift` covers truncation, markdown escaping, camelCase splitting

### Changed
- **Code Quality Improvements** (#81)
  - Consolidated magic numbers into `Shared.Constants` (timeouts, delays, limits, intervals)
  - Added `Timeout`, `Delay`, `Limit`, `Interval` namespaces for better organization
  - Replaced hardcoded values across WKWebCrawler, HIGCrawler, and other modules
- **PriorityPackagesCatalog** - Made fields optional for TUI compatibility
  - `appleOfficial` tier now optional (TUI only saves ecosystem tier)
  - Stats fields `totalCriticalApplePackages` and `totalEcosystemPackages` now optional
- **Search Result Formatting** (#81)
  - Hierarchical result numbering (1.1, 1.2, 2.1, etc.)
  - Source counts in headers: `## 1. Apple Documentation (20) 📚`
  - Renamed `md` variable to `output` in formatters for clarity

### Fixed
- **Package-docs fetch now reads user selections** (#107)
  - `cupertino fetch --type package-docs` now loads from `~/.cupertino/selected-packages.json`
  - Falls back to bundled `priority-packages.json` if user file doesn't exist
  - TUI package selections are now respected by fetch command
- **Display Formatting Bugs** (#81)
  - Double space artifacts ("Tab  bars" → "Tab bars")
  - Smart title-casing (only lowercase first letters get uppercased)
  - SwiftLint violations (line length, identifier names)

### Related Issues
- Closes #81, #107

---

## 0.7.0 (2025-12-15)

### Added
- **Unified Search with Source Parameter**
  - New `--source` parameter: `apple-docs`, `samples`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`, `packages`, `all`
  - Teasers show results from alternate sources in every search response
  - Source-aware messaging tells AI exactly what was searched
- **Documentation Database Expanded** - 302,424 docs across 307 frameworks (up from 234k/287)

### Changed
- Consolidated multiple search tools into one unified search tool
- Shared formatters between MCP and CLI for consistent output
- Shared TeaserFormatter and constants eliminate hardcoding

---

## 0.6.0 (2025-12-12)

### Added
- **Platform Availability Support** (#99)
  - `cupertino fetch --type availability` - Fetch platform version data for all docs
  - Availability tracked for all sources: apple-docs, sample-code, archive, swift-evolution, swift-book, hig
  - Search filtering by `--min-ios`, `--min-macos`, `--min-tvos`, `--min-watchos`, `--min-visionos` (CLI and MCP `search_docs` tool)
  - `save` command now warns if docs don't have availability data
  - Schema v7: availability columns in docs_metadata and sample_code_metadata

### Availability Sources
| Source | Strategy |
|--------|----------|
| apple-docs | API fetch + fallbacks |
| sample-code | Derives from framework |
| apple-archive | Derives from framework |
| swift-evolution | Swift version mapping |
| swift-book/hig | Universal (all platforms) |

### Documentation
- Added `docs/commands/search/option (--)/min-ios.md`
- Added `docs/commands/search/option (--)/min-macos.md`
- Added `docs/commands/search/option (--)/min-tvos.md`
- Added `docs/commands/search/option (--)/min-watchos.md`
- Added `docs/commands/search/option (--)/min-visionos.md`
- Updated search command docs with availability filtering options

### Related Issues
- Closes #99

---

## 0.5.0 (2025-12-11)

**Why minor bump?** The `cupertino release` command was removed from the public CLI. Users who had scripts calling `cupertino release` will need to update them. This is a breaking change for maintainer workflows.

### Added
- **Documentation Database Expanded** - 234,331 pages across 287 frameworks (up from 138k/263)
  - Kernel: 24,747 docs
  - Matter: 22,013 docs
  - Swift: 17,466 docs
  - Full deep crawl of Apple Developer Documentation
- **New ReleaseTool Package** - Maintainer-only release automation (#98)
  - `cupertino-rel bump` - Update version in all files
  - `cupertino-rel tag` - Create and push git tags
  - `cupertino-rel databases` - Upload databases to cupertino-docs
  - `cupertino-rel homebrew` - Update Homebrew formula
  - `cupertino-rel docs-update` - Documentation-only releases
  - `cupertino-rel full` - Complete release workflow

### Changed
- **Breaking:** `cupertino release` removed from CLI - maintainers now use separate `cupertino-rel` executable
- README now shows accurate documentation counts

### Fixed
- Flaky ArchiveGuideCatalog tests (#101)

### Documentation
- Updated `docs/DEPLOYMENT.md` with automated release instructions
- Added `Packages/Sources/ReleaseTool/README.md`

### Related Issues
- Closes #98, #101

---

## 0.4.0 (2025-12-09)

### Added
- **HIG Support** - Human Interface Guidelines documentation (#95)
  - `cupertino fetch --type hig` - Fetch HIG documentation
  - New HIG source for search results

### Fixed
- Swift.org indexer now handles JSON files correctly

### Documentation
- Added video demo
- Added MIT License
- Added Homebrew tap info to README

### Related Issues
- Closes #95

---

## 0.3.4

### Added
- **One-Command Install** - Single curl command installs everything (#82)
  - `bash <(curl -sSL .../install.sh)` - Downloads binary and databases
  - Pre-built universal binary (arm64 + x86_64)
  - Code signed with Developer ID Application certificate
  - Notarized with Apple for Gatekeeper approval
  - GitHub Actions workflow for automated releases
- Closes #79, #82

---

## 0.3.0

### Added
- **Setup Command** - Instant database download from GitHub Releases (#65)
  - `cupertino setup` - Download pre-built databases in ~30 seconds
  - Version parity - CLI version matches release tag for schema compatibility
  - Progress bar with percentage and download size
  - `--base-dir` option for custom location
  - `--force` flag to re-download
- **Release Command** - Automated database publishing for maintainers (#66)
  - `cupertino release` - Package and upload databases to GitHub Releases
  - Creates versioned zip with SHA256 checksum
  - `--dry-run` for local testing
  - Handles existing releases (deletes and recreates)
- **Remote Sync** - New `--remote` flag for `cupertino save` command (#52)
  - Stream documentation directly from GitHub without local crawling
  - Build database locally in ~45 minutes instead of 20+ hours
  - Resumable - if interrupted, continue from where you left off
  - No disk bloat - streams directly to SQLite
  - Uses raw.githubusercontent.com (no API rate limits)
- **RemoteSync Package** - New standalone Swift 6 package with strict concurrency
  - `RemoteIndexer` actor for orchestrating remote sync
  - `GitHubFetcher` actor for HTTP operations
  - `RemoteIndexState` Sendable struct for state persistence
  - `AnimatedProgress` for terminal progress display

### Documentation
- Updated README with "Instant Setup" quick start using `cupertino setup`
- Added `docs/commands/setup/README.md` documentation
- Added `docs/commands/release/README.md` documentation
- Added `docs/commands/save/option (--)/remote/` documentation
- Updated `docs/commands/README.md` with new commands

### Related Issues
- Closes #52, #65, #66

---

## 0.2.7

### Fixed
- **Search Ranking** - Penalize release notes in search results (2.5x multiplier) to prevent them polluting unrelated queries (#57)
- **Swift Evolution Indexing** - Fix filename pattern to match `SE-0001.md` format (#61)
- **Database Re-indexing** - Delete database before re-index to prevent FTS5 duplicate rows doubling db size (#62)
- **Serve Output** - Simplified startup messages to show only DB paths; server now requires at least one database to start (#60)

---

## 0.2.6

### Fixed
- **MCP Server Tool Registration** - Fixed bug where only sample code tools were exposed (#55)
  - Created `CompositeToolProvider` that delegates to both `DocumentationToolProvider` and `SampleCodeToolProvider`
  - All 7 MCP tools now properly exposed: `search_docs`, `list_frameworks`, `read_document`, `search_samples`, `list_samples`, `read_sample`, `read_sample_file`
  - Follows composite pattern with proper separation of concerns

### Related Issues
- Fixes #55

---

## 0.2.5

### Added
- **CLI Sample Code Commands** - Full parity with MCP sample code tools (#51)
  - `cupertino list-samples` - List indexed sample projects
  - `cupertino search-samples <query>` - Search sample code projects and files
  - `cupertino read-sample <project-id>` - Read project README and metadata
  - `cupertino read-sample-file <project-id> <path>` - Read source file content
- **CLI Framework List Command**
  - `cupertino list-frameworks` - List available frameworks with document counts
- All new commands support `--format text|json|markdown` output

### Related Issues
- Closes #51

---

## 0.2.4

### Added
- **GitHub Sample Code Fetcher** - Fast alternative to Apple website scraping
  - `cupertino fetch --type samples` - Clone/pull from public GitHub repository
  - 606 projects, ~10GB with Git LFS
  - Much faster than `--type code` (~4 minutes vs hours)
- **Sample Code Directory Indexing** - Index extracted project directories (not just ZIPs)
  - `SampleIndexBuilder` now scans both ZIP files and extracted folders
  - Supports GitHub-cloned projects in `cupertino-sample-code/` subdirectory
  - 18,000+ source files indexed for full-text search

### Changed
- Sample code can now be fetched from two sources:
  - `--type samples` - GitHub (recommended, faster)
  - `--type code` - Apple website (requires authentication)

---

## 0.2.3

### Added
- **Apple Archive Documentation Crawler** - Crawl legacy Apple programming guides (Core Animation, Core Graphics, Core Text, etc.) (#41)
- `cupertino fetch --type archive` - Fetch archived Apple programming guides
- `--include-archive` flag for search command - Include legacy guides in results
- `include_archive` parameter for MCP `search_docs` tool
- Framework synonyms for better search (QuartzCore↔CoreAnimation, CoreGraphics↔Quartz2D)
- Source-based search ranking (modern docs rank higher, archive docs have slight penalty)
- TUI Archive view for browsing and selecting archive guides

### Changed
- Archive documentation excluded from search by default (use `--include-archive` or `--source apple-archive`)
- Updated MCP tool description to document archive features

### Related Issues
- Closes #41

---

## 0.2.2

### Added
- Intelligent kind inference for unknown document types using URL depth, title patterns, and word count signals
- Improved search ranking for core types when `kind=unknown`

### Fixed
- Fixed URL scheme error when resuming crawl session (#47)

### Related Issues
- Closes #47
- Related to #28 (Search Ranking Improvements)

---

## 0.2.1

### Fixed
- Fixed crawler filename collision causing parent documentation pages to be overwritten by operators/methods (#45)
- Crawler now generates unique filenames for URLs with special characters using hash suffixes
- Parent types (Text, Color, Date, String structs) will be restored on next crawl

### Related Issues
- Closes #45
- Related to #28 (Search Ranking Improvements)

---

## 0.2.0

### Fixed
- **CRITICAL**: Fixed cleanup bug that deleted source code instead of .git folders (#40)
- Simplified `compressDirectory()` to preserve Apple's flat ZIP structure
- Reduced cleanup patterns to only safe items: .git, .DS_Store, DerivedData, build, .build, xcuserdata, *.xcuserstate
- Verified all 606/607 sample ZIPs contain intact source code (1 corrupted in original download)
- Cleanup now achieves 44% space reduction (27GB → 15GB) while preserving all code

---

## 0.1.9

### Added
- `--language` filter for search (swift, objc) - CLI and MCP (#34)
- `source` parameter to MCP `search_docs` tool (#38)

### Changed
- Database schema v5 - added `language` column to docs_fts and docs_metadata
- **BREAKING**: Requires database rebuild (`rm ~/.cupertino/search.db && cupertino save`)

---

## 0.1.8

### Added
- `cupertino cleanup` - Clean up sample code archives by removing .git, .DS_Store, xcuserdata, etc. (#31)
- Dry run mode (`--dry-run`) to preview cleanup without modifying files
- Keep originals mode (`--keep-originals`) to preserve original ZIPs

### Changed
- Reorganized docs folder structure to be self-illustrating (folders show command syntax)
- Removed unused serve command options (`--docs-dir`, `--evolution-dir`, `--search-db`)

### Fixed
- Dry run now correctly detects nested junk files (e.g., `.git/hooks/*`)

---

## 0.1.7

### Added
- Unified logging system with categories and log levels (#26, #30)
- Search tests for swift-book URIs

### Fixed
- `read_document` returning empty content for swift-book URIs
- Consolidated logging across all modules

---

## 0.1.6

### Added
- `cupertino search` - CLI command for searching documentation without MCP server (#23)
- `cupertino read` - CLI command for reading full documents by URI
- `summaryTruncated` field in search results for AI agents
- Truncation indicator with word count in text output
- Comprehensive command documentation in `docs/commands/`

### Changed
- Increased summary limit from 500 to 1500 characters
- JSON-first crawling to reduce WKWebView memory usage (#25)

### Fixed
- Memory spike on large index pages by using JSON API first (#25)

---

## 0.1.0 — Pre-release

- Initial crawler prototype (`Crawler`)
- Local MCP server implemented (`Serve`)
- Admin TUI added (`AdminUI`)
- Documentation system connected
- Pre-release versioning strategy established
- Internal architecture stabilized enough for developer preview


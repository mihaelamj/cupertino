## 0.11.0 (2026-04-23)

### Added
- **Transitive dependency resolution for `fetch --type package-docs`** (#184): each seed in `priority-packages.json` is now walked through its `Package.swift` first (libraries commit this; most lockfiles are `.gitignored`), then `Package.resolved` as a fallback for apps. Fetched from `raw.githubusercontent.com`; GitHub-hosted dependencies are added to the fetch queue. Non-GitHub URLs, missing manifests, and malformed manifests are counted and reported, then skipped. Opt out with `--no-recurse`. Terminates via canonical-name dedupe, so a seed like `vapor` naturally pulls in `swift-nio`, `async-http-client`, `swift-log`, etc. without manual curation.
- **GitHub redirect canonicalisation**: seeds and discovered URLs are canonicalised via `api.github.com/repos/<owner>/<repo>` before the resolver's dedupe set, so aliases like `apple/swift-docc` and `swiftlang/swift-docc` collapse into one entry instead of double-indexing. Results are cached at `~/.cupertino/.cache/canonical-owners.json`; one API call per unique repo, lifetime.
- **Persisted resolved closure** at `~/.cupertino/resolved-packages.json`: records the full closure, timestamp, cupertino version, per-package parentage (which seed(s) pulled each package in), and a checksum of the seed + exclusion inputs. Next fetch reuses this cache unless the checksum changed or `--refresh` is passed. Answers "why is this package in my index?" by inspection.
- **User exclusion list** at `~/.cupertino/excluded-packages.json`: a flat JSON array of `"owner/repo"` strings that the resolver drops from its closure even when transitively discovered. Absent by default; hand-edit to use.
- **`--refresh` flag** on `fetch --type package-docs`: discards the cached closure and re-walks every dependency graph. Use when upstream packages have added new dependencies since the last fetch.
- **Parallel resolver**: the BFS now dispatches manifest fetches in batches of 10 concurrent requests instead of sequential one-by-one. A 200-package closure shrinks from roughly 3 minutes of wall time to a few tens of seconds on a typical connection.
- **Per-branch manifest cache** at `~/.cupertino/.cache/manifests/<owner>/<repo>/<branch>/Package.swift` with 24h TTL. 404s cached as zero-byte sentinels so known-missing files aren't re-requested. Complements the seed-checksum cache: when the checksum misses (seeds changed or `--refresh` passed), repeat runs reuse manifests whose upstream hasn't changed in the last day.
- **SPM registry id counting**: `.package(id: "scope.name", …)` identifier-based dependencies (SPM 5.8+) are detected in `Package.swift` and surfaced as `Skipped (SPM registry id)` in the resolver summary. Source URLs for registry ids are out of scope for this resolver — registry protocol resolution needs per-registry handling — but we don't silently lose track of them.
- **TUI promote / exclude actions** in the package view:
  - `x`: toggle exclusion. Excluded packages persist to `~/.cupertino/excluded-packages.json` on the next `w` (save) and drop from future resolver closures.
  - `p`: promote the current entry (typically a discovered-via-dep package) to a seed. Equivalent to selecting with space, but explicit in the keybinding for users navigating the closure.
  - Visual indicators: `[*]` seed, `[X]` excluded, `[+]` discovered-via-dep-only, `[ ]` none. Loaded from `resolved-packages.json` + `excluded-packages.json` at TUI startup.
- **Expanded bundled `priority-packages.json`**: 36 seeds grew to 135. Breakdown: 43 Apple (12 additions including `swift-syntax` moved to the swiftlang namespace, `swift-foundation`, `swift-markdown`, `swift-http-types`, `swift-nio-extras`, `swift-configuration`, `swift-distributed-tracing`); 92 ecosystem covering the full Vapor and Hummingbird ecosystems, an expanded Point-Free set (18 additions), swiftlang (`swift-syntax`, `swift-docc-plugin`, `swift-docc-symbolkit`), SSWG (`async-http-client`, `swift-service-lifecycle`, `swift-openapi-async-http-client`, `swift-openapi-vapor`), tooling (`SwiftFormat`, `SwiftLint`, `XcodeGen`), Soto, SwiftUI Introspect, Tuist, and project-specific seeds derived from a real `Package.resolved` (`Inject`, `KZFileWatchers`, `OpenAPIKit`, `Playbook`, `Roadmap`, `Yams`).

### Fixed
- **Homebrew resource bundle lookup** (#161): `fetch --type package-docs` and `fetch --type archive` crashed on fresh Homebrew installs with `Fatal error: could not load resource bundle`. Root cause: SPM's `Bundle.module` resolves via `Bundle.main.bundleURL`, which does not resolve symlinks, so `/opt/homebrew/bin/cupertino` pointed the lookup at `/opt/homebrew/bin/Cupertino_Resources.bundle` rather than the Cellar. `CupertinoResources.bundle` now resolves the executable URL's symlinks before looking up the resource bundle, independent of the formula's `post_install` symlink. Landed in `b9bc70a` shortly after the v0.10.0 tag; this release is the first to ship it.
- **`fetch --type package-docs` honours user selections** (#107): `PriorityPackagesCatalog` read `~/.cupertino/selected-packages.json` when present but never created it, so the bundled catalog was used even when the TUI had been run. First access now copies the bundled `priority-packages.json` to the user location so subsequent edits (TUI or manual) take effect immediately, matching the `ArchiveGuideCatalog` pattern.

---

## 0.9.1 (2026-01-25)

### Added
- **MCP client configuration docs** - Added setup guides for multiple AI tools (#134, #137)
  - OpenAI Codex (CLI and ~/.codex/config.toml)
  - Cursor (.cursor/mcp.json)
  - VS Code with GitHub Copilot (.vscode/mcp.json)
  - Zed (settings.json)
  - Windsurf (~/.codeium/windsurf/mcp_config.json)
  - opencode (opencode.jsonc)
- **Binary documentation** - Full docs for additional executables (#137)
  - cupertino-tui: Terminal UI with 5 views documented
  - mock-ai-agent: MCP testing tool with arguments documented
  - cupertino-rel: Release tool with 6 subcommands and all options
  - 48 new documentation files in docs/binaries/
- **mock-ai-agent --version** - Added version flag support (#137)

---

## 0.10.0 (2026-03-13)

### Added
- Framework synonyms: search using common alternate names (e.g., "nfc" → CoreNFC, "bluetooth" → CoreBluetooth, "shareplay" → GroupActivities)
- Seed framework discovery from Apple's technologies.json for complete coverage
- Agent skill for stateless CLI usage (#167, thanks @tijs)
- Database v0.9.0: 320,771 documents across 443 frameworks (+18k docs, +136 frameworks)

### Changed
- Case-insensitive framework matching across all search functions
- Reduced default request delay from 0.5s to 0.05s for faster crawling

### Fixed
- Crawler session resume now validates startURL before resuming
- Case-insensitive URL prefix matching in shouldVisit
- Link enqueue before skip check — incremental re-crawls now discover new child pages
- Case-insensitive framework queries in searchByKind and searchSampleCode

## 0.9.0 (2025-12-31)

### Changed
- **MCP Protocol Upgrade** - Support 2025-06-18 with backward compatibility (#130)
  - Upgraded default protocol version from 2024-11-05 to 2025-06-18
  - Server negotiates compatible version with clients
  - MCPClient and MockAIAgent support version fallback
  - Thanks to @erikmackinnon for the contribution

---

## 0.8.3 (2025-12-31)

### Changed
- **Swift-only MCP integration tests** - Rewrote tests and removed Node.js dependency (#131)
  - New integration tests use `cupertino serve` instead of npm packages
  - Tests verify MCP initialize handshake and tools/list responses
  - Validates protocol version, server info, and tool registration
  - Added Language Policy to AGENTS.md: no Node.js/npm in codebase

---

## 0.8.2 (2025-12-31)

### Fixed
- **Setup progress animation** - Show download and extraction progress (#96)
  - Added `DownloadProgressDelegate` for real-time download progress
  - Added `ExtractionSpinner` for extraction feedback
  - Extended download timeout to 10 minutes for large database files

---

## 0.8.1 (2025-12-28)

### Fixed
- **Installer ANSI escape sequences** - Fix raw `\033[...]` text in summary (#124)
  - Two `echo` statements missing `-e` flag for color output
  - Affects `bash <(curl ...)` install method

---

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


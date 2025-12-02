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


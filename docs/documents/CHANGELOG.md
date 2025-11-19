# Changelog

## [0.1.5] - 2025-11-15

### Fixed
- **Critical: Output directory consistency**: Fixed bug where resuming a crawl without `--output-dir` would auto-detect a different directory than the original session, causing files to be split across two locations
- Session state now includes output directory to ensure consistent file placement across interruptions
- Auto-resume now searches all subdirectories in `~/.docsucker/` to find matching sessions

### Changed
- Improved session detection logic to find active crawls in custom output directories within `~/.docsucker/`
- Added informative message when resuming from an existing session

### Note
- For crawls using custom `--output-dir` paths **outside** `~/.docsucker/`, you must continue to specify the same `--output-dir` when resuming

## [0.1.4] - 2025-11-15

### Added
- **`--allowed-prefixes` option**: Manually specify allowed URL prefixes (comma-separated) to curate crawls
- **www.swift.org support**: Full support for crawling www.swift.org documentation hub (articles, guides, etc.)

### Changed
- **Simplified swift.org behavior**: Now allows entire swift.org domain by default - curate via start URL instead of hardcoded prefixes
- Enhanced URL utilities to handle www.swift.org URLs

## [0.1.3] - 2025-11-15

### Added
- **Swift.org documentation crawling support**: Can now crawl docs.swift.org (The Swift Programming Language book)
- **Per-directory metadata**: Each output directory gets its own metadata.json for independent crawl sessions
- **Auto-directory selection**: Automatically chooses `swift-org/` for Swift.org URLs, `docs/` for Apple docs
- **Flexible URL prefix configuration**: Support for multiple documentation sources beyond developer.apple.com
- **Resume command**: New `cupertino resume` command to continue crawls without typing start URLs

### Changed
- Enhanced URL normalization to support docs.swift.org domain
- Framework extraction now handles both Apple and Swift.org URLs
- Metadata files now stored in output directories instead of global ~/.docsucker/metadata.json
- `--output-dir` is now optional and auto-detected from start URL

## [0.1.2] - 2025-11-15

### Added
- **Crawl state persistence**: Auto-saves crawl progress every 30 seconds
- **Auto-resume capability**: Automatically resumes from saved session state
- **`--resume` flag**: Explicit flag for resuming crawls
- **Enhanced progress logging**: Detailed stats every 50 pages with ETA
- **Log file support**: `--log-file` option for persistent crawl logs
- Session state tracking (visited URLs + pending queue)

### Changed
- Crawler now persists queue state and visited URLs
- Progress updates include speed (pages/sec) and ETA
- Improved error handling during state persistence

### Fixed
- Crawl can now survive interruptions and continue from exact position

## [0.1.1] - 2025-11-15

### Features
- Basic crawling with WKWebView
- SQLite FTS5 search indexing
- MCP server for AI agents
- Swift Evolution proposal indexing
- Change detection with SHA256 hashing
- Homebrew installation support


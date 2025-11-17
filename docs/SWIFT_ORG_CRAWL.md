# Swift.org Documentation Crawling

## Version 0.1.3 Feature

Added support for crawling Swift.org documentation (The Swift Programming Language book and related docs).

## Changes Made

### 1. URL Utilities Enhancement (Sources/CupertinoShared/Models.swift)

Updated `URLUtilities.extractFramework()` to recognize Swift.org URLs:
- Detects `docs.swift.org` domain
- Extracts "swift-book" for The Swift Programming Language
- Falls back to "swift-org" for other Swift.org docs

Updated `URLUtilities.filename()` to handle Swift.org URLs:
- Strips `https://docs.swift.org/` prefix
- Normalizes paths to safe filenames

### 2. Configuration Auto-Detection (Sources/CupertinoShared/Configuration.swift)

Enhanced `CrawlerConfiguration.init()` to automatically detect allowed prefixes:
- **For swift.org domains**: Allows `/swift-book` and `/documentation` paths
- **For apple.com domains**: Allows `/documentation` path only
- **For other domains**: Allows entire host

This means you can now just pass a `--start-url` and the crawler will automatically:
- Determine the correct URL prefixes to follow
- Stay within the appropriate documentation sections

### 3. Version Bumps

- Updated VERSION file to 0.1.3
- Updated CHANGELOG.md with new features
- Updated version strings in both CLI and MCP binaries

## Usage

### Command Line

Crawl Swift.org documentation:

```bash
cupertino crawl \
  --start-url "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/" \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-book \
  --max-pages 200 \
  --max-depth 10 \
  --resume
```

### Convenience Script

```bash
cd /Volumes/Code/DeveloperExt/work/cupertino/Packages
./crawl-swift-book.sh
```

The script will:
1. Build v0.1.3
2. Start crawling Swift.org docs
3. Save to `/Volumes/Code/DeveloperExt/appledocsucker/swift-book/`
4. Log to `/Volumes/Code/DeveloperExt/appledocsucker/swift-book-crawl.log`

## Expected Results

### The Swift Programming Language (TSPL)
- **Estimated pages**: 60-80
- **Sections**:
  - Language Guide (29 files): TheBasics, ControlFlow, Functions, Closures, etc.
  - Reference Manual (10 files): LexicalStructure, Types, Expressions, Statements, etc.
  - Guided Tour (3 files)
  - Root documentation

### Additional Swift.org Docs
- Server-side Swift guides
- C++ interoperability docs
- DocC documentation
- ~20+ additional articles

### Output Structure

```
/Volumes/Code/DeveloperExt/appledocsucker/swift-book/
├── swift-book/          # The Swift Programming Language files
│   ├── documentation_the_swift_programming_language_*.md
│   └── ...
└── swift-org/           # Other Swift.org documentation
    └── ...
```

## Crawl Time Estimate

- **~60-80 pages** × **0.5s delay** = ~30-40 seconds base
- **+JavaScript rendering time** = ~2-3 minutes per page
- **Total estimate**: 5-10 minutes for complete crawl

## Important Notes

### Does NOT Affect Running Crawls

- v0.1.2 (currently running Apple docs crawl) uses symlink
- Building v0.1.3 will update the symlink
- **BUT** the running process (PID 77059) still uses the v0.1.2 binary in memory
- The Apple docs crawl will continue unaffected

### Separate Output Directories

- Apple docs: `/Volumes/Code/DeveloperExt/appledocsucker/docs/`
- Swift.org docs: `/Volumes/Code/DeveloperExt/appledocsucker/swift-book/`
- Different metadata files (separate sessions)
- Can run concurrently without interference

### Resume Capability

Swift.org crawl supports the same resume functionality as Apple docs:
- Auto-saves every 30 seconds
- Can be interrupted and resumed
- Progress logging every 50 pages

## Testing

To test without building, you can verify the URL utilities work correctly:

```swift
import CupertinoShared

let swiftURL = URL(string: "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics")!
let framework = URLUtilities.extractFramework(from: swiftURL)
// Should return: "swift-book"

let filename = URLUtilities.filename(from: swiftURL)
// Should return: "swift_book_documentation_the_swift_programming_language_thebasics"
```

## Future Enhancements

Potential additions for future versions:
- [ ] Dedicated `crawl-swift-book` subcommand (instead of generic `crawl`)
- [ ] Swift.org-specific metadata tracking
- [ ] Integration with search index (separate table for Swift.org docs)
- [ ] MCP resource provider for Swift.org docs (similar to Apple docs)

## Related Files

- `Sources/CupertinoShared/Models.swift` - URL utilities
- `Sources/CupertinoShared/Configuration.swift` - Configuration with auto-detection
- `CHANGELOG.md` - Version history
- `VERSION` - Current version number
- `crawl-swift-book.sh` - Convenience script

## Version History

- **v0.1.3** (2025-11-15): Added Swift.org documentation crawling support
- **v0.1.2** (2025-11-15): Added crawl state persistence and resume capability
- **v0.1.1** (2025-11-15): Initial stable release

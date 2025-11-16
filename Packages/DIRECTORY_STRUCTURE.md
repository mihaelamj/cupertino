# Cupertino - Directory Structure Reference

## Hardcoded Paths

**⚠️ CRITICAL: These paths are hardcoded throughout the codebase - do NOT change them**

### Base Directory
```
/Volumes/Code/DeveloperExt/private/cupertino/
```

### Data Directories

| Directory | Absolute Path | Contents | Size | Count |
|-----------|---------------|----------|------|-------|
| **Documentation** | `/Volumes/Code/DeveloperExt/private/cupertino/docs` | Crawled Apple docs (markdown) | 61 MB | 10,099+ files |
| **Swift Evolution** | `/Volumes/Code/DeveloperExt/private/cupertino/swift-evolution` | Accepted proposals (markdown) | 8.2 MB | 429 files |
| **Sample Code** | `/Volumes/Code/DeveloperExt/private/cupertino/sample-code` | Sample projects (.zip) | 26 GB | 607 files |
| **Search Database** | `/Volumes/Code/DeveloperExt/private/cupertino/search.db` | SQLite FTS5 index | ~100 MB | 1 file |

### Directory Tree

```
/Volumes/Code/DeveloperExt/private/cupertino/
│
├── docs/                           # Documentation markdown files
│   ├── swift/                      # Framework subdirectories
│   │   ├── documentation_swift_array.md
│   │   ├── documentation_swift_dictionary.md
│   │   └── ...
│   ├── swiftui/
│   │   ├── documentation_swiftui_view.md
│   │   └── ...
│   ├── uikit/
│   ├── foundation/
│   └── ...
│
├── swift-evolution/                # Swift Evolution proposals
│   ├── 0001-*.md
│   ├── 0002-*.md
│   ├── ...
│   └── 0429-*.md
│
├── sample-code/                    # Sample code .zip files
│   ├── accelerate-blurring-an-image.zip
│   ├── swiftui-building-a-document-based-app.zip
│   ├── ...
│   └── (607 total .zip files)
│
└── search.db                       # SQLite FTS5 search index

Total: ~32-37 GB
```

## File Naming Conventions

### Documentation Files
- Pattern: `documentation_{framework}_{topic}.md`
- Examples:
  - `documentation_swift_array.md`
  - `documentation_swiftui_view.md`
  - `documentation_uikit_uiview.md`

### Swift Evolution Proposals
- Pattern: `{number}-{title}.md`
- Examples:
  - `0001-keywords-as-argument-labels.md`
  - `0066-standardize-function-type-syntax.md`

### Sample Code Files
- Pattern: `{framework}-{description}.zip`
- Examples:
  - `accelerate-blurring-an-image.zip`
  - `swiftui-building-a-document-based-app.zip`
  - `coredata-synchronizing-a-local-store-to-the-cloud.zip`

## What's Inside Each File Type

### Documentation Markdown (.md)
```markdown
---
source: https://developer.apple.com/documentation/Swift/Array
crawled: 2025-11-15T09:08:10Z
---

# Array | Apple Developer Documentation

An ordered, random-access collection.

## Overview
Arrays are one of the most commonly used data types...
```

### Swift Evolution Proposals (.md)
Standard markdown with proposal metadata, motivation, detailed design, etc.

### Sample Code Archives (.zip)
```
sample-code.zip
├── README.md               # ✅ ALWAYS PRESENT (100% coverage verified)
├── LICENSE.txt
├── Configuration/
│   └── SampleCode.xcconfig
├── ProjectName.xcodeproj/
├── ProjectName/
│   └── *.swift files
└── .git/                   # ⚠️ NEVER EXTRACT (stays in .zip)
```

## Code References

### Swift Constants
Use these hardcoded paths in Swift code:

```swift
// Base directory
let baseDir = "/Volumes/Code/DeveloperExt/private/cupertino"

// Data directories
let docsDir = "/Volumes/Code/DeveloperExt/private/cupertino/docs"
let evolutionDir = "/Volumes/Code/DeveloperExt/private/cupertino/swift-evolution"
let samplesDir = "/Volumes/Code/DeveloperExt/private/cupertino/sample-code"
let searchDB = "/Volumes/Code/DeveloperExt/private/cupertino/search.db"
```

### Shell Scripts
```bash
# Base directory
BASE_DIR="/Volumes/Code/DeveloperExt/private/cupertino"

# Data directories
DOCS_DIR="$BASE_DIR/docs"
EVOLUTION_DIR="$BASE_DIR/swift-evolution"
SAMPLES_DIR="$BASE_DIR/sample-code"
SEARCH_DB="$BASE_DIR/search.db"
```

## External SSD Info

- **Volume:** `/Volumes/Code`
- **Project Root:** `/Volumes/Code/DeveloperExt/private/cupertino`
- **Available Space:** ~1.6 TB free
- **File System:** APFS (case-sensitive)

## Important Notes

1. **Never use relative paths** - always use absolute paths
2. **Never use environment variables** - hardcode paths directly
3. **Never extract .git folders** from sample .zips
4. **Sample code requires Apple ID login** - cannot re-download automatically
5. **All 607 samples have README.md** (verified 100% coverage)

## Quick Verification Commands

```bash
# Check documentation count
find /Volumes/Code/DeveloperExt/private/cupertino/docs -name "*.md" | wc -l

# Check Swift Evolution count
find /Volumes/Code/DeveloperExt/private/cupertino/swift-evolution -name "*.md" | wc -l

# Check sample code count
find /Volumes/Code/DeveloperExt/private/cupertino/sample-code -name "*.zip" | wc -l

# Check total size
du -sh /Volumes/Code/DeveloperExt/private/cupertino

# Verify README in sample
unzip -l /Volumes/Code/DeveloperExt/private/cupertino/sample-code/accelerate-blurring-an-image.zip | grep README
```

---

*Last updated: 2024-11-15*
*All paths verified and documented*

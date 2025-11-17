# Cupertino Files and Folders

*Complete reference for all files and directories created by Cupertino*
*Last updated: 2024-11-16*

---

## Overview

Cupertino creates a structured set of directories and files to organize crawled documentation, metadata, search indexes, and configuration. This document explains every file and folder, their purpose, format, and how they're used.

---

## Directory Structure

### Default Directory Layout

By default, Cupertino uses `~/.cupertino` as the base directory. This can be customized via command-line parameters.

```
~/.cupertino/                          # Base directory (configurable)
├── docs/                              # Apple documentation (Markdown)
│   ├── swift/                         # Framework-specific subdirectories
│   │   ├── documentation_swift.md
│   │   ├── documentation_swift_bool.md
│   │   └── ...
│   ├── swiftui/
│   ├── uikit/
│   └── [259 frameworks total]
│
├── swift-evolution/                   # Swift Evolution proposals
│   ├── 0001-keywords-as-argument-labels.md
│   ├── 0002-remove-currying.md
│   └── [431 proposals]
│
├── swift-org/                         # Swift.org documentation
│   ├── swift-book/                    # The Swift Programming Language
│   └── ...
│
├── sample-code/                       # Apple sample code projects
│   ├── sample-project-name.zip
│   └── [607 sample projects]
│
├── packages/                          # Third-party Swift package data
│   ├── swift-packages-with-stars.json
│   └── checkpoint.json
│
├── metadata.json                      # Crawl metadata (tracking file)
├── config.json                        # Configuration file
├── search.db                          # SQLite FTS5 search index
│
└── logs/                              # Log files (optional)
    ├── crawl.log
    └── swift-org-crawl.log
```

---

## Directory Details

### 1. `docs/` - Documentation Files

**Purpose:** Stores crawled Apple documentation in Markdown format

**Structure:**
- Organized by framework (e.g., `swift/`, `swiftui/`, `uikit/`)
- Each page is a separate `.md` file
- Filenames derived from URL (normalized, lowercased)

**Example File:** `docs/swift/documentation_swift_task_init_name_priority_operation.md`

**File Format:**
```markdown
---
source: https://developer.apple.com/documentation/swift/task/init(...)
crawled: 2025-11-15T12:25:23Z
---

# init(name:executorPreference:priority:operation:) | Apple Developer Documentation

[Content follows...]
```

**Created By:** `DocumentationCrawler.crawl()`

**Configured By:**
- `CrawlerConfiguration.outputDirectory` (where to save)
- `OutputConfiguration.format` (markdown or html)

**Command Line:**
```bash
cupertino crawl \
  --output-dir ~/my-docs \       # Customize output directory
  --max-pages 1000
```

---

### 2. `swift-evolution/` - Swift Evolution Proposals

**Purpose:** Stores Swift Evolution proposals (SE-0001, SE-0002, etc.)

**Structure:**
- One file per proposal
- Named `NNNN-proposal-title.md` (e.g., `0001-keywords-as-argument-labels.md`)
- 431 proposals as of 2024-11-16

**File Format:**
```markdown
# Allowing Keywords as Argument Labels

* Proposal: [SE-0001](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0001-keywords-as-argument-labels.md)
* Author: [Doug Gregor](https://github.com/DougGregor)
* Status: **Implemented (Swift 2.2)**
* Review Manager: [Chris Lattner](https://github.com/lattner)

[Proposal content...]
```

**Created By:** `SwiftEvolutionCrawler`

**Command Line:**
```bash
cupertino crawl-swift-evolution \
  --output-dir ~/.cupertino/swift-evolution
```

---

### 3. `swift-org/` - Swift.org Documentation

**Purpose:** Stores documentation from docs.swift.org

**Structure:**
- `swift-book/` - The Swift Programming Language book
- Other Swift.org resources

**File Format:** Same as Apple docs (Markdown with frontmatter)

**Created By:** `DocumentationCrawler` with Swift.org start URL

**Command Line:**
```bash
cupertino crawl \
  --start-url https://docs.swift.org/swift-book/ \
  --output-dir ~/.cupertino/swift-org
```

---

### 4. `sample-code/` - Sample Code Projects

**Purpose:** Stores Apple sample code projects as `.zip` files

**Structure:**
- One `.zip` file per sample project
- 607 projects as of 2024-11-16
- Total size: ~26 GB

**Filename Example:** `building-a-custom-peer-to-peer-protocol.zip`

**Contents:** Each `.zip` contains:
- Complete Xcode project
- README.md
- Source code
- Assets

**Created By:** `SampleCodeDownloader`

**Command Line:**
```bash
cupertino download-samples \
  --output-dir ~/.cupertino/sample-code
```

**Note:** Downloads require Apple ID login (manual authentication)

---

### 5. `packages/` - Package Data

**Purpose:** Stores third-party Swift package information

**Files:**

#### `swift-packages-with-stars.json` (3.0 MB)

Complete package list from SwiftPackageIndex with GitHub metadata.

**Format:**
```json
{
  "packages": [
    {
      "owner": "apple",
      "repo": "swift",
      "url": "https://github.com/apple/swift",
      "stars": 65000,
      "description": "The Swift Programming Language",
      "lastUpdated": "2024-11-15T10:30:00Z"
    }
  ]
}
```

#### `checkpoint.json`

Tracks package fetch progress for resuming.

**Format:**
```json
{
  "lastProcessedIndex": 1250,
  "totalPackages": 5000,
  "timestamp": "2024-11-15T14:22:00Z"
}
```

**Created By:** `PackageFetcher`

**Command Line:**
```bash
cupertino fetch-packages \
  --output-dir ~/.cupertino/packages
```

---

## File Details

### `metadata.json` - Crawl Metadata

**Purpose:** Tracks crawl state, statistics, and page metadata for:
- Resume functionality
- Change detection
- Incremental updates

**Location:** Can be in multiple places:
- Per-directory: `<output-dir>/metadata.json` (recommended)
- Global: `~/.cupertino/metadata.json` (default)
- Custom: `--metadata-file <path>`

**Size:** Varies based on pages crawled
- Small crawl (~100 pages): ~50 KB
- Medium crawl (~5,000 pages): ~2 MB
- Large crawl (~20,000 pages): ~10 MB

**Format:**
```json
{
  "pages": {
    "https://developer.apple.com/documentation/swift": {
      "url": "https://developer.apple.com/documentation/swift",
      "framework": "swift",
      "filePath": "/Users/name/.cupertino/docs/swift/documentation_swift.md",
      "contentHash": "3366e9f7a55f90bb97e9...",
      "depth": 0,
      "lastCrawled": "2025-11-15T12:25:23Z"
    }
  },
  "stats": {
    "totalPages": 15234,
    "newPages": 15234,
    "updatedPages": 0,
    "skippedPages": 0,
    "errors": 12,
    "startTime": "2025-11-15T10:00:00Z",
    "endTime": "2025-11-15T18:30:00Z"
  },
  "lastCrawl": "2025-11-15T18:30:00Z",
  "crawlState": {
    "isActive": false,
    "startURL": "https://developer.apple.com/documentation/",
    "outputDirectory": "/Users/name/.cupertino/docs",
    "visited": ["url1", "url2", ...],
    "queue": [
      {
        "url": "https://developer.apple.com/documentation/...",
        "depth": 2
      }
    ],
    "sessionStartTime": "2025-11-15T10:00:00Z",
    "lastSaveTime": "2025-11-15T18:30:00Z"
  }
}
```

**Key Fields:**

- **`pages`:** Dictionary of URL → page metadata
  - `url`: Original URL
  - `framework`: Extracted framework name (swift, swiftui, etc.)
  - `filePath`: Where the markdown file is saved
  - `contentHash`: SHA-256 hash for change detection
  - `depth`: How many links away from start URL
  - `lastCrawled`: When this page was last fetched

- **`stats`:** Statistics for the crawl
  - `totalPages`: Total pages crawled
  - `newPages`: New pages (not in previous metadata)
  - `updatedPages`: Pages that changed (different hash)
  - `skippedPages`: Pages skipped (no change)
  - `errors`: Number of errors encountered
  - `startTime`, `endTime`: Crawl duration

- **`crawlState`:** Resume state (only present during active crawl)
  - `isActive`: Whether crawl is in progress
  - `startURL`: Where crawl began
  - `outputDirectory`: Where files are being saved
  - `visited`: Set of visited URLs (for deduplication)
  - `queue`: Pending URLs to crawl
  - `sessionStartTime`: When current session started
  - `lastSaveTime`: Last auto-save timestamp

**Created By:**
- Auto-created on first crawl
- Updated every 30 seconds during crawl (auto-save)
- Finalized when crawl completes

**Used For:**
- Resume: Load queue and visited set to continue interrupted crawl
- Change detection: Compare contentHash to detect updated pages
- Incremental updates: Only re-crawl changed pages
- Statistics: Show user what was crawled

---

### `config.json` - Configuration File

**Purpose:** Stores persistent configuration for Cupertino

**Location:** `~/.cupertino/config.json` or `--config <path>`

**Format:**
```json
{
  "crawler": {
    "startURL": "https://developer.apple.com/documentation/",
    "allowedPrefixes": [
      "https://developer.apple.com/documentation"
    ],
    "maxPages": 15000,
    "maxDepth": 15,
    "outputDirectory": "/Users/name/.cupertino/docs",
    "logFile": "/Users/name/.cupertino/logs/crawl.log",
    "requestDelay": 0.5,
    "retryAttempts": 3
  },
  "changeDetection": {
    "enabled": true,
    "metadataFile": "/Users/name/.cupertino/metadata.json",
    "forceRecrawl": false
  },
  "output": {
    "format": "markdown",
    "includePDF": false
  }
}
```

**Created By:**
```bash
cupertino init  # Creates default config
```

**Loaded Automatically:** If present, config is loaded on every command

**Override:** Command-line args override config file settings

---

### `search.db` - Search Index

**Purpose:** SQLite database with FTS5 (Full-Text Search) index

**Location:** `~/.cupertino/search.db` or `--search-db <path>`

**Size:** ~100-200 MB for complete Apple documentation

**Schema:**

#### Table: `docs_metadata`
```sql
CREATE TABLE docs_metadata (
    uri TEXT PRIMARY KEY,            -- Unique resource identifier
    framework TEXT NOT NULL,          -- Framework name (swift, swiftui, etc.)
    file_path TEXT NOT NULL,          -- Path to markdown file
    content_hash TEXT,                -- SHA-256 hash of content
    last_crawled INTEGER,             -- Unix timestamp
    word_count INTEGER,               -- Number of words in document
    source_type TEXT DEFAULT 'apple', -- Source (apple, swift-org, package)
    package_id INTEGER                -- FK to packages table (if applicable)
);

CREATE INDEX idx_framework ON docs_metadata(framework);
CREATE INDEX idx_source_type ON docs_metadata(source_type);
```

#### Table: `docs_fts` (FTS5 Virtual Table)
```sql
CREATE VIRTUAL TABLE docs_fts USING fts5(
    uri UNINDEXED,  -- Not indexed for search (just stored)
    title,          -- Page title (indexed)
    summary,        -- First ~500 chars (indexed)
    content,        -- Full page content (indexed)
    content=docs_metadata,  -- Content source
    content_rowid=rowid     -- Sync mechanism
);
```

#### Table: `packages` (Future)
```sql
CREATE TABLE packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    owner TEXT NOT NULL,
    repository_url TEXT NOT NULL,
    documentation_url TEXT,
    stars INTEGER,
    last_updated INTEGER,
    is_apple_official INTEGER DEFAULT 0,
    description TEXT,
    UNIQUE(owner, name)
);
```

**Created By:**
```bash
cupertino build-index \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir ~/.cupertino/swift-evolution \
  --search-db ~/.cupertino/search.db
```

**Used By:** MCP server for search queries

**Search Query Example:**
```sql
SELECT
    uri,
    title,
    summary,
    bm25(docs_fts) as rank
FROM docs_fts
WHERE docs_fts MATCH 'async await'
ORDER BY rank
LIMIT 20;
```

---

## Configuration Parameters

### Output Directory

**Default:** `~/.cupertino/docs`

**Customize:**
```bash
# Via command line
cupertino crawl --output-dir /custom/path

# Via config file
{
  "crawler": {
    "outputDirectory": "/custom/path"
  }
}
```

**What's Affected:**
- Where markdown files are saved
- Framework subdirectory structure created here
- Metadata file location (if using per-directory metadata)

---

### Metadata File

**Default:** `~/.cupertino/metadata.json` OR `<output-dir>/metadata.json`

**Customize:**
```bash
# Explicit path
cupertino crawl --metadata-file /custom/metadata.json

# Per-directory (recommended)
cupertino crawl --output-dir /my-docs
# Creates: /my-docs/metadata.json
```

**Recommendation:** Use per-directory metadata (one metadata.json per output directory)

**Why:** Allows multiple separate crawls without conflicts

---

### Search Database

**Default:** `~/.cupertino/search.db`

**Customize:**
```bash
cupertino build-index --search-db /custom/search.db
```

---

### Log Files

**Default:** None (logs to stdout)

**Enable:**
```bash
cupertino crawl --log-file ~/.cupertino/logs/crawl.log
```

**Format:** Plain text, one log entry per line

---

## File Naming Conventions

### Markdown Files

**Pattern:** `documentation_<path-components>.md`

**Examples:**
```
URL: https://developer.apple.com/documentation/swift
File: docs/swift/documentation_swift.md

URL: https://developer.apple.com/documentation/swift/task
File: docs/swift/documentation_swift_task.md

URL: https://developer.apple.com/documentation/swift/task/init(name:priority:operation:)
File: docs/swift/documentation_swift_task_init_name_priority_operation.md
```

**Normalization:**
- Lowercase
- Remove scheme and domain
- Replace `/` with `_`
- Remove special characters (parentheses, colons, etc.)
- Remove query parameters and fragments

---

### Framework Directories

**Derived From:** URL path

**Examples:**
```
https://developer.apple.com/documentation/swift/*       → docs/swift/
https://developer.apple.com/documentation/swiftui/*     → docs/swiftui/
https://developer.apple.com/documentation/uikit/*       → docs/uikit/
https://docs.swift.org/swift-book/*                     → docs/swift-book/
```

---

## File Sizes (Typical)

```
docs/                    100-150 MB  (20,000 pages)
swift-evolution/         8-10 MB     (431 proposals)
swift-org/               10-15 MB    (Swift Book + guides)
sample-code/             25-30 GB    (607 projects)
packages/                3-5 MB      (package metadata JSON)

metadata.json            5-15 MB     (depends on page count)
config.json              1-2 KB      (small config)
search.db                100-200 MB  (full FTS5 index)
```

---

## Data Flow

### During Crawl

```
1. Start Crawl
   ↓
2. Load metadata.json (if exists)
   ↓
3. Create/update docs/<framework>/*.md files
   ↓
4. Auto-save metadata.json every 30 seconds
   ↓
5. Finalize metadata.json on completion
```

### During Search Index Build

```
1. Read all .md files from docs/
   ↓
2. Read all .md files from swift-evolution/
   ↓
3. Extract: URI, title, summary, content
   ↓
4. Insert into search.db (docs_metadata + docs_fts)
   ↓
5. Create indexes for fast queries
```

### During MCP Search

```
1. Client: search_docs(query="async await")
   ↓
2. MCP Server: Query search.db FTS5 index
   ↓
3. Return: URIs with BM25 ranking
   ↓
4. Client: resources/read(uri)
   ↓
5. MCP Server: Read markdown file from disk
   ↓
6. Return: Full content
```

---

## Resume Functionality

When a crawl is interrupted (crash, Ctrl+C, error), resume uses `metadata.json`:

**What's Saved:**
```json
{
  "crawlState": {
    "isActive": true,
    "startURL": "...",
    "outputDirectory": "/path/to/docs",
    "visited": ["url1", "url2", ...],  // ~20K URLs
    "queue": [                         // ~55K items
      {"url": "...", "depth": 2}
    ],
    "sessionStartTime": "...",
    "lastSaveTime": "..."
  }
}
```

**On Resume:**
```bash
cupertino crawl --resume
```

1. Load `metadata.json`
2. Check `crawlState.isActive` == true
3. Restore `visited` set (skip already-crawled pages)
4. Restore `queue` (continue where left off)
5. Continue crawling

**Note:** Currently broken due to Bug #1 (resume detection) and Bug #7 (metadata sync)

---

## Incremental Updates

To re-crawl and update only changed pages:

```bash
cupertino update
# OR
cupertino crawl --no-force-recrawl
```

**How It Works:**
1. Load existing `metadata.json`
2. For each URL in queue:
   - Fetch page
   - Compute contentHash
   - Compare with stored hash in metadata
   - If different: save new markdown, update metadata
   - If same: skip (no changes)

**Benefits:**
- Faster updates (skip unchanged pages)
- Less bandwidth usage
- Preserves crawl history

**Note:** Currently broken due to Bug #13 (hash instability)

---

## Cleanup and Maintenance

### Remove Old Data

```bash
# Remove all crawled data
rm -rf ~/.cupertino/docs
rm -rf ~/.cupertino/swift-evolution
rm -rf ~/.cupertino/swift-org

# Keep sample code (can't re-download without login)
# DO NOT: rm -rf ~/.cupertino/sample-code

# Remove metadata (forces fresh crawl)
rm ~/.cupertino/metadata.json

# Remove search index (rebuild with build-index)
rm ~/.cupertino/search.db
```

### Rebuild Search Index

```bash
cupertino build-index \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir ~/.cupertino/swift-evolution \
  --search-db ~/.cupertino/search.db
```

---

## Summary

**Essential Files:**
- `docs/` - Crawled documentation (118 MB)
- `metadata.json` - Tracking and resume (5-15 MB)
- `search.db` - Search index (100-200 MB)

**Optional Files:**
- `config.json` - Persistent configuration
- `logs/` - Log files
- `swift-evolution/` - Proposals
- `swift-org/` - Swift.org docs
- `sample-code/` - Sample projects
- `packages/` - Package data

**Total Space:** 150-200 MB (docs + index) + 26 GB (sample code)

---

*End of File and Folder Documentation*

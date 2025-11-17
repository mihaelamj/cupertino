# Sample Code Integration Plan

## IMPORTANT: Apple Sample Code Download Constraints

**⚠️ CRITICAL:** Apple sample code downloads require Apple ID login - cannot be automated!

**Implications:**
- Cannot re-download samples programmatically
- Must keep existing .zip files (27GB)
- Cannot build automatic sample fetching for missing samples
- For new samples: users must manually download from developer.apple.com
- Search results should indicate: "Locally available" vs "Manual download required"
- Where possible, find GitHub URLs (some samples are open source on GitHub)

## Current State Analysis

**What we have:**
- 607 sample code projects downloaded as .zip files (manually downloaded)
- Filenames follow pattern: `{framework}-{description}.zip`
  - Example: `accelerate-blurring-an-image.zip`
  - Framework prefix helps categorization
  - Description is URL-slug-ified title
- Zips contain full Xcode projects with .git history
- Documentation pages reference sample code projects
- Total size: ~27GB compressed
- **Cannot delete .zip files** - no way to re-download without manual login

**Filename Structure Insights:**
- Framework prefix (accelerate, swiftui, avfoundation, etc.)
- Kebab-case description matches documentation URLs
- Can be parsed to extract: framework, title, topic

## Strategic Questions

### 1. **Should agents get zipped or unzipped code?**

**Decision: HYBRID APPROACH** ✅
- Index README summaries from all samples
- Keep .zip files (cannot re-download without Apple ID login)
- Track local availability + GitHub URLs in database
- For actually using samples: agents can extract on-demand from local .zips

**Why not extract all?**
- 607 samples × ~70MB average = ~40-50GB extracted
- Most samples won't be accessed frequently
- Can extract on-demand when needed
- README indexing provides searchability

**Storage:**
- Keep .zip files (~27GB) - CANNOT delete, no way to re-download
- Index README summaries in database (<1GB)
- Track: locally_available, apple_docs_url, github_url
- Extract on-demand to temp location when agents request code

### 2. **How to link samples to documentation?**

**Observations:**
- Docs contain text: "This sample code project is associated with..."
- References to specific files/classes
- WWDC session links

**Approach:**
1. Parse documentation for sample references
2. Build mapping: `doc_url -> [sample_slugs]`
3. Extract README.md from each sample
4. Index README content with framework/title metadata

### 3. **Should samples be searchable?**

**Yes - agents would benefit from:**
- Searching by framework: "Show me SwiftUI samples"
- Searching by topic: "Core Data concurrency examples"
- Finding samples mentioned in docs
- Browsing by technique/API used

### 4. **Storage & Organization**

**Hardcoded base directory:** `/Volumes/Code/DeveloperExt/appledocsucker/`

**Directory structure:**
```
/Volumes/Code/DeveloperExt/appledocsucker/
├── docs/                    # Documentation markdown (current: 102 files)
├── swift-evolution/         # Proposals (current: 429 files)
├── sample-code/            # Zipped samples (current: 607 .zip files, ~27GB)
├── sample-code-extracted/  # Extracted samples (to be created)
│   ├── accelerate-blurring-an-image/
│   │   ├── README.md
│   │   ├── BlurringAnImage.xcodeproj/
│   │   └── BlurringAnImage/
│   │       └── *.swift files
│   └── ...
└── search.db               # Search index (current: 542 docs, 14.1MB)
```

**Hardcoded paths in code:**
- Base: `/Volumes/Code/DeveloperExt/cupertino`
- Docs: `$BASE/docs`
- Evolution: `$BASE/swift-evolution`
- Samples (zipped): `$BASE/sample-code`
- Samples (extracted): `$BASE/sample-code-extracted`
- Search DB: `$BASE/search.db`

## Implementation Plan

### Phase 1: Sample Extraction & Metadata Indexing

**Goal:** Extract all samples and make them discoverable

**Implementation in `SearchIndexBuilder.swift`:**

1. **Add `indexSamples()` method**
   - Scan `sample-code/*.zip` files
   - For each zip:
     - Extract to `sample-code-extracted/{slug}/`
     - Strip `.git` directories
     - Read README.md
     - Parse framework from filename
     - Count Swift files
   - Log progress: "📦 Extracting & indexing samples..."

2. **Build sample registry in search.db**
   - Add table: `samples_metadata`
   - Fields: slug, framework, title, description, zip_path, extracted_path, readme_text, file_count, swift_file_count

3. **Link to documentation** (Phase 2)
   - Scan docs for sample references
   - Build: `doc_page -> [sample_slugs]` mapping
   - Store in `samples_metadata.related_docs`

### Phase 2: Search Integration

1. **Add samples table to search.db**
   ```sql
   CREATE TABLE samples (
       slug TEXT PRIMARY KEY,
       framework TEXT,
       title TEXT,
       description TEXT,
       readme_content TEXT,
       zip_path TEXT,
       extracted_path TEXT,
       file_count INTEGER,
       related_docs TEXT  -- JSON array of doc URIs
   );
   ```

2. **Create FTS index**
   ```sql
   CREATE VIRTUAL TABLE samples_fts USING fts5(
       slug,
       framework,
       title,
       description,
       readme_content,
       tokenize='porter unicode61'
   );
   ```

3. **Add MCP tool: `search_samples`**
   - Query: keywords, framework filter
   - Returns: metadata + README + related docs
   - Option to get file listing

### Phase 3: MCP Tools for Sample Access

**Add to `DocsSearchToolProvider.swift` or new `SampleCodeToolProvider.swift`:**

1. **MCP tools:**
   - `search_samples(query, framework)` - Search sample READMEs
   - `get_sample_info(slug)` - Get metadata + file listing
   - `list_sample_files(slug)` - Get file tree
   - `read_sample_file(slug, path)` - Read specific file
   - `search_in_samples(query)` - Grep across all Swift code

2. **Tool descriptions for agents:**
   ```
   search_samples: Find sample code projects by keywords or framework.
                   Returns README content and file listings.

   read_sample_file: Read a specific source file from a sample project.
                     Use after searching to see implementation details.
   ```

### Phase 4: API-Level Granular Indexing (Dash-style)

**Goal:** Index every API element individually for precise lookups

**What Dash has that we don't:**
- 678,370 indexed API elements vs our ~20K-30K pages
- Individual methods, properties, constants, enums indexed separately
- Direct deep links to specific APIs

**Implementation:**

1. **Parse documentation pages for API elements**
   - Extract from markdown code blocks
   - Parse class/struct/enum definitions
   - Extract method signatures, properties, constants
   - Identify API type: Method, Property, Constant, Function, Class, Struct, Enum, Protocol

2. **Add API-level table to search.db**
   ```sql
   CREATE TABLE api_elements (
       id INTEGER PRIMARY KEY,
       name TEXT NOT NULL,              -- e.g., "backgroundColor"
       type TEXT NOT NULL,               -- Method, Property, Constant, Class, etc.
       parent TEXT,                      -- e.g., "UIView" (for properties/methods)
       framework TEXT NOT NULL,          -- e.g., "UIKit"
       language TEXT,                    -- "swift" or "objc"
       signature TEXT,                   -- Full method signature
       description TEXT,                 -- Short description
       page_uri TEXT NOT NULL,           -- Link back to full doc page
       FOREIGN KEY (page_uri) REFERENCES docs_metadata(uri)
   );

   CREATE VIRTUAL TABLE api_elements_fts USING fts5(
       name,
       type,
       parent,
       framework,
       signature,
       description,
       tokenize='porter unicode61'
   );
   ```

3. **API extraction patterns**
   - Classes: `class UIViewController`, `struct String`
   - Methods: `func viewDidLoad()`, `func dataTask(with:completionHandler:)`
   - Properties: `var backgroundColor: UIColor`
   - Constants: `static let didBecomeActive`
   - Enums: `enum UIUserInterfaceStyle`
   - Protocols: `protocol Codable`

4. **Enhanced MCP tools**
   - `search_api(query, type, framework)` - Search specific APIs
     - Example: "UIView backgroundColor" → direct property match
     - Example: "URLSession dataTask" → all dataTask methods
   - `get_api_details(name, parent, framework)` - Get full API info
   - Current `search_docs` still works for page-level search

**Benefits for Agents:**

| Query Type | Current (Page-level) | With API Indexing |
|------------|---------------------|-------------------|
| "How to use Core Data" | ✅ Full guide page | ✅ Same + related APIs |
| "UIView backgroundColor" | ⚠️ Search UIView page | ✅ Direct property match |
| "URLSession methods" | ⚠️ Full URLSession page | ✅ List of all methods |
| "What is Codable" | ✅ Protocol page | ✅ Direct protocol + conforming types |

**Estimated effort:** 6-8 hours
- Parser for API elements: 3-4 hours
- Database schema + indexing: 2-3 hours
- MCP tools: 1-2 hours

**Priority:** Phase 4 (after sample code integration)

### Phase 5: Advanced Sample Code Features

1. **Code indexing within samples**
   - Parse Swift files in sample code
   - Index: classes, functions, APIs used
   - Enable search: "samples using URLSession"

2. **Cross-referencing**
   - Link samples to API documentation
   - Link API elements to samples that use them
   - Show "Used in samples: X, Y, Z" for each API
   - Bidirectional navigation

## Data Flow

```
User/Agent Query
    ↓
MCP search_samples tool
    ↓
Search samples_fts table
    ↓
Return metadata + README
    ↓
(Optional) Agent requests specific files
    ↓
Extract zip (if needed)
    ↓
Return requested files
```

## Benefits for Agents

1. **Discovery:** "Show me samples about Core Image filters"
2. **Context:** README explains what sample demonstrates
3. **Learning:** Can read actual implementation code
4. **Reference:** Link between theory (docs) and practice (samples)
5. **Examples:** Copy-paste working code patterns

## Estimated Effort

- **Phase 1:** 2-3 hours (metadata extraction, registry)
- **Phase 2:** 2-3 hours (search integration, MCP tools)
- **Phase 3:** 1-2 hours (on-demand extraction)
- **Phase 4:** 4-6 hours (full code indexing)

**Total for Phases 1-3:** ~6-8 hours
**Full feature set:** ~10-14 hours

## Decisions Made

1. ✅ Extract ALL samples upfront (plenty of SSD space)
2. ✅ Strip .git directories (reduce size)
3. ✅ Hardcode base path: `/Volumes/Code/DeveloperExt/cupertino`
4. ✅ Index READMEs first, full code indexing in Phase 4
5. ✅ Keep .zip files for re-download capability

## Extraction Strategy

**✅ Extraction during indexing** (Recommended)

The `cupertino build-index` command should:
1. Scan `sample-code/*.zip` files
2. Extract each to `sample-code-extracted/{slug}/` (if not already extracted)
3. Strip `.git` directories during extraction
4. Index README.md content
5. Build file inventory
6. Store metadata in `search.db`

**Benefits:**
- Single command for everything: `cupertino build-index`
- Smart: only extracts if needed (checks extracted dir existence)
- Clean: removes .git during extraction
- Integrated: extraction + indexing in one pass

**Command:**
```bash
cupertino build-index \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --evolution-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
  --samples-dir /Volumes/Code/DeveloperExt/appledocsucker/sample-code \
  --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

**Estimated extracted size:** ~40-50GB (with .git stripped)

## Next Steps

1. ✅ Review this plan
2. Create `SampleMetadataExtractor.swift`
3. Add `samples` table to SearchIndex
4. Add MCP search_samples tool
5. Test with agent queries
6. Implement delta tracking for documentation changes
7. Add popular Swift package documentation (SwiftPackageIndex.com integration)

---

## Phase 6: Delta Tracking & Change Detection

**Goal:** Track documentation changes over time to identify new, updated, and removed pages.

**Location:** `/Volumes/Code/DeveloperExt/appledocsucker/deltas/`

### Delta File Structure

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── deltas/
│   ├── snapshots/
│   │   ├── 2024-11-15.json          # Full snapshot of crawl
│   │   ├── 2024-11-20.json          # Next crawl snapshot
│   │   └── 2024-12-01.json
│   ├── changes/
│   │   ├── 2024-11-15_to_2024-11-20.json  # Delta between crawls
│   │   └── 2024-11-20_to_2024-12-01.json
│   └── latest.json                  # Symlink to most recent snapshot
```

### Snapshot Format

```json
{
  "crawl_date": "2024-11-15T03:10:55Z",
  "total_pages": 13414,
  "pages": [
    {
      "uri": "swift://documentation/swift",
      "path": "docs/swift/documentation_swift.md",
      "content_hash": "sha256:abc123...",
      "file_size": 6004,
      "last_modified": "2024-11-15T00:00:00Z",
      "framework": "swift",
      "title": "Swift"
    }
  ],
  "frameworks": {
    "swift": 1234,
    "uikit": 567,
    "swiftui": 890
  }
}
```

### Delta Format

```json
{
  "from_date": "2024-11-15T03:10:55Z",
  "to_date": "2024-11-20T10:00:00Z",
  "summary": {
    "added": 45,
    "modified": 123,
    "removed": 12,
    "unchanged": 13234
  },
  "added": [
    {
      "uri": "swift://documentation/swift/new-feature",
      "path": "docs/swift/documentation_swift_new-feature.md",
      "framework": "swift",
      "title": "New Feature",
      "added_date": "2024-11-20T10:00:00Z"
    }
  ],
  "modified": [
    {
      "uri": "swift://documentation/swift/updated-api",
      "old_hash": "sha256:abc123...",
      "new_hash": "sha256:def456...",
      "changes": "Content updated",
      "modified_date": "2024-11-20T10:00:00Z"
    }
  ],
  "removed": [
    {
      "uri": "swift://documentation/swift/deprecated-api",
      "path": "docs/swift/documentation_swift_deprecated-api.md",
      "framework": "swift",
      "removed_date": "2024-11-20T10:00:00Z",
      "reason": "Page no longer exists"
    }
  ]
}
```

### Implementation

#### 1. Add to `SearchIndex.swift`

```swift
func createSnapshot(outputPath: String) async throws {
    let snapshot = CrawlSnapshot(
        crawlDate: Date(),
        totalPages: /* count */,
        pages: /* all pages */,
        frameworks: /* framework counts */
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(snapshot)
    try data.write(to: URL(fileURLWithPath: outputPath))
}
```

#### 2. Add to `cupertino build-index` command

```bash
cupertino build-index \
  --docs-dir /path/to/docs \
  --search-db /path/to/search.db \
  --create-snapshot /path/to/deltas/snapshots/2024-11-15.json
```

#### 3. Add `cupertino compare` command

```bash
# Compare two snapshots
cupertino compare \
  --from deltas/snapshots/2024-11-15.json \
  --to deltas/snapshots/2024-11-20.json \
  --output deltas/changes/2024-11-15_to_2024-11-20.json

# Compare against latest
cupertino compare \
  --from deltas/latest.json \
  --to deltas/snapshots/2024-11-20.json \
  --auto-output
```

#### 4. Add to MCP Server

```swift
// New MCP tool: get_documentation_changes
func getDocumentationChanges(since: String?) async throws -> [Change] {
    // Read latest delta file
    // Return changes since date or last N changes
}
```

### Use Cases

**For Users:**
- "What changed in Apple docs this week?"
- "Show me new Swift Evolution proposals"
- "Which APIs were updated?"

**For AI Agents:**
- Proactively notify about relevant changes
- Track API evolution over time
- Identify deprecated features

**For Automation:**
- Weekly email digest of changes
- RSS feed of documentation updates
- Changelog generation

### MCP Tool: `get_documentation_changes`

```typescript
{
  "name": "get_documentation_changes",
  "description": "Get documentation changes between crawls",
  "inputSchema": {
    "type": "object",
    "properties": {
      "since": {
        "type": "string",
        "description": "ISO date or 'latest' for last delta"
      },
      "framework": {
        "type": "string",
        "description": "Filter by framework (optional)"
      },
      "change_type": {
        "type": "string",
        "enum": ["added", "modified", "removed", "all"],
        "default": "all"
      }
    }
  }
}
```

### Automation Script

```bash
#!/bin/bash
# /usr/local/bin/cupertino-daily-crawl

DATE=$(date +%Y-%m-%d)
SNAPSHOT="/Volumes/Code/DeveloperExt/appledocsucker/deltas/snapshots/${DATE}.json"
LATEST="/Volumes/Code/DeveloperExt/appledocsucker/deltas/latest.json"

# Crawl documentation
cupertino crawl \
  --start-url https://developer.apple.com/documentation \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --max-pages 20000

# Build index and create snapshot
cupertino build-index \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db \
  --create-snapshot "$SNAPSHOT"

# Compare with previous crawl
if [ -f "$LATEST" ]; then
  cupertino compare \
    --from "$LATEST" \
    --to "$SNAPSHOT" \
    --auto-output
fi

# Update latest symlink
ln -sf "$SNAPSHOT" "$LATEST"

# Notify if changes found
CHANGES=$(jq '.summary.added + .summary.modified + .summary.removed' \
  "deltas/changes/${DATE}.json")

if [ "$CHANGES" -gt 0 ]; then
  echo "📊 Documentation changes: $CHANGES"
  # Send notification, email, etc.
fi
```

### Database Schema Addition

```sql
-- Track crawl history
CREATE TABLE crawl_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    crawl_date INTEGER NOT NULL,
    snapshot_path TEXT NOT NULL,
    total_pages INTEGER NOT NULL,
    pages_added INTEGER,
    pages_modified INTEGER,
    pages_removed INTEGER,
    delta_path TEXT
);

CREATE INDEX idx_crawl_date ON crawl_history(crawl_date DESC);
```

### Estimated Effort

- **Snapshot generation:** 1-2 hours (integrate with build-index)
- **Compare command:** 2-3 hours (delta calculation logic)
- **MCP tool:** 1 hour (expose deltas to agents)
- **Automation script:** 30 minutes
- **Testing:** 1 hour

**Total: 5-7 hours**

---

**Notes:**
- Keep zips as canonical source
- Extract on-demand to avoid 27GB+ extraction
- READMEs provide 80% of value with 1% of space
- Code access available but not required for initial value
- **Delta tracking enables change monitoring and API evolution tracking**

---

## Phase 7: Third-Party Swift Package Documentation

**Goal:** Index documentation from popular Swift packages to provide comprehensive Swift ecosystem coverage.

**Source:** https://swiftpackageindex.com

### Popular Packages to Index

**Server-Side Swift:**
- Vapor (web framework)
- Hummingbird (lightweight web framework)
- Swift NIO (async networking)
- Fluent (ORM)

**CLI Tools:**
- Swift Argument Parser
- Swift Log
- Swift Metrics

**Testing:**
- Quick/Nimble
- SnapshotTesting

**Networking:**
- Alamofire
- Moya

**Data:**
- SwiftyJSON
- Codable extensions

**UI (iOS/macOS):**
- SnapKit (Auto Layout)
- Kingfisher (image loading)
- SwiftGen (code generation)

### Documentation Sources

Swift packages can have documentation in multiple formats:

1. **DocC Archives** (`.doccarchive`)
   - Modern Swift documentation format
   - Best case: hosted on GitHub Pages or package website
   - Example: `https://swiftpackageindex.com/vapor/vapor/documentation`

2. **README + Inline Comments**
   - Extract from GitHub repository
   - Parse markdown README
   - Generate docs from source comments

3. **Hosted Documentation Sites**
   - Vapor: https://docs.vapor.codes
   - Hummingbird: https://hummingbird-project.github.io/hummingbird-docs
   - Custom documentation sites

### Implementation Strategy

#### Option 1: SwiftPackageIndex API (Recommended)

SwiftPackageIndex provides documentation URLs for packages:

```swift
struct PackageInfo: Codable {
    let name: String
    let owner: String
    let repository: String
    let documentationURL: String?
    let stars: Int
    let lastActivityAt: Date
}

func fetchTopPackages(limit: Int = 100) async throws -> [PackageInfo] {
    // Query SwiftPackageIndex API or scrape rankings
    // Filter by: stars > 1000, has documentation
}
```

#### Option 2: Direct Crawling

For each package:

1. **Check for DocC archive**
   ```
   https://swiftpackageindex.com/{owner}/{repo}/documentation/
   ```

2. **Check GitHub Pages**
   ```
   https://{owner}.github.io/{repo}/documentation/
   ```

3. **Check custom docs site**
   ```
   // Parse package README for documentation link
   ```

4. **Fallback: Generate from README**
   ```swift
   // Fetch README.md from GitHub
   // Convert to documentation format
   ```

### Directory Structure

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── third-party/
│   ├── vapor/
│   │   ├── vapor/              # Main package
│   │   ├── fluent/
│   │   └── leaf/
│   ├── hummingbird/
│   │   └── hummingbird/
│   ├── apple/
│   │   ├── swift-argument-parser/
│   │   ├── swift-nio/
│   │   └── swift-log/
│   └── alamofire/
│       └── alamofire/
```

### Search Index Integration

Add to `search.db`:

```sql
-- Add source type
ALTER TABLE docs_metadata ADD COLUMN source_type TEXT DEFAULT 'apple';
-- Values: 'apple', 'swift-evolution', 'third-party'

-- Add package metadata
CREATE TABLE packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    owner TEXT NOT NULL,
    repository_url TEXT NOT NULL,
    documentation_url TEXT,
    stars INTEGER,
    last_updated INTEGER,
    UNIQUE(owner, name)
);

-- Link docs to packages
ALTER TABLE docs_metadata ADD COLUMN package_id INTEGER REFERENCES packages(id);
```

### MCP Tool: `search_package_docs`

```typescript
{
  "name": "search_package_docs",
  "description": "Search community-maintained Swift package documentation. IMPORTANT: These are third-party packages NOT created or maintained by Apple. Results include popular open-source Swift libraries like Vapor, Hummingbird, Alamofire, etc.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Search query"
      },
      "package": {
        "type": "string",
        "description": "Filter by package name (e.g., 'vapor', 'hummingbird')"
      },
      "limit": {
        "type": "number",
        "default": 10
      }
    },
    "required": ["query"]
  }
}
```

### MCP Response Format

All search results should clearly indicate the source:

```json
{
  "results": [
    {
      "title": "Routing",
      "framework": "vapor",
      "source": "community",
      "source_label": "Community Package: vapor/vapor",
      "package_url": "https://github.com/vapor/vapor",
      "stars": 24000,
      "description": "...",
      "content": "...",
      "disclaimer": "This is a community-maintained package, not an official Apple framework."
    }
  ]
}
```

### Crawl Command

```bash
# Crawl ALL Apple open-source packages (automatic)
cupertino crawl-packages \
  --apple-official \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party
# Automatically fetches all packages from github.com/apple
# ~18 packages: swift-nio, swift-log, swift-argument-parser, etc.

# Crawl curated community packages (top 50, excluding Apple)
cupertino crawl-packages \
  --curated \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party
# Uses predefined list of high-quality packages
# Vapor, Alamofire, TCA, etc.

# Crawl specific package
cupertino crawl-package \
  --owner vapor \
  --repo vapor \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party

# Crawl top N packages from SwiftPackageIndex
cupertino crawl-packages \
  --top 100 \
  --min-stars 1000 \
  --exclude-owner apple \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party

# Crawl everything (Apple + curated + top N)
cupertino crawl-packages \
  --all \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party
```

### Example: Vapor Documentation

**Source:** https://docs.vapor.codes or https://swiftpackageindex.com/vapor/vapor/documentation

**Crawl result:**
```
third-party/vapor/vapor/
├── getting-started.md
├── routing.md
├── controllers.md
├── fluent.md
├── authentication.md
└── deployment.md
```

**Indexed as:**
- Framework: `vapor`
- Source: `third-party`
- Package: `vapor/vapor`
- Searchable alongside Apple docs

### Benefits

1. **Comprehensive coverage** - Apple APIs + popular third-party packages
2. **Real-world examples** - Vapor docs show server-side Swift patterns
3. **Single search** - Query across Apple + third-party in one place
4. **Learning path** - "How to build web API" → Vapor + Foundation + Swift NIO
5. **Ecosystem awareness** - AI agents understand full Swift landscape

### Use Cases

**AI Agent Queries:**
```
User: "How do I build a REST API in Swift?"

Agent searches:
- Apple: URLSession, Foundation
- Third-party: Vapor routing, Hummingbird handlers

Returns: Complete picture of server-side Swift
```

**MCP Search:**
```swift
// Search across all sources (Apple + community packages)
search_docs(query: "async HTTP client")
// Returns with clear source labels:
// - "Apple Official: URLSession"
// - "Community Package: vapor/vapor - Vapor Client"
// - "Community Package: apple/swift-nio - NIO examples"

// Filter to third-party only
search_package_docs(query: "routing", package: "vapor")
// Returns: Vapor-specific routing documentation
// All results clearly marked as "Community Package: vapor/vapor"
```

**Important Implementation Note:**

When implementing the MCP server, ALL results must include a `source` field:

```swift
struct SearchResult: Codable {
    let title: String
    let framework: String
    let source: Source  // .apple, .swiftEvolution, .community
    let summary: String
    let uri: String

    // For community packages only
    let packageOwner: String?
    let packageRepo: String?
    let packageStars: Int?

    // Human-readable source label
    var sourceLabel: String {
        switch source {
        case .apple:
            return "Apple Official"
        case .swiftEvolution:
            return "Swift Evolution Proposal"
        case .community:
            return "Community Package: \(packageOwner!)/\(packageRepo!)"
        }
    }
}

enum Source: String, Codable {
    case apple
    case swiftEvolution = "swift-evolution"
    case community
}
```

### Implementation Phases

#### Phase 7a: Infrastructure (2-3 hours)
- [ ] Add `packages` table to database
- [ ] Add `source_type` and `package_id` columns
- [ ] Create `PackageInfo` model
- [ ] Update search queries to include third-party docs

#### Phase 7b: SwiftPackageIndex Integration (2-3 hours)
- [ ] Fetch top packages from SwiftPackageIndex
- [ ] Parse documentation URLs
- [ ] Filter by stars/activity

#### Phase 7c: Documentation Crawling (3-4 hours)
- [ ] Add `crawl-package` command
- [ ] Support DocC archives
- [ ] Support custom doc sites (Vapor, Hummingbird)
- [ ] Fallback to README parsing

#### Phase 7d: MCP Integration (1-2 hours)
- [ ] Add `search_package_docs` tool
- [ ] Update existing tools to include third-party results
- [ ] Add filtering options

**Total Estimated Effort: 8-12 hours**

### Priority Packages (Phase 1)

#### Tier 1: Apple Open Source Packages (AUTOMATIC - ALL INCLUDED)

All packages under `github.com/apple` should be automatically indexed:

1. **swift-argument-parser** - CLI tool building
2. **swift-nio** - Async networking foundation
3. **swift-log** - Logging infrastructure
4. **swift-metrics** - Metrics/observability
5. **swift-crypto** - Cryptography
6. **swift-collections** - Advanced data structures
7. **swift-algorithms** - Algorithm extensions
8. **swift-numerics** - Numeric protocols
9. **swift-system** - System interfaces
10. **swift-async-algorithms** - AsyncSequence utilities
11. **swift-distributed-actors** - Distributed computing
12. **swift-atomics** - Atomic operations
13. **swift-package-manager** - SPM internals
14. **swift-syntax** - SwiftSyntax (macros, code generation)
15. **swift-testing** - New testing framework
16. **swift-corelibs-foundation** - Foundation implementation
17. **swift-corelibs-dispatch** - GCD implementation
18. **swift-corelibs-xctest** - XCTest implementation

**Reasoning:** These are official Apple packages, maintained by Swift core team, same quality/trust as stdlib.

#### Tier 2: Popular Community Packages (CURATED - TOP ~50)

Curated list of high-quality, well-maintained community packages:

**Server-Side:**
1. **Vapor** (vapor/vapor) - Most popular server framework
2. **Hummingbird** (hummingbird-project/hummingbird) - Modern lightweight framework
3. **Fluent** (vapor/fluent) - Database ORM

**Networking:**
4. **Alamofire** (Alamofire/Alamofire) - iOS HTTP client
5. **Moya** (Moya/Moya) - Network abstraction layer

**UI/Layout:**
6. **SnapKit** (SnapKit/SnapKit) - Auto Layout DSL
7. **Kingfisher** (onevcat/Kingfisher) - Image loading/caching

**Architecture:**
8. **swift-composable-architecture** (pointfreeco/swift-composable-architecture) - TCA
9. **RxSwift** (ReactiveX/RxSwift) - Reactive programming

**Testing:**
10. **Quick/Nimble** (Quick/Quick) - BDD testing

**Total:** ~18 Apple packages (automatic) + ~30-50 curated community packages = ~50-70 total

#### Tier 3: User-Requested (ON-DEMAND)

Users can request specific packages via:
```bash
cupertino crawl-package --owner <owner> --repo <repo>
```

### Dependency Resolution

**IMPORTANT:** When indexing a package, also index its **direct dependencies**.

**Example: Vapor Dependencies**
```
vapor/vapor
  ├── apple/swift-nio (Tier 1 - already included)
  ├── apple/swift-log (Tier 1 - already included)
  ├── vapor/routing-kit
  ├── vapor/console-kit
  └── vapor/multipart-kit
```

**Implementation:**

1. **Fetch Package.swift** from GitHub
2. **Parse dependencies** section
3. **Check if dependency is already indexed**
4. **Recursively crawl dependencies** (max depth: 2 levels)
5. **Mark as "Dependency of X"** in metadata

**Command flags:**
```bash
# Crawl package WITH dependencies (default)
cupertino crawl-package --owner vapor --repo vapor --with-dependencies

# Crawl package WITHOUT dependencies
cupertino crawl-package --owner vapor --repo vapor --no-dependencies

# Set dependency depth
cupertino crawl-package --owner vapor --repo vapor --dependency-depth 2
```

**Dependency Metadata:**

```sql
-- Track package relationships
CREATE TABLE package_dependencies (
    package_id INTEGER NOT NULL,
    dependency_id INTEGER NOT NULL,
    dependency_type TEXT, -- 'direct', 'transitive'
    PRIMARY KEY (package_id, dependency_id),
    FOREIGN KEY (package_id) REFERENCES packages(id),
    FOREIGN KEY (dependency_id) REFERENCES packages(id)
);
```

**Search Result Annotation:**

When showing results from a dependency package, indicate the relationship:

```json
{
  "title": "EventLoop",
  "framework": "swift-nio",
  "source": "apple-official",
  "source_label": "Apple Official",
  "used_by": ["vapor/vapor", "hummingbird-project/hummingbird"],
  "note": "Core dependency of Vapor and Hummingbird"
}
```

**Benefits:**

1. **Complete context** - Understand full stack (Vapor → Swift NIO → Foundation)
2. **No missing docs** - If Vapor uses NIO, NIO docs are available
3. **Discover related packages** - "What else uses Swift NIO?"
4. **Avoid duplicates** - Don't re-crawl Apple packages already indexed

**Example Resolution:**

```
User: crawl vapor/vapor

Step 1: Parse vapor/vapor Package.swift
Dependencies found:
  - apple/swift-nio ✅ (Tier 1 - skip, already indexed)
  - apple/swift-log ✅ (Tier 1 - skip, already indexed)
  - vapor/routing-kit ⏳ (Not indexed - add to queue)
  - vapor/console-kit ⏳ (Not indexed - add to queue)

Step 2: Crawl vapor/vapor docs

Step 3: Crawl vapor/routing-kit
  Dependencies:
    - apple/swift-nio ✅ (skip)

Step 4: Crawl vapor/console-kit
  Dependencies:
    - apple/swift-log ✅ (skip)

Result: 3 packages indexed (vapor, routing-kit, console-kit)
        + 2 dependencies already available (swift-nio, swift-log)
```

### Challenges & Solutions

**Challenge 1: Documentation Format Variety**
- **Solution:** Support multiple formats (DocC, markdown, custom HTML)

**Challenge 2: Outdated Documentation**
- **Solution:** Track last update, mark stale docs, re-crawl periodically

**Challenge 3: Conflicting Information**
- **Solution:** Clearly label source (Apple vs third-party), rank Apple docs higher

**Challenge 4: Size Management**
- **Solution:** Only index top packages, user can request specific packages

### Automation

```bash
#!/bin/bash
# /usr/local/bin/cupertino-sync-packages

# Weekly sync of top Swift packages
cupertino crawl-packages \
  --top 50 \
  --min-stars 1000 \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party

# Rebuild index including third-party
cupertino build-index \
  --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
  --third-party-dir /Volumes/Code/DeveloperExt/appledocsucker/third-party \
  --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db

echo "✅ Synced $(ls -1 third-party | wc -l) packages"
```

---

**This makes AppleCupertino the single source of truth for ALL Swift documentation - official + ecosystem.**

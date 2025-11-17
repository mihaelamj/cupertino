# AppleCupertino - Key Constraints & Design Decisions

## Hardcoded Directory Structure

**⚠️ IMPORTANT: All paths are hardcoded - do NOT use relative paths or environment variables**

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── docs/                    # Crawled Apple documentation (markdown)
│   ├── swift/              # Framework subdirectories
│   ├── swiftui/
│   ├── uikit/
│   └── ...
├── swift-evolution/         # Swift Evolution proposals (markdown)
│   ├── 0001-*.md
│   ├── 0002-*.md
│   └── ...
├── sample-code/            # Sample code .zip files
│   ├── accelerate-*.zip
│   ├── swiftui-*.zip
│   └── ...
└── search.db               # SQLite FTS5 search index
```

**Absolute paths hardcoded in code:**
```
Base:       /Volumes/Code/DeveloperExt/cupertino
Docs:       /Volumes/Code/DeveloperExt/appledocsucker/docs
Evolution:  /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution
Samples:    /Volumes/Code/DeveloperExt/appledocsucker/sample-code
Search DB:  /Volumes/Code/DeveloperExt/appledocsucker/search.db
```

**Current contents:**
- `docs/`: 10,099+ markdown files (61 MB)
- `swift-evolution/`: 429 proposal files (8.2 MB)
- `sample-code/`: 607 .zip files (26 GB)
- `search.db`: SQLite database (~100 MB when indexed)

---

## Critical Constraints

### 1. Apple Sample Code Requires Login

**⚠️ BLOCKER:** Apple sample code downloads require Apple ID login - cannot be automated!

**Implications:**
- Cannot programmatically download samples
- Cannot re-download lost/deleted samples without manual intervention
- Must keep all existing .zip files (27GB)
- No automatic "fetch missing sample" feature possible

**Workarounds:**
1. **GitHub URLs:** Some Apple samples are open-source on GitHub
   - Can be cloned without login
   - Store both Apple URL and GitHub URL in database
   - Prefer GitHub URL when available

2. **Local Availability Tracking:**
   - Database tracks: `locally_available` (boolean)
   - Search results show: "Locally available" vs "Manual download required"
   - If not local, provide Apple URL + note about login requirement

3. **Third-Party Swift Packages:**
   - All packages from GitHub/SwiftPackageIndex CAN be automated
   - Store repository URLs for all packages
   - Can clone, index, and update automatically

### 2. Local Storage Management

**User Request:** "allow them to have it stored locally, and search results would check whether we have them downloaded, and return the appropriate result"

**Implementation:**

```sql
-- samples table includes local tracking
CREATE TABLE samples (
    slug TEXT PRIMARY KEY,
    framework TEXT,
    title TEXT,
    description TEXT,
    readme_content TEXT,
    zip_path TEXT,
    locally_available BOOLEAN DEFAULT 0,    -- Do we have the .zip?
    apple_docs_url TEXT,                     -- Requires login
    github_url TEXT,                         -- No login required (if exists)
    file_count INTEGER,
    related_docs TEXT,
    last_accessed INTEGER
);
```

**MCP Search Results:**
```json
{
  "title": "Building a Document-Based App",
  "framework": "SwiftUI",
  "description": "Create, save, and open documents...",
  "download_status": "Locally available",
  "local_path": "/Volumes/.../sample-code/swiftui-building-a-document-based-app.zip",
  "apple_url": "https://developer.apple.com/documentation/...",
  "github_url": null,
  "note": null
}
```

vs

```json
{
  "title": "Advanced SwiftUI Animation",
  "framework": "SwiftUI",
  "description": "...",
  "download_status": "Manual download required",
  "local_path": null,
  "apple_url": "https://developer.apple.com/documentation/...",
  "github_url": "https://github.com/apple/sample-swift-animations",
  "note": "Apple URL requires login. Try GitHub URL for direct access."
}
```

### 3. Swift Package URLs

**User Request:** "Did you take into account to save urls of swift packages from github"

**Implementation:**

```sql
-- packages table stores GitHub URLs
CREATE TABLE packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    owner TEXT NOT NULL,
    repository_url TEXT NOT NULL,           -- GitHub URL (e.g., https://github.com/vapor/vapor)
    documentation_url TEXT,                  -- DocC site or custom docs URL
    stars INTEGER,
    last_updated INTEGER,
    is_apple_official BOOLEAN DEFAULT 0,
    UNIQUE(owner, name)
);
```

**Package Analysis Script** (already in WARMUP.md):
- Fetches top Swift repos from GitHub
- Checks for `Package.swift` in root
- Stores repository URLs
- Identifies Apple official packages
- Checks SwiftPackageIndex availability

**MCP Search Results for Packages:**
```json
{
  "title": "Vapor Documentation",
  "framework": "Vapor",
  "source": "Community Package: vapor/vapor",
  "repository_url": "https://github.com/vapor/vapor",
  "documentation_url": "https://docs.vapor.codes",
  "stars": 24000,
  "note": "Third-party package - actively maintained"
}
```

## Storage Strategy Summary

### What We Keep

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── docs/                    ~200 MB   ✅ KEEP (markdown source, ~10K+ pages)
├── swift-evolution/         ~8.2 MB   ✅ KEEP (429 proposals)
├── sample-code/            ~26 GB    ✅ KEEP (607 .zips, cannot re-download)
├── search.db               ~100 MB   ✅ KEEP (includes all metadata + URLs)
└── third-party-packages/   ~5-10 GB  ✅ KEEP (curated packages)

Total: ~32-37 GB
```

### Sample Code Verified Details

**✅ All 607 samples have README.md files (100% coverage)**

**README Quality:**
- Detailed technical descriptions
- Code examples with syntax highlighting
- Diagrams and images
- Links to Apple documentation APIs
- Step-by-step instructions
- Perfect for FTS5 indexing

**Example README Structure:**
```markdown
# Sample Title

Brief description

## Overview
Detailed technical explanation...

## Code Examples
```swift
// Well-documented code
```

## Related Documentation
- [API Reference](https://developer.apple.com/documentation/...)
```

**Extraction Method:**
```bash
# Extract README without touching .git folders
unzip -p "sample.zip" README.md
```

**Never Extracted:**
- .git folders (remain in .zips)
- Full project contents (extract on-demand only)
- Xcode project files (not needed for search)

### What's Indexed in Database

**For Samples:**
- ✅ README summaries (searchable)
- ✅ Framework, title, description
- ✅ Local availability status
- ✅ Apple docs URL (for manual download)
- ✅ GitHub URL (when available)
- ✅ File counts, last accessed time

**For Packages:**
- ✅ GitHub repository URL
- ✅ Documentation URL (DocC or custom)
- ✅ Stars, last updated time
- ✅ Apple official flag
- ✅ Dependencies

**For Documentation:**
- ✅ Full-text search index (FTS5)
- ✅ Metadata (hashes, word counts)
- ✅ Source type (Apple/Evolution/Package)
- ❌ NOT full markdown (stored in files)

## MCP Tool Updates

### search_samples

**Returns:**
- Sample metadata
- **Download status:** "Locally available" or "Manual download required"
- Local path (if available)
- Apple docs URL (with login warning)
- GitHub URL (if available, no login)

### search_docs

**Returns:**
- Documentation content
- **Source label:** "Apple Official" or "Community Package: owner/repo"
- Package repository URL (for third-party)

### get_sample_info

**Returns:**
- Full sample details
- README summary
- **Download options:**
  1. Local .zip path (if we have it)
  2. Apple URL (requires login)
  3. GitHub URL (if exists, no login)

## Implementation Phases

### Phase 2: Sample Code Integration
- [x] Database schema with local tracking + URLs
- [x] ✅ **Verified: All 607 samples have README.md (100% coverage)**
- [ ] Index README content from existing .zips using `unzip -p`
- [ ] Parse README first paragraph as description
- [ ] Extract GitHub URLs from READMEs
- [ ] Construct Apple docs URLs from slug
- [ ] Find related documentation links in README
- [ ] MCP tools: search_samples, get_sample_info, extract_sample

### Phase 3: Third-Party Packages
- [ ] Package analysis script (identify packages)
- [ ] Store GitHub repository URLs
- [ ] Clone and index package documentation
- [ ] Dependency resolution (parse Package.swift, store URLs)

## Resolved Questions

### 1. ✅ Do samples have READMEs?
**Answer:** YES - All 607 samples have README.md files (verified 100%)
- High-quality content with code examples, diagrams, API links
- Perfect for FTS5 search indexing
- Extract with: `unzip -p "{sample}.zip" README.md`

### 2. ✅ How to avoid .git folders?
**Answer:** Never extract full contents
- Use `unzip -p` to extract README to stdout
- .git folders stay in .zips (never touched)
- Only extract specific files when agents request them

### 3. ✅ What data to index for each sample?
**Answer:** 7 key pieces of information (see "What we index" above)
1. Metadata from filename
2. Full README content
3. Description (first paragraph)
4. Apple docs URL
5. GitHub URL (if found)
6. Related docs
7. Local availability

## Open Questions

1. **Sample GitHub Discovery:**
   - Parse READMEs for GitHub links (some samples reference GitHub)
   - Try GitHub search: `https://github.com/apple/{slug}`
   - Verify repo exists before storing URL

2. **Package Documentation:**
   - Clone full repos or just fetch docs?
   - How to handle DocC archives vs custom doc sites?
   - Update frequency for third-party packages?

---

*Last updated: 2024-11-15 (README verification completed)*
*All constraints documented based on user feedback*
*Verified: All 607 samples have README.md files*

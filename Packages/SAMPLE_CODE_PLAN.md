# Sample Code Integration Plan

## Current State Analysis

**What we have:**
- 607 sample code projects downloaded as .zip files
- Filenames follow pattern: `{framework}-{description}.zip`
  - Example: `accelerate-blurring-an-image.zip`
  - Framework prefix helps categorization
  - Description is URL-slug-ified title
- Zips contain full Xcode projects with .git history
- Documentation pages reference sample code projects
- Total size: ~27GB compressed

**Filename Structure Insights:**
- Framework prefix (accelerate, swiftui, avfoundation, etc.)
- Kebab-case description matches documentation URLs
- Can be parsed to extract: framework, title, topic

## Strategic Questions

### 1. **Should agents get zipped or unzipped code?**

**Decision: EXTRACT ALL** ✅
- External SSD has 1.6TB free space
- Fast access for agents (no extraction delay)
- Can grep/search across all code
- Better developer experience

**Storage:**
- Keep .zip files (canonical source, for re-download)
- Extract all to `sample-code-extracted/`
- Strip `.git` directories to save space

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
- Base: `/Volumes/Code/DeveloperExt/appledocsucker`
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
3. ✅ Hardcode base path: `/Volumes/Code/DeveloperExt/appledocsucker`
4. ✅ Index READMEs first, full code indexing in Phase 4
5. ✅ Keep .zip files for re-download capability

## Extraction Strategy

**✅ Extraction during indexing** (Recommended)

The `appledocsucker build-index` command should:
1. Scan `sample-code/*.zip` files
2. Extract each to `sample-code-extracted/{slug}/` (if not already extracted)
3. Strip `.git` directories during extraction
4. Index README.md content
5. Build file inventory
6. Store metadata in `search.db`

**Benefits:**
- Single command for everything: `appledocsucker build-index`
- Smart: only extracts if needed (checks extracted dir existence)
- Clean: removes .git during extraction
- Integrated: extraction + indexing in one pass

**Command:**
```bash
appledocsucker build-index \
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

---

**Notes:**
- Keep zips as canonical source
- Extract on-demand to avoid 27GB+ extraction
- READMEs provide 80% of value with 1% of space
- Code access available but not required for initial value

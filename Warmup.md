# AppleCupertino - AI Assistant Warmup Guide

## Quick Context Prompts

Use these prompts to quickly get an AI assistant up to speed on this project.

### Minimal Warmup (10 seconds)

```
We're building AppleCupertino - a tool that crawls Apple documentation and makes it searchable for AI agents.

Current state:
- CLI tool: cupertino (crawling)
- MCP server: cupertino-mcp (for Claude/AI agents)
- Search indexing with SQLite FTS5
- Currently crawling ~13,000 pages

Read key files:
- DIRECTORY_STRUCTURE.md (hardcoded paths reference)
- TODO.md (comprehensive task list)
- CONSTRAINTS.md (critical constraints)

What do you want help with?
```

### Detailed Warmup (30 seconds)

```
AppleCupertino Project Overview:

Tech Stack:
- Swift 6.2
- WKWebView for JS-enabled crawling
- SQLite3 with FTS5 for search
- MCP (Model Context Protocol) for AI agents
- SwiftUI for planned GUI

Project Structure:
/Volumes/Code/DeveloperExt/work/cupertino/Packages/
├── Sources/
│   ├── CupertinoCore/      - Crawling logic
│   ├── CupertinoSearch/    - SQLite FTS5 indexing
│   ├── CupertinoLogging/   - os.log based logging
│   ├── CupertinoMCP/       - MCP server for AI agents
│   └── CupertinoCLI/       - Main CLI executable

**Data Locations (HARDCODED - do not change):**

```
/Volumes/Code/DeveloperExt/appledocsucker/
├── docs/              # Apple documentation markdown (~10K+ files, 61 MB)
├── swift-evolution/   # Swift Evolution proposals (429 files, 8.2 MB)
├── sample-code/       # Sample code .zip files (607 files, 26 GB)
└── search.db          # SQLite FTS5 search index (~100 MB)
```

**Absolute paths used everywhere:**
- Base: `/Volumes/Code/DeveloperExt/cupertino`
- Docs: `/Volumes/Code/DeveloperExt/appledocsucker/docs`
- Evolution: `/Volumes/Code/DeveloperExt/appledocsucker/swift-evolution`
- Samples: `/Volumes/Code/DeveloperExt/appledocsucker/sample-code`
- Search DB: `/Volumes/Code/DeveloperExt/appledocsucker/search.db`

**Current folder contents:**
- `docs/`: 10,099+ crawled pages (organized by framework subdirs)
- `swift-evolution/`: 429 proposal markdown files
- `sample-code/`: 607 .zip files (all have README.md - verified)
- `search.db`: SQLite database (to be rebuilt with full index)

Current Status:
- Documentation crawl: ~10,099+ pages (still running)
- Swift.org crawl: Completed (88 pages, auto-generates priority-packages.json)
- Package fetching: Integrated (fetch-packages command)
- MCP server: /usr/local/bin/cupertino-mcp
- Homebrew formula: /opt/homebrew/Library/Taps/mmj/homebrew-cupertino/Formula/cupertino.rb

Key Documents:
1. DIRECTORY_STRUCTURE.md - Hardcoded paths reference
2. TODO.md - Comprehensive task list with all phases
3. CONSTRAINTS.md - Critical constraints and design decisions
4. UPDATE_STRATEGY.md - Fast check mode and refresh strategy
5. GUI_PROPOSAL.md - Native macOS SwiftUI GUI plan (6-8 hours realistic)
6. SAMPLE_CODE_PLAN.md - Sample code integration plan (4 phases)
7. Package.swift - Swift package configuration

Read these files, then ask: What task should we work on?
```

### Full Context Warmup (1 minute)

```
AppleCupertino - Comprehensive Context

Project: Tool to crawl and index Apple developer documentation for AI agent consumption

History:
- Built in ~5 hours total
- Started Nov 14, 2024
- Current date: Nov 15, 2024
- Conversation split due to context limit

Architecture:
1. CupertinoCore
   - WebCrawler: Breadth-first crawling with WKWebView
   - HTMLToMarkdown: Multi-stage conversion with code block protection
   - Crawl metadata tracking and resume capability

2. CupertinoSearch
   - SearchIndex (Actor): SQLite3 with FTS5
   - SearchIndexBuilder: Indexes docs + Swift Evolution proposals
   - BM25 ranking with Porter stemming

3. CupertinoLogging
   - Subsystem: com.docsucker.cupertino
   - Categories: crawler, mcp, search, markdown
   - View logs: subsystem:com.docsucker.cupertino in Console.app

4. CupertinoMCP
   - MCP server for Claude Code / AI agents
   - Tools: search_docs, get_doc_content
   - Running via: /usr/local/bin/cupertino-mcp serve

5. CupertinoCLI
   - Main executable: /usr/local/bin/cupertino
   - Commands: crawl, build-index
   - Flags: --start-url, --output-dir, --max-pages, --force

Installation:
- Homebrew tap: mmj/cupertino
- Formula: /opt/homebrew/Library/Taps/mmj/homebrew-cupertino/Formula/cupertino.rb
- Installed: /usr/local/bin/{cupertino, cupertino-mcp}

Data Pipeline:
1. Crawl: Apple docs → WKWebView → HTML → Markdown
2. Index: Markdown → Parse → SQLite FTS5
3. Search: Query → FTS5 → BM25 rank → Results
4. MCP: AI agent → search_docs → JSON results

Current Crawl Status:
- Started: Nov 14, 2024 12:00 AM
- Killed: Nov 15, 2024 ~7:45 PM (at page 12,661, depth=4 in Accelerate)
- Resumed: Nov 15, 2024 ~7:47 PM from Accelerate framework
- Current pages: 11,331 (73MB)
- Current command: cupertino crawl --start-url https://developer.apple.com/documentation/accelerate --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs --max-pages 150000 --force
- Status: Running in background (bash_id: 40ae3f)
- Note: Using `--force` to rediscover pages, SHA256 change detection skips unchanged ones

Completed:
✅ CLI crawler with resume capability
✅ HTML to Markdown conversion (clean, preserves code blocks)
✅ SQLite FTS5 search indexing
✅ MCP server for AI agents
✅ Homebrew installation
✅ Swift Evolution proposal indexing (429 proposals)
✅ os.log logging with proper subsystems
✅ SwiftLint compliance (fixed all warnings)
✅ Sample code download (607 projects, 27GB)
✅ Sample README verification (100% have README.md files)

Sample Code Details (verified):
- All 607 samples have README.md files
- High-quality READMEs with code examples, diagrams, API links
- Never need to extract .git folders (stay in .zips)
- Use `unzip -p "{sample}.zip" README.md` for extraction

Planned (Not Started):
- [ ] Native macOS SwiftUI GUI (GUI_PROPOSAL.md)
- [ ] Sample code README indexing (SAMPLE_CODE_PLAN.md Phase 1-3)
  - Index README content for FTS5 search
  - Extract Apple docs URLs and GitHub URLs
  - Track local availability (all 607 are local)
  - Find related documentation links
- [ ] API-level granular indexing (SAMPLE_CODE_PLAN.md Phase 4)

Key Files to Read:
1. DIRECTORY_STRUCTURE.md - Hardcoded paths reference (read this first!)
2. TODO.md - Comprehensive task list with all phases
3. CONSTRAINTS.md - Critical constraints and design decisions
4. GUI_PROPOSAL.md - Native macOS SwiftUI GUI plan
5. SAMPLE_CODE_PLAN.md - Sample code integration plan
6. Package.swift - Swift package configuration

Important Notes:
- Hardcoded base path: /Volumes/Code/DeveloperExt/cupertino
- External SSD with 1.6TB free space
- User prefers native macOS apps, hates web GUIs
- Realistic estimates: GUI = 6-8 hours, not weeks
- Professional billable estimates: 40-60 hours (for client work)

Context from Dash Analysis:
- Dash has 678K API elements in 2GB docset
- Pre-built from Apple feeds, not crawled
- We're building for LLM consumption (clean markdown)
- Our approach: real-time crawling, always current

Now: What task should we work on?
```

## Quick Status Commands

```bash
# Check crawl progress
bash /tmp/check-crawl-progress.sh

# Check current process
ps aux | grep cupertino | grep -v grep

# View logs
log stream --predicate 'subsystem == "com.docsucker.cupertino"' --level debug

# Database stats
sqlite3 /Volumes/Code/DeveloperExt/appledocsucker/search.db "SELECT COUNT(*) FROM docs_metadata"

# Build and install
cd /Volumes/Code/DeveloperExt/work/cupertino/Packages
make build
sudo make install
```

## Common Tasks

### Task: Check Crawl Progress
```
Check progress of the documentation crawl and estimate time remaining.
Use: bash /tmp/check-crawl-progress.sh
```

### Task: Start GUI Development
```
We want to start implementing the GUI from GUI_PROPOSAL.md.
Read GUI_PROPOSAL.md first.
Start with Phase 1 (Basic GUI, 2-4 hours).
```

### Task: Implement Sample Code Indexing
```
We want to implement sample code extraction and indexing.
Read SAMPLE_CODE_PLAN.md first.
Start with Phase 1 (extraction during indexing).
```

### Task: Fix SwiftLint Issues
```
Fix SwiftLint warnings. Run swiftlint lint and fix violations.
Prefer splitting functions over disabling rules.
```

### Task: Test MCP Server
```
Test the MCP server with search_docs tool.
Server runs at: /usr/local/bin/cupertino-mcp serve
Test script: ./test-mcp-server.sh
```

### Task: Add New Feature
```
When adding features:
1. Update Package.swift if adding dependencies
2. Follow existing architecture (Actors for shared state)
3. Add os.log logging with appropriate category
4. Run swiftlint before committing
5. Update relevant .md documentation
```

## Decision Log

**Why crawl instead of using Apple's docsets?**
- Docsets are HTML for human browsing, we want clean markdown for LLMs
- Crawling gives us always-current content
- We control the format and indexing

**Why hardcode paths?**
- Project is on external SSD with specific structure
- Simplifies configuration
- Easy to change if needed

**Why native GUI instead of web?**
- User preference: hates web GUIs
- Native is faster and more integrated
- Better macOS experience

**Why XPC for CLI ↔ GUI?**
- Proper IPC on macOS
- Secure and reliable
- Allows independent processes

**Why SQLite FTS5 instead of other search?**
- Lightweight, no external dependencies
- Excellent full-text search
- Easy to distribute
- Porter stemming built-in

## User Preferences

- **Speed over perfection** - Get it working, then polish
- **Native tools** - No web GUIs, prefer native macOS
- **Realistic estimates** - Built entire tool in 5 hours
- **Direct answers** - No fluff, get to the point
- **Show code** - Examples over explanations

## How to Use This File

**Starting fresh conversation:**
1. Copy appropriate warmup prompt (minimal/detailed/full)
2. Paste into AI chat
3. AI will read referenced files
4. Continue with your task

**Mid-conversation context:**
- Point AI to specific "Common Tasks" section
- Reference "Decision Log" for "why we did X"
- Use "Quick Status Commands" to get current state

---

## Research Scripts

### Analyze Top Swift Packages

Script to identify which top Swift repos are Swift packages and should be indexed:

```bash
#!/usr/bin/env bash
# Save as: /Volumes/Code/DeveloperExt/appledocsucker/scripts/analyze-top-swift-packages.sh
set -euo pipefail

LIMIT=100
OUTPUT_DIR="/Volumes/Code/DeveloperExt/cupertino"
TIMESTAMP=$(date +%Y-%m-%d)

echo "📊 Fetching top $LIMIT Swift repos..."
gh search repos \
  'language:Swift' \
  --sort stars \
  --order desc \
  --limit "$LIMIT" \
  --json name,fullName,stargazersCount,url,description,updatedAt \
  > /tmp/top-swift-repos-raw.json

echo "🔍 Checking which ones are Swift packages..."

jq -c '.[]' /tmp/top-swift-repos-raw.json | while read -r repo; do
  fullName=$(jq -r '.fullName' <<<"$repo")
  echo "  Checking $fullName..."

  # Does this repo have Package.swift in root?
  if gh api -H "Accept: application/vnd.github+json" \
     "/repos/$fullName/contents/Package.swift" >/dev/null 2>&1; then
    kind="package"
    hasPackageSwift=true

    # Try to fetch SwiftPackageIndex info if available
    owner=$(cut -d'/' -f1 <<<"$fullName")
    repo=$(cut -d'/' -f2 <<<"$fullName")

    # Check if it's on SwiftPackageIndex
    spiURL="https://swiftpackageindex.com/$owner/$repo"
    if curl -sf -o /dev/null -I "$spiURL" 2>/dev/null; then
      onSwiftPackageIndex=true
      swiftPackageIndexURL="$spiURL"
    else
      onSwiftPackageIndex=false
      swiftPackageIndexURL=null
    fi

    # Check if it's from Apple
    if [[ "$owner" == "apple" ]]; then
      isAppleOfficial=true
    else
      isAppleOfficial=false
    fi
  else
    kind="app-or-other"
    hasPackageSwift=false
    onSwiftPackageIndex=false
    swiftPackageIndexURL=null
    isAppleOfficial=false
  fi

  jq --arg kind "$kind" \
     --argjson hasPackageSwift "$hasPackageSwift" \
     --argjson onSwiftPackageIndex "$onSwiftPackageIndex" \
     --arg swiftPackageIndexURL "$swiftPackageIndexURL" \
     --argjson isAppleOfficial "$isAppleOfficial" \
     '. + {
       kind: $kind,
       hasPackageSwift: $hasPackageSwift,
       onSwiftPackageIndex: $onSwiftPackageIndex,
       swiftPackageIndexURL: $swiftPackageIndexURL,
       isAppleOfficial: $isAppleOfficial
     }' <<<"$repo"
done | jq -s '.' > "$OUTPUT_DIR/top-swift-repos-${TIMESTAMP}.json"

# Generate summary
echo ""
echo "📈 Summary:"
jq -r '
  group_by(.kind) |
  map({kind: .[0].kind, count: length}) |
  .[] |
  "\(.kind): \(.count)"
' "$OUTPUT_DIR/top-swift-repos-${TIMESTAMP}.json"

echo ""
echo "🍎 Apple official packages:"
jq -r '.[] | select(.isAppleOfficial == true) | "  - \(.fullName) (\(.stargazersCount) ⭐)"' \
  "$OUTPUT_DIR/top-swift-repos-${TIMESTAMP}.json"

echo ""
echo "📦 Top 10 non-Apple packages:"
jq -r '.[] | select(.hasPackageSwift == true and .isAppleOfficial == false) |
  "\(.fullName) (\(.stargazersCount) ⭐)"' \
  "$OUTPUT_DIR/top-swift-repos-${TIMESTAMP}.json" | head -10

echo ""
echo "✅ Wrote: $OUTPUT_DIR/top-swift-repos-${TIMESTAMP}.json"
```

**Usage:**
```bash
cd /Volumes/Code/DeveloperExt/cupertino
chmod +x scripts/analyze-top-swift-packages.sh
./scripts/analyze-top-swift-packages.sh
```

**Output:**
- `top-swift-repos-YYYY-MM-DD.json` - Full data with metadata
- Summary showing package vs app breakdown
- List of Apple official packages
- Top 10 community packages

**Use this data to:**
1. Verify all Apple packages are in Tier 1 list
2. **MANUAL CURATION:** Update Tier 2 community packages with modern relevance
3. Identify packages on SwiftPackageIndex (easier to crawl)

**IMPORTANT: You are the curator!** High stars ≠ modern relevance.

**Exclude outdated packages (even with high stars):**
- ❌ **Alamofire** - URLSession + async/await is sufficient now
- ❌ **RxSwift** - Replaced by Swift's native async/await
- ❌ **PromiseKit** - Replaced by async/await
- ❌ **SwiftyJSON** - Codable is built-in to Swift

**Include packages that fill real gaps in 2024/2025:**
- ✅ **Vapor/Hummingbird** - Server-side Swift (unique use case)
- ✅ **TCA** (Composable Architecture) - Modern architecture pattern
- ✅ **Swift NIO** - Foundation for async networking (Apple official)
- ✅ Packages actively maintained with Swift 5.5+ features

**Curation Criteria:**
1. Active maintenance (commits in last 6 months)
2. Modern Swift (uses Swift 5.5+ concurrency, Sendable, etc.)
3. Fills a gap not covered by stdlib/Foundation
4. Actually used in production (check GitHub dependents)
5. Has good documentation worth indexing

**Create `tier2-packages.json` with:**
```json
{
  "packages": [
    {
      "owner": "vapor",
      "repo": "vapor",
      "stars": 24000,
      "rationale": "Leading server-side Swift framework, active development",
      "include": true
    },
    {
      "owner": "Alamofire",
      "repo": "Alamofire",
      "stars": 40589,
      "rationale": "URLSession + async/await replaced this for most use cases",
      "include": false
    }
  ]
}
```

---

---

## Recent Session Context (2025-01-16)

### Text-to-Speech Integration
Added macOS text-to-speech capability for AI assistant communication:
- Updated `ai-rules/mcp-tools-usage.md` with `say` command usage
- AI can now speak progress updates using `say "message"`
- No permission needed - AI speaks automatically when configured

### SwiftLint Error Resolution
Fixed all critical SwiftLint errors in project source files:

**Files Fixed:**
1. **MCPShared/JSONRPC.swift**
   - Renamed 6 single-letter variables to descriptive names
   - `v` → `boolValue`, `intValue`, `doubleValue`, `stringValue`, `arrayValue`, `dictValue`

2. **CupertinoMCPSupport/DocsResourceProvider.swift**
   - Removed trailing comma from resource templates array

3. **CupertinoSearchToolProvider/CupertinoSearchToolProvider.swift**
   - Removed trailing comma from tools array
   - Fixed 2 line length violations with multiline strings

4. **MCPTransport/MCPTransport.swift**
   - Fixed orphaned doc comment by moving into usage example block

5. **CupertinoCore/PackageFetcher.swift** (Major Refactoring)
   - Reduced `fetch()` function from 135 lines to ~20 lines
   - Reduced `fetchGitHubMetadata()` from 84 lines to ~15 lines
   - Reduced type body from 323 lines to under 250 lines
   - Extracted 15+ helper methods:
     - `setupOutputDirectory()`
     - `fetchAndSortPackageList()`
     - `processPackages()`
     - `loadCheckpointIfNeeded()`
     - `logProgress()`
     - `handleRateLimit()`
     - `handleFetchError()`
     - `applyRateLimit()`
     - `saveResults()`
     - `logCompletionSummary()`
     - `createGitHubRequest()`
     - `validateHTTPResponse()`
     - `createPackageInfo()`

6. **CupertinoCoreTests/CupertinoCoreTests.swift**
   - Refactored test function from 51 lines to ~15 lines
   - Extracted 8 helper functions for better organization

7. **CupertinoCore/HTMLToMarkdown.swift**
   - Fixed 10+ line length violations
   - Removed trailing commas
   - Improved code formatting with multiline NSRegularExpression calls

**Results:**
- Before: 346 serious errors in project files
- After: 0 errors in Sources/ directory
- Remaining violations only in `.build/checkouts` (third-party code)

**SwiftLint Commands:**
```bash
# Run SwiftLint on project sources
cd /Volumes/Code/DeveloperExt/private/cupertino/Packages
swiftlint lint --quiet Sources/

# Count violations
swiftlint lint --quiet Sources/ 2>&1 | grep "error" | wc -l
```

### AI Rules Documentation
Updated AI assistant rules with new capabilities:
- `ai-rules/mcp-tools-usage.md` - Added macOS TTS section
- All rules loaded via `ai-rules/rule-loading.md`
- Core rules: general.md, mcp-tools-usage.md, extreme-packaging.md

### Project Status
- All source code SwiftLint compliant
- Text-to-speech enabled for AI communication
- Ready for next development phase

---

*Last updated: 2025-01-16*
*Project: Cupertino - Apple Documentation Crawler & MCP Server*

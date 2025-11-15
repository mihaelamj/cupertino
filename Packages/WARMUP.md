# AppleDocsucker - AI Assistant Warmup Guide

## Quick Context Prompts

Use these prompts to quickly get an AI assistant up to speed on this project.

### Minimal Warmup (10 seconds)

```
We're building AppleDocsucker - a tool that crawls Apple documentation and makes it searchable for AI agents.

Current state:
- CLI tool: appledocsucker (crawling)
- MCP server: appledocsucker-mcp (for Claude/AI agents)
- Search indexing with SQLite FTS5
- Currently crawling ~13,000 pages

Read: /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/Package.swift
Read: /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/GUI_PROPOSAL.md
Read: /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/SAMPLE_CODE_PLAN.md

What do you want help with?
```

### Detailed Warmup (30 seconds)

```
AppleDocsucker Project Overview:

Tech Stack:
- Swift 6.2
- WKWebView for JS-enabled crawling
- SQLite3 with FTS5 for search
- MCP (Model Context Protocol) for AI agents
- SwiftUI for planned GUI

Project Structure:
/Volumes/Code/DeveloperExt/work/appledocsucker/Packages/
├── Sources/
│   ├── DocsuckerCore/      - Crawling logic
│   ├── DocsuckerSearch/    - SQLite FTS5 indexing
│   ├── DocsuckerLogging/   - os.log based logging
│   ├── DocsuckerMCP/       - MCP server for AI agents
│   └── DocsuckerCLI/       - Main CLI executable

Data Locations (hardcoded):
- Base: /Volumes/Code/DeveloperExt/appledocsucker
- Docs: $BASE/docs (markdown)
- Evolution: $BASE/swift-evolution (429 proposals)
- Samples: $BASE/sample-code (607 .zip files, ~27GB)
- Search DB: $BASE/search.db (SQLite)

Current Status:
- Documentation crawl: [CHECK PROGRESS]
- Index: 542 docs (113 Apple + 429 Swift Evolution)
- MCP server running at /usr/local/bin/appledocsucker-mcp
- Homebrew formula ready

Key Documents:
1. GUI_PROPOSAL.md - Native macOS SwiftUI GUI plan (6-8 hours realistic)
2. SAMPLE_CODE_PLAN.md - Sample code integration plan (4 phases)
3. Package.swift - Swift package configuration

Read these files, then ask: What task should we work on?
```

### Full Context Warmup (1 minute)

```
AppleDocsucker - Comprehensive Context

Project: Tool to crawl and index Apple developer documentation for AI agent consumption

History:
- Built in ~5 hours total
- Started Nov 14, 2024
- Current date: Nov 15, 2024
- Conversation split due to context limit

Architecture:
1. DocsuckerCore
   - WebCrawler: Breadth-first crawling with WKWebView
   - HTMLToMarkdown: Multi-stage conversion with code block protection
   - Crawl metadata tracking and resume capability

2. DocsuckerSearch
   - SearchIndex (Actor): SQLite3 with FTS5
   - SearchIndexBuilder: Indexes docs + Swift Evolution proposals
   - BM25 ranking with Porter stemming

3. DocsuckerLogging
   - Subsystem: com.docsucker.appledocsucker
   - Categories: crawler, mcp, search, markdown
   - View logs: subsystem:com.docsucker.appledocsucker in Console.app

4. DocsuckerMCP
   - MCP server for Claude Code / AI agents
   - Tools: search_docs, get_doc_content
   - Running via: /usr/local/bin/appledocsucker-mcp serve

5. DocsuckerCLI
   - Main executable: /usr/local/bin/appledocsucker
   - Commands: crawl, build-index
   - Flags: --start-url, --output-dir, --max-pages, --force

Installation:
- Homebrew tap: mmj/appledocsucker
- Formula: /opt/homebrew/Library/Taps/mmj/homebrew-appledocsucker/Formula/appledocsucker.rb
- Installed: /usr/local/bin/{appledocsucker, appledocsucker-mcp}

Data Pipeline:
1. Crawl: Apple docs → WKWebView → HTML → Markdown
2. Index: Markdown → Parse → SQLite FTS5
3. Search: Query → FTS5 → BM25 rank → Results
4. MCP: AI agent → search_docs → JSON results

Current Crawl Status:
- Started: Nov 15, 12:00 AM
- Rate: ~606 pages/hour
- Target: ~13,000 pages total
- ETA: ~21 hours (Nov 15, 9:30 PM)
- Command: appledocsucker --start-url https://developer.apple.com/documentation/swift --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs --max-pages 150000 --force
- Check progress: bash /tmp/check-crawl-progress.sh

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

Planned (Not Started):
- [ ] Native macOS SwiftUI GUI (GUI_PROPOSAL.md)
- [ ] Sample code extraction & indexing (SAMPLE_CODE_PLAN.md Phase 1-3)
- [ ] API-level granular indexing (SAMPLE_CODE_PLAN.md Phase 4)

Key Files to Read:
1. /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/Package.swift
2. /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/GUI_PROPOSAL.md
3. /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/SAMPLE_CODE_PLAN.md
4. /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/Sources/DocsuckerCore/WebCrawler.swift
5. /Volumes/Code/DeveloperExt/work/appledocsucker/Packages/Sources/DocsuckerSearch/SearchIndex.swift

Important Notes:
- Hardcoded base path: /Volumes/Code/DeveloperExt/appledocsucker
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
ps aux | grep appledocsucker | grep -v grep

# View logs
log stream --predicate 'subsystem == "com.docsucker.appledocsucker"' --level debug

# Database stats
sqlite3 /Volumes/Code/DeveloperExt/appledocsucker/search.db "SELECT COUNT(*) FROM docs_metadata"

# Build and install
cd /Volumes/Code/DeveloperExt/work/appledocsucker/Packages
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
Server runs at: /usr/local/bin/appledocsucker-mcp serve
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

*Last updated: 2024-11-15*
*Crawl status: In progress (~950 pages as of 1:33 AM)*

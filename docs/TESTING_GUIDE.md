# Testing Guide for Cupertino

Complete guide for testing both the CLI crawler and MCP server.

## Table of Contents

1. [CLI Testing](#cli-testing)
2. [MCP Server Testing](#mcp-server-testing)
3. [Integration Testing](#integration-testing)
4. [End-to-End Verification](#end-to-end-verification)

---

## CLI Testing

### 1. Build Verification

```bash
# Build the CLI
cd Packages
swift build --product docsucker

# Verify binary exists
ls -lh .build/debug/cupertino
```

**Expected**: Binary should be ~4.3MB

### 2. Help Command Test

```bash
.build/debug/cupertino --help
```

**Expected Output:**
```
OVERVIEW: Apple Documentation Crawler

USAGE: docsucker <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  crawl (default)         Crawl Apple documentation and save as Markdown
  crawl-evolution         Download Swift Evolution proposals from GitHub
  update                  Update existing documentation (incremental crawl)
  config                  Manage Cupertino configuration
```

### 3. Version Test

```bash
.build/debug/cupertino --version
```

**Expected**: `1.0.0`

### 4. Small Crawl Test (2-3 pages)

```bash
mkdir -p ~/docsucker-test
.build/debug/cupertino crawl \
  --start-url "https://developer.apple.com/documentation/swift/array" \
  --max-pages 3 \
  --max-depth 1 \
  --output-dir ~/docsucker-test \
  --force
```

**Expected Output:**
```
🚀 Cupertino - Apple Documentation Crawler

🚀 Starting crawl
   Start URL: https://developer.apple.com/documentation/swift/array
   Max pages: 3
   Output: ~/docsucker-test

📄 [1/3] depth=0 [swift] https://developer.apple.com/documentation/swift/array
   ✅ Saved new page: documentation_swift_array.md
   Progress: 33.3% - array

📄 [2/3] depth=1 [root] https://developer.apple.com/documentation/
   ✅ Saved new page: documentation.md
   Progress: 66.7% - documentation

📄 [3/3] depth=1 [samplecode] https://developer.apple.com/documentation/samplecode/
   ✅ Saved new page: documentation_samplecode.md
   Progress: 100.0% - samplecode

✅ Crawl completed!
📊 Statistics:
   Total pages processed: 3
   New pages: 3
   Updated pages: 0
   Skipped (unchanged): 0
   Errors: 0
   Duration: 10-20s
```

**Verification:**
```bash
# Check files were created
find ~/docsucker-test -name "*.md"

# Expected files:
# ~/docsucker-test/swift/documentation_swift_array.md
# ~/docsucker-test/root/documentation.md
# ~/docsucker-test/samplecode/documentation_samplecode.md

# Check file sizes
du -sh ~/docsucker-test
# Expected: ~50-200KB total
```

### 5. Swift Evolution Test

```bash
.build/debug/cupertino crawl-evolution \
  --output-dir ~/swift-evolution-test
```

**Expected Output:**
```
🚀 Swift Evolution Crawler

📋 Fetching proposals list...
   Found ~400 proposals

📄 [1/400] SE-0001
   ✅ Saved new proposal

...

✅ Download completed!
   Total: 400 proposals
   New: 400
   Updated: 0
   Errors: 0
   Duration: 2-5 minutes
```

**Verification:**
```bash
# Check proposals downloaded
ls ~/swift-evolution-test/SE-*.md | wc -l
# Expected: ~400 files

# Check a specific proposal
head -20 ~/swift-evolution-test/SE-0001-keywords-as-argument-labels.md
```

### 6. Incremental Update Test

```bash
# Re-run crawl (should skip unchanged pages)
.build/debug/cupertino crawl \
  --start-url "https://developer.apple.com/documentation/swift/array" \
  --max-pages 3 \
  --max-depth 1 \
  --output-dir ~/docsucker-test
```

**Expected Output:**
```
✅ Crawl completed!
📊 Statistics:
   Total pages processed: 3
   New pages: 0
   Updated pages: 0
   Skipped (unchanged): 3  ← All pages skipped!
   Errors: 0
```

### 7. Configuration Test

```bash
# Initialize config
.build/debug/cupertino config init

# Show config
.build/debug/cupertino config show
```

**Expected**: JSON configuration displayed

---

## MCP Server Testing

### 1. Build Verification

```bash
# Build the MCP server
swift build --product cupertino-mcp

# Verify binary exists
ls -lh .build/debug/cupertino-mcp
```

**Expected**: Binary should be ~4.4MB

### 2. Help Command Test

```bash
.build/debug/cupertino-mcp --help
```

**Expected Output:**
```
OVERVIEW: MCP Server for Apple Documentation and Swift Evolution

USAGE: cupertino-mcp <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  serve (default)         Start MCP server (serves docs to AI agents like Claude)
```

### 3. Startup Test

```bash
.build/debug/cupertino-mcp serve
```

**Expected Output:**
```
🚀 Cupertino MCP Server starting...
   Apple docs: /Users/username/.docsucker/docs
   Evolution: /Users/username/.docsucker/swift-evolution
   Waiting for client connection...
```

**✅ Success Indicators:**
- Server starts without crashing
- Shows correct document paths
- No error messages
- Process stays running (Ctrl+C to stop)

**❌ Common Issues:**

If you see errors about directories not found:
```bash
# Download documentation first
cupertino crawl --max-pages 10 --output-dir ~/.docsucker/docs
cupertino crawl-evolution --output-dir ~/.docsucker/swift-evolution
```

### 4. Verify Documentation Exists

```bash
# Check Apple docs
ls ~/.docsucker/docs/*/*.md | head -5

# Check Swift Evolution
ls ~/.docsucker/swift-evolution/SE-*.md | head -5
```

**Expected**: Lists of .md files

### 5. Check File Content

```bash
# View a documentation file
cat ~/docsucker-test/swift/documentation_swift_array.md | head -50
```

**Expected**: Markdown content with:
- YAML front matter (source URL, crawled date)
- Markdown headers
- Documentation content

---

## Integration Testing

### Run Automated Integration Test

```bash
# Run integration test (downloads real page)
swift test --filter testDownloadRealAppleDocPage
```

**Expected Output:**
```
🧪 Integration Test: Downloading real Apple doc page...
   URL: https://developer.apple.com/documentation/swift
   Output: /tmp/docsucker-integration-test-[UUID]

🚀 Starting crawl
   Start URL: https://developer.apple.com/documentation/swift
   Max pages: 1

📄 [1/1] depth=0 [swift] https://developer.apple.com/documentation/swift
   ✅ Saved new page: documentation_swift.md

✅ Crawl completed!
📊 Statistics:
   Total pages processed: 1
   New pages: 1
   Updated pages: 0
   Skipped (unchanged): 0
   Errors: 0
   Duration: 5-6s

   ✅ Crawled 1 page(s)
   ✅ Created markdown file: documentation_swift.md
   ✅ Content size: 10,000+ characters
   ✅ Metadata created with 1 page(s)

🎉 Integration test passed!
􁁛  Test testDownloadRealAppleDocPage() passed after 5-6 seconds.
```

### Run All Tests

```bash
swift test
```

**Expected Output:**
```
✅ 28/28 tests passed (0 failures)
- 21 SharedModels tests (IBAN validation)
- 7 MCP/Cupertino framework tests:
  ✅ testConfiguration
  ✅ testHTMLToMarkdown
  ✅ testRequestIDCoding
  ✅ testServerInitialization
  ✅ testTransportProtocol
  ✅ testCupertinoMCPSupport
  ✅ testDownloadRealAppleDocPage (integration)
```

---

## End-to-End Verification

### Complete Workflow Test

#### Step 1: Download Documentation

```bash
# Download small sample (10 pages)
.build/debug/cupertino crawl \
  --start-url "https://developer.apple.com/documentation/swift" \
  --max-pages 10 \
  --output-dir ~/.docsucker/docs
```

**✅ Success**: 10 pages downloaded, organized by framework

#### Step 2: Download Swift Evolution

```bash
.build/debug/cupertino crawl-evolution \
  --output-dir ~/.docsucker/swift-evolution
```

**✅ Success**: ~400 proposals downloaded

#### Step 3: Start MCP Server

```bash
.build/debug/cupertino-mcp serve
```

**✅ Success**: Server starts and shows "Waiting for client connection..."

#### Step 4: Configure Claude (Manual)

1. Install Claude Desktop: https://claude.ai/download

2. Edit config file:
   ```bash
   # macOS
   nano ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

3. Add configuration:
   ```json
   {
     "mcpServers": {
       "cupertino": {
         "command": "/Users/YOUR_USERNAME/.build/debug/cupertino-mcp",
         "args": ["serve"]
       }
     }
   }
   ```

4. Restart Claude Desktop

#### Step 5: Test with Claude

Open Claude Desktop and ask:

```
"Show me the documentation for Swift Array"
```

**✅ Success**: Claude responds with Array documentation from your local cache

```
"What does Swift Evolution proposal SE-0255 say?"
```

**✅ Success**: Claude shows content from SE-0255

---

## Troubleshooting

### Issue: Crawl shows 0 pages downloaded

**Solution:**
```bash
# Check internet connection
curl -I https://developer.apple.com/documentation/

# Check URL is accessible
open https://developer.apple.com/documentation/swift/array
```

### Issue: MCP server can't find documentation

**Solution:**
```bash
# Verify paths
ls ~/.docsucker/docs
ls ~/.docsucker/swift-evolution

# Use custom paths
.build/debug/cupertino-mcp serve \
  --docs-dir ~/my-docs \
  --evolution-dir ~/my-evolution
```

### Issue: Claude can't connect to MCP server

**Solutions:**

1. Check binary path:
   ```bash
   which cupertino-mcp
   # or
   realpath .build/debug/cupertino-mcp
   ```

2. Use full path in Claude config:
   ```json
   {
     "mcpServers": {
       "cupertino": {
         "command": "/Users/username/path/to/.build/debug/cupertino-mcp",
         "args": ["serve"]
       }
     }
   }
   ```

3. Check Claude logs:
   - Open Claude Desktop
   - Settings → Developer → View Logs
   - Look for "cupertino" errors

### Issue: Tests failing

**Solutions:**

```bash
# Clean and rebuild
swift package clean
swift build

# Run specific test
swift test --filter testConfiguration

# Run without integration tests
swift test --filter "test" --skip "testDownloadRealAppleDocPage"
```

---

## Quick Checklist

### Before Testing

- [ ] Swift 6.0+ installed
- [ ] macOS 15+ (required for WKWebView)
- [ ] Internet connection
- [ ] ~500MB disk space for test docs

### CLI Tests

- [ ] Build succeeds
- [ ] `--help` shows usage
- [ ] `--version` shows 1.0.0
- [ ] Small crawl (3 pages) works
- [ ] Swift Evolution download works
- [ ] Incremental update skips unchanged pages
- [ ] Config commands work

### MCP Server Tests

- [ ] Build succeeds
- [ ] Server starts without crashing
- [ ] Shows correct document paths
- [ ] Documentation files exist
- [ ] Markdown content is readable

### Integration Tests

- [ ] `swift test` passes all tests
- [ ] Integration test downloads real page
- [ ] Content size > 10KB
- [ ] Metadata file created

### End-to-End

- [ ] Download documentation
- [ ] Start MCP server
- [ ] Configure Claude
- [ ] Claude can read docs
- [ ] Claude can read proposals

---

## Performance Benchmarks

Expected performance on modern Mac (M1/M2/M3):

| Operation | Time | Size |
|-----------|------|------|
| Build CLI | 10-15s | 4.3MB |
| Build MCP | 10-15s | 4.4MB |
| Crawl 1 page | 5-6s | ~50KB |
| Crawl 10 pages | 30-60s | ~500KB |
| Crawl 100 pages | 5-10 min | ~5MB |
| Crawl 15,000 pages | 2-4 hours | 2-3GB |
| Swift Evolution | 2-5 min | 10-20MB |
| MCP server startup | <1s | 10-50MB RAM |
| Integration test | 5-6s | 11KB |

---

## Support

If tests fail:

1. Check requirements (macOS 15+, Swift 6+)
2. Run `swift package clean`
3. Check internet connection
4. Verify disk space
5. Review error messages
6. Check troubleshooting section above

For persistent issues, check:
- Xcode version: `xcodebuild -version`
- Swift version: `swift --version`
- Platform: `uname -a`

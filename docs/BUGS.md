# Cupertino - Bug List

*Generated: 2024-11-16*
*Source: Deep codebase analysis*

---

## Priority 0: Critical Bugs (Fix Immediately)

### Bug #1: Resume Detection Completely Broken
**File:** `Sources/CupertinoCLI/Commands.swift:191`
**Severity:** CRITICAL
**Impact:** Resume functionality never works, users always start from scratch

**Problem:**
```swift
guard let outputDir = URL(string: session.outputDirectory)  // BUG!
```

Uses `URL(string:)` for file paths instead of `URL(fileURLWithPath:)`. Since `session.outputDirectory` is a file path like `/Users/name/.cupertino/docs`, `URL(string:)` returns `nil` (expects URL scheme like `file://` or `http://`).

**Fix:**
```swift
guard let outputDir = URL(fileURLWithPath: session.outputDirectory)
```

**Test Case Required:** Resume detection with matching output directory

---

### Bug #2: MCP Server Blocks Indefinitely on Stdin
**File:** `Sources/MCPTransport/StdioTransport.swift:139-148`
**Severity:** CRITICAL
**Impact:** MCP server hangs waiting for input, becomes completely unresponsive

**Problem:**
```swift
#if canImport(Darwin)
// Use availableData on Darwin platforms
let data = availableData
return data.isEmpty ? nil : Data(data.prefix(count))
```

`FileHandle.availableData` **blocks** until data is available or EOF. This blocks the async read loop, making the server hang indefinitely if stdin is slow or closed.

**Fix:** Use non-blocking I/O or poll stdin before reading

**Test Case Required:** Test MCP server behavior when stdin is slow/delayed

---

### Bug #3: Crawler Page Loading Race Condition
**File:** `Sources/CupertinoCore/Crawler.swift:236-266`
**Severity:** CRITICAL
**Impact:** Page loading can hang or crash from double-resuming continuation

**Problem:**
```swift
private func loadPage(url: URL) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        webView.load(URLRequest(url: url))

        // Set timeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            continuation.resume(throwing: CrawlerError.timeout)  // Could resume twice!
        }

        // Wait for load to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            timeoutTask.cancel()
            // ... evaluateJavaScript could fail, leaving timeout running
        }
    }
}
```

Issues:
1. Fixed 5-second delay doesn't guarantee page is loaded
2. If JS evaluation fails after 5s, timeout task still runs and resumes continuation again (CRASH)
3. No actual WKWebView navigation delegate monitoring

**Fix:** Use WKNavigationDelegate properly with real completion detection

**Test Case Required:** Load slow page, verify proper timeout handling

---

### Bug #4: WKWebView Navigation Errors Cause Indefinite Hang
**File:** `Sources/CupertinoCore/Crawler.swift:410-418`
**Severity:** CRITICAL
**Impact:** Crawler hangs forever on navigation errors

**Problem:**
```swift
public func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
) {
    logError("Navigation failed: \(error.localizedDescription)")
    // Does NOT resume the continuation!
}
```

When navigation fails, the delegate only logs but never resumes the continuation waiting in `loadPage()`. The crawler hangs indefinitely.

**Fix:** Resume continuation with error

**Test Case Required:** Trigger navigation failure, verify error is thrown and crawler continues

---

### Bug #5: SearchError Enum Not Defined
**File:** `Sources/CupertinoSearch/SearchIndex.swift:165-183`
**Severity:** CRITICAL (if code compiles) / BLOCKER (if it doesn't)
**Impact:** Error handling broken or code doesn't compile

**Problem:**
```swift
throw SearchError.prepareFailed("FTS insert: \(errorMessage)")
```

`SearchError` enum is referenced but never defined anywhere in the codebase.

**Fix:** Define `SearchError` enum with appropriate cases

**Test Case Required:** Trigger SQLite error, verify proper error is thrown

---

## Priority 1: High Priority Bugs

### Bug #6: Database Connections Never Closed (Memory Leak)
**File:** `Sources/CupertinoSearch/SearchIndex.swift:41-51`
**Severity:** HIGH
**Impact:** Memory leak in long-running MCP server

**Problem:**
```swift
// Note: deinit cannot access actor-isolated properties
// SQLite connections will be closed when the process terminates
```

Actor-isolated deinit can't access `database` property. Connections rely on process termination. In long-running MCP server, if SearchIndex is recreated, connections leak.

**Fix:** Use `nonisolated deinit` (Swift 6) or lifecycle management

**Test Case Required:** Create/destroy SearchIndex multiple times, verify no connection leaks

---

### Bug #7: Auto-Save Errors Stop Entire Crawl
**File:** `Sources/CupertinoCore/Crawler.swift:113-119`
**Severity:** HIGH
**Impact:** Crawl stops completely on save failure, losing progress

**Problem:**
```swift
// Auto-save session state periodically
try await state.autoSaveIfNeeded(...)  // throws!
```

If metadata save fails (disk full, permissions, etc.), entire crawl stops. Error is caught as page error, incrementing error count without logging actual save failure.

**Fix:** Make auto-save never throw, log failures separately

**Test Case Required:** Simulate save failure, verify crawl continues

---

### Bug #8: Crawl Queue Contains Duplicates
**File:** `Sources/CupertinoCore/Crawler.swift:216-222`
**Severity:** HIGH
**Impact:** Memory waste, redundant work

**Problem:**
```swift
for link in links where shouldVisit(url: link) {
    queue.append((url: link, depth: depth + 1))  // Can add duplicates!
}
```

Same URL can be queued multiple times if linked from different pages. `shouldVisit` checks visited set but not the queue itself.

**Fix:** Check queue membership or use Set for queue tracking

**Test Case Required:** Verify no duplicate URLs in queue

---

### Bug #9: GitHub API Called Twice Per Package
**File:** `Sources/CupertinoCore/PackageFetcher.swift:257-302` and `349-366`
**Severity:** HIGH
**Impact:** Doubles GitHub API calls, hits rate limits unnecessarily

**Problem:**
```swift
// First call: Pre-fetch for sorting
let stars = try await fetchStarCount(owner: owner, repo: repo)
starCache["\(owner)/\(repo)"] = stars

// Later: Full metadata fetch
let packageInfo = try await fetchGitHubMetadata(owner: owner, repo: repo)
// Uses cached stars OR fetches again: starCache[cacheKey] ?? repoData.stargazersCount
```

For non-cached packages, this makes 2 API calls. With 10K packages, that's 20K calls vs 10K.

**Fix:** Either skip pre-fetch or ensure all packages go through it

**Test Case Required:** Verify only 1 API call per package

---

### Bug #10: Network Errors Not Retried
**File:** `Sources/CupertinoCore/PackageFetcher.swift:107-117`
**Severity:** HIGH
**Impact:** Temporary network issues cause permanent failures

**Problem:**
```swift
} catch {
    try handleFetchError(...)  // Marks as error, no retry
}
```

Configuration has `retryAttempts: Int = 3` but it's never used. Network timeouts, DNS failures, etc. are permanent.

**Fix:** Implement retry logic

**Test Case Required:** Simulate transient network error, verify retry happens

---

### Bug #21: Priority Packages Missing URL Field
**File:** `/Volumes/Code/DeveloperExt/appledocsucker/priority-packages.json`
**Severity:** HIGH
**Impact:** Package fetching will fail for priority packages

**Problem:**
```json
{
  "owner": "apple",
  "repo": "swift"
  // Missing: "url": "https://github.com/apple/swift"
}
```

Packages in `priority-packages.json` are missing the `url` field. Code that processes packages expects this field for repository access and documentation fetching.

**Fix:** Add `url` field to all package entries in priority-packages.json

**Test Case Required:** Verify priority package loading includes URL field and can construct proper repository URLs

---

## Priority 2: Medium Priority Bugs

### Bug #11: MCP Resource Listing Loads Everything Into Memory
**File:** `Sources/CupertinoMCPSupport/DocsResourceProvider.swift:22-69`
**Severity:** MEDIUM
**Impact:** OOM with large doc sets (15K+ pages)

**Problem:**
```swift
for (url, pageMetadata) in metadata.pages {
    let resource = Resource(...)
    resources.append(resource)  // 15,000 resources in memory!
}
```

MCP supports cursor-based pagination but it's not implemented. Creates all resources in memory.

**Fix:** Implement proper pagination

**Test Case Required:** List resources with 15K+ pages, verify memory usage

---

### Bug #12: URL Normalization Removes Valid Query Params
**File:** `Sources/CupertinoShared/Models.swift:174-180`
**Severity:** MEDIUM
**Impact:** Valid pages skipped due to overly aggressive normalization

**Problem:**
```swift
public static func normalize(_ url: URL) -> URL? {
    components?.fragment = nil
    components?.query = nil  // Removes ALL query params!
    return components?.url
}
```

Apple docs may use `?language=swift` vs `?language=objc` as different pages, but normalization treats them as identical.

**Fix:** Make normalization configurable or preserve important query params

**Test Case Required:** Verify language-specific URLs are not deduplicated

---

### Bug #13: Change Detection Hash Always Differs
**File:** `Sources/CupertinoCore/CrawlerState.swift:33-61` and `Crawler.swift:160-163`
**Severity:** MEDIUM
**Impact:** Everything re-crawled on updates, defeating change detection

**Problem:**
```swift
let html = try await loadPage(url: url)  // WKWebView renders with timestamps
let contentHash = HashUtilities.sha256(of: html)  // Hash includes dynamic content
```

WKWebView-rendered HTML includes timestamps, session IDs, analytics. Hash always differs even if content unchanged.

**Fix:** Extract stable content before hashing

**Test Case Required:** Crawl same page twice, verify hash matches

---

### Bug #14: Session State and Metadata Out of Sync
**File:** `Sources/CupertinoCore/CrawlerState.swift:123-146` and `85-97`
**Severity:** MEDIUM
**Impact:** Metadata corruption on crashes

**Problem:**
Two separate saves to same file:
1. `saveSessionState()` updates `metadata.crawlState`
2. `finalizeCrawl()` updates `metadata.lastCrawl` and `metadata.stats`

If auto-save happens just before finalize, or process crashes between saves, metadata is inconsistent.

**Fix:** Atomic metadata updates

**Test Case Required:** Verify metadata consistency across saves

---

### Bug #15: JSON Decode Failures Silently Swallowed
**File:** `Sources/CupertinoMCPSupport/DocsResourceProvider.swift:242` and `PackageFetcher.swift:237-244`
**Severity:** MEDIUM
**Impact:** User doesn't know their JSON files are corrupted

**Problem:**
```swift
guard let priorityList = try? JSONDecoder().decode(...) else {
    return []  // Silent failure!
}
```

Corrupted JSON files silently return empty arrays. No logging or warning.

**Fix:** Log decode failures

**Test Case Required:** Provide corrupted JSON, verify error is logged

---

### Bug #16: File Read Errors Silently Ignored
**File:** `Sources/CupertinoSearch/SearchIndexBuilder.swift:77-83`
**Severity:** MEDIUM
**Impact:** Indexing failures not reported to user

**Problem:**
```swift
guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
    skipped += 1  // Could be permission error, encoding error, etc.
    continue
}
```

Using `try?` hides real errors (permissions, encoding issues, disk errors).

**Fix:** Log read failures with error details

**Test Case Required:** Trigger read permission error, verify it's logged

---

### Bug #17: MCP Protocol Version Not Validated
**File:** `Sources/MCPServer/MCPServer.swift:210`
**Severity:** MEDIUM
**Impact:** Protocol mismatches, undefined behavior

**Problem:**
```swift
// Parse initialize params (we accept but don't validate client capabilities)
// let params = try decodeParams(InitializeRequest.Params.self, from: request.params)
```

Line is commented out! Client version and capabilities never validated.

**Fix:** Uncomment and validate protocol version

**Test Case Required:** Send incompatible protocol version, verify rejection

---

### Bug #22: Duplicate Package Files
**Files:** `packages/` vs `_docsucker/packages/`
**Severity:** MEDIUM
**Impact:** Synchronization issues, unclear data source

**Problem:**
Package data is duplicated between production directory (`packages/swift-packages-with-stars.json`) and test directory (`_docsucker/packages/swift-packages-with-stars.json`). It's unclear which is the authoritative source.

**Impact:**
- Risk of using stale or incorrect package data
- Synchronization issues if one is updated but not the other
- Wasted disk space
- Confusion about which file to update

**Fix:** Choose single authoritative location, remove duplicate, update code to reference correct path

**Test Case Required:** Verify package loading uses correct data source and doesn't fall back to duplicate

---

## Priority 3: Low Priority Issues

### Bug #18: Magic Number Constants Unexplained
**Files:** Multiple
**Severity:** LOW
**Impact:** Maintainability, unclear tuning

**Examples:**
- `autoSaveInterval: TimeInterval = 30.0` - Why 30 seconds?
- `try await Task.sleep(for: .seconds(5))` - Why 5 seconds for page load?
- `maxLength: 500` - Why 500 chars for summary?
- `if (index + 1) % 50 == 0` - Why rate limit every 50?

**Fix:** Extract to named constants with documentation

---

### Bug #19: No Cancellation Support in Long Operations
**Files:** `Crawler.swift`, `SearchIndexBuilder.swift`, `PackageFetcher.swift`
**Severity:** LOW
**Impact:** Can't stop long-running operations gracefully

**Problem:** No `Task.isCancelled` checks in loops. User must kill process.

**Fix:** Add cancellation checks

**Test Case Required:** Cancel crawl mid-way, verify clean shutdown

---

### Bug #20: Package Dependencies Table Unused
**File:** `Sources/CupertinoSearch/SearchIndex.swift:114-126`
**Severity:** LOW
**Impact:** Dead schema, wasted space

**Problem:** `package_dependencies` table created but never populated.

**Fix:** Remove schema or implement feature

---

### Bug #23: Empty JSON File
**File:** `/Volumes/Code/DeveloperExt/appledocsucker/top-swift-repos-2025-11-15.json`
**Severity:** LOW
**Impact:** Dead file, potential parsing errors

**Problem:**
File exists but is 0 bytes. If any code tries to parse it, it will fail. Creates confusion about the file's purpose.

**Fix:** Delete file or populate with actual data

**Test Case Required:** Verify no code references this file before deletion

---

## Test Coverage Plan

### Critical Tests (P0)
1. ✅ Resume detection with file paths
2. ✅ Stdin blocking behavior
3. ✅ Page load timeout and completion
4. ✅ WKWebView error handling
5. ✅ SearchError existence

### High Priority Tests (P1)
6. ✅ Database connection cleanup
7. ✅ Auto-save error handling
8. ✅ Queue deduplication
9. ✅ GitHub API call count
10. ✅ Network retry logic

### Medium Priority Tests (P2)
11. ✅ Resource listing memory usage
12. ✅ URL normalization with query params
13. ✅ Hash stability across re-crawls
14. ✅ Metadata consistency
15. ✅ JSON decode error logging

---

## Summary

- **5 Critical Bugs (P0)** - Fix immediately, could cause crashes/hangs/data loss
- **6 High Priority Bugs (P1)** - Fix soon, impact reliability and performance
- **8 Medium Priority Bugs (P2)** - Fix when possible, improve robustness
- **4 Low Priority Issues (P3)** - Technical debt, fix eventually

**Total: 23 bugs identified**

**Recently Added (from re-analysis on 2024-11-16):**
- Bug #21 (P1): Priority packages missing URL field
- Bug #22 (P2): Duplicate package files
- Bug #23 (P3): Empty JSON file

---

*Next Steps:*
1. Write tests for all P0 bugs
2. Fix P0 bugs
3. Write tests for P1 bugs
4. Fix P1 bugs
5. Continue down priority list

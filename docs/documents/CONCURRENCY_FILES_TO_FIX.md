# Files Requiring Concurrency Fixes

**Generated**: 2025-11-19
**Reference**: SWIFT_CONCURRENCY_AUDIT.md

## Priority 1: CRITICAL (Fix Immediately)

### 1. Sources/TUI/Infrastructure/Screen.swift
**Issues**: #7, #8
- Lines 20-25: `ioctl()` C interop in actor (unsafe)
- Lines 29-49: `tcgetattr()`, `tcsetattr()` C interop in actor (unsafe)
- Lines 60-72: Global stdout/stdin access in actor
**Fix**: Mark functions as `nonisolated`

### 2. Sources/Core/SampleCodeDownloader.swift
**Issues**: #2, #3
- Line 57: Missing `@Sendable` on progress closure
- Line 421: Blocking `readLine()` on `@MainActor` (CRITICAL)
**Fix**: Add `@Sendable`, move `readLine()` to detached task

### 3. Sources/TUI/PackageCurator.swift
**Issue**: #9
- Line 20-22: `AppState` shared without isolation
**Fix**: Add `@MainActor` to `AppState` class

## Priority 2: HIGH (Fix This Week)

### 4. Sources/Core/Crawler.swift
**Issue**: #1
- Line 232-237: Missing `@Sendable` on progress closure parameter
**Fix**: Add `@Sendable` to closure type

### 5. Sources/MCP/Transport/StdioTransport.swift
**Issues**: #5, #6
- Line 43: Weak self in Task
- Lines 8-9: `FileHandle` not Sendable
**Fix**: Remove weak self, add `nonisolated(unsafe)` to FileHandle

### 6. Sources/CLI/Commands/FetchCommand.swift
**Issue**: #10
- Lines 106, 271, 301, 336, 365: Progress closures not `@Sendable`
**Fix**: Add `@Sendable` to all closure parameters

## Priority 3: MEDIUM (Fix Next Sprint)

### 7. Sources/MCP/Server/MCPServer.swift
**Issue**: #4
- Line 74: Weak self anti-pattern in Task
**Fix**: Remove weak self, use task cancellation

### 8. Sources/CLI/Commands/ServeCommand.swift
**Issue**: #11
- Lines 75-77: Inefficient infinite loop with periodic sleep
**Fix**: Use `withCheckedContinuation` to wait indefinitely

## Warnings (Document/Review)

### 9. Sources/Search/SearchIndex.swift
**Warning**: #5
- Line 21: SQLite `OpaquePointer` thread safety
**Action**: Add documentation comment

### 10. Sources/MCP/Server/MCPServer.swift
**Warning**: #3
- Lines 13-15: Protocol type erasure loses Sendable checking
**Action**: Add `Sendable` constraint to protocols

### 11. Sources/Core/Crawler.swift
**Warning**: #1
- Lines 245-271: Task racing pattern for timeout
**Action**: Add documentation comment

### 12. Sources/MCP/Transport/StdioTransport.swift
**Warning**: #4
- Line 11: AsyncStream continuation not Sendable
**Action**: Verify usage is confined to actor

## Files WITHOUT Issues (Reference)

✅ Sources/Core/CrawlerState.swift - Perfect actor usage
✅ Sources/Core/PackageFetcher.swift - Good actor and Sendable conformance
✅ Sources/Search/SearchIndexBuilder.swift - Clean actor design
✅ Sources/SearchToolProvider/CupertinoSearchToolProvider.swift - Proper actor
✅ Sources/CLI/Commands/SaveCommand.swift - No concurrency issues
✅ Sources/CLI/Commands/DoctorCommand.swift - Proper async/await

## Summary

**Total Files to Fix**: 8 critical/high priority
**Critical Issues**: 4 files
**High Priority**: 2 files
**Medium Priority**: 2 files
**Documentation**: 4 files

**Estimated Effort**:
- Priority 1: 4-6 hours
- Priority 2: 2-3 hours
- Priority 3: 2-3 hours
- Total: ~10-12 hours

## Next Steps

1. Start with Priority 1 (Screen.swift, SampleCodeDownloader.swift, PackageCurator.swift)
2. Test after each fix with full test suite
3. Enable strict concurrency checking after Priority 1+2 complete
4. Document all C interop assumptions

---

**For detailed analysis and fixes, see**: SWIFT_CONCURRENCY_AUDIT.md

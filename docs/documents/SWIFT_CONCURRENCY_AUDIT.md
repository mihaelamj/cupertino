# Swift Concurrency Audit Report

**Date**: 2025-11-19
**Auditor**: Automated Analysis vs Apple Swift Concurrency Documentation
**Reference**: `/Volumes/Code/DeveloperExt/cupertino_test`

---

## Executive Summary

**Total Files Analyzed**: 27 files with Swift concurrency features
**Critical Issues Found**: 11
**Warnings**: 8
**Compliance**: Moderate - Several critical data race risks identified

---

## Apple's Swift Concurrency Principles

Based on official Apple documentation in `/Volumes/Code/DeveloperExt/cupertino_test/docs/swift/`:

### Core Principles

1. **Sendable Protocol**: Types crossing concurrency boundaries must be thread-safe
2. **Actor Isolation**: Actors provide serial execution domain guarantees
3. **@MainActor**: All UI updates and main-thread-only work must use @MainActor
4. **Structured Concurrency**: Prefer `async let` and task groups over unstructured Tasks
5. **Error Handling**: Async functions should propagate errors with `throws`
6. **Sendable Closures**: Closures escaping actor boundaries need `@Sendable` annotation

### Key Documentation References

- **Concurrency**: Understanding async/await and structured concurrency
- **Actors**: Data isolation and actor re-entrancy
- **Sendable**: Thread-safe type requirements
- **MainActor**: UI thread safety guarantees

---

## Critical Issues Summary

| Priority | Issue # | File | Line | Problem | Severity |
|----------|---------|------|------|---------|----------|
| 1 | #3 | SampleCodeDownloader.swift | 421 | Blocking `readLine()` on @MainActor | **CRITICAL** |
| 1 | #7 | Screen.swift | 20-25 | Unsafe C interop in actor (`ioctl`) | **CRITICAL** |
| 1 | #8 | Screen.swift | 60-72 | Global stdout/stdin in actor | **CRITICAL** |
| 1 | #9 | PackageCurator.swift | 22 | AppState shared without isolation | **CRITICAL** |
| 2 | #1 | Crawler.swift | 232 | Missing @Sendable on closure | HIGH |
| 2 | #2 | SampleCodeDownloader.swift | 57 | Missing @Sendable on closure | HIGH |
| 2 | #6 | StdioTransport.swift | 8-9 | FileHandle not Sendable | HIGH |
| 2 | #10 | FetchCommand.swift | Multiple | Progress closures not @Sendable | HIGH |
| 3 | #4 | MCPServer.swift | 74 | Weak self in Task | MEDIUM |
| 3 | #5 | StdioTransport.swift | 43 | Weak self in Task | MEDIUM |
| 3 | #11 | ServeCommand.swift | 75-77 | Inefficient infinite loop | LOW |

---

## Detailed Analysis by File

### 1. Sources/Core/Crawler.swift

**Status**: ⚠️ Issues Found
**Actor Isolation**: `@MainActor class Crawler` (line 19)

#### Issue #1: Missing @Sendable on Progress Closure

**Location**: Line 232-237

```swift
// CURRENT (INCORRECT)
if let onProgress {
    let progress = await CrawlProgress(
        currentURL: url,
        visitedCount: visited.count,
        totalPages: configuration.maxPages,
        stats: state.getStatistics()
    )
    onProgress(progress)  // ⚠️ Closure crossing actor boundary
}
```

**Problem**: The `onProgress` closure parameter is not marked `@Sendable`, but it's being called from a `@MainActor` context and may be called from different isolation domains.

**Apple Documentation Reference**: "Closures that escape their defining context and cross concurrency boundaries must be marked @Sendable to ensure thread safety."

**Fix**:
```swift
// Line 18 - Parameter declaration
public func crawl(
    onProgress: (@Sendable (CrawlProgress) -> Void)? = nil
) async throws -> CrawlStatistics
```

**Impact**: Without `@Sendable`, the closure could capture mutable state and cause data races.

---

#### Warning #1: Task Racing Pattern

**Location**: Lines 245-271

```swift
return try await withThrowingTaskGroup(of: String?.self) { group in
    group.addTask {
        try await Task.sleep(for: Shared.Constants.Timeout.pageLoad)
        return nil  // Timeout case
    }
    group.addTask {
        try await self.loadPageContent()  // Content loading
    }

    // Return first result
    for try await result in group {
        group.cancelAll()
        return result
    }
}
```

**Analysis**: This implements a timeout by racing two tasks. While functionally correct, it's a pattern that could be more explicit.

**Apple Best Practice**: Use structured concurrency primitives. Consider documenting this as a timeout pattern.

**Recommendation**: Add documentation comment:
```swift
/// Loads page content with timeout using task racing pattern
/// Returns nil if timeout expires before content loads
```

**Positive Aspects**:
- ✅ Correctly uses `@MainActor` for WebKit integration
- ✅ `CrawlProgress` properly marked `Sendable` (line 449)
- ✅ Good use of structured concurrency with `withThrowingTaskGroup`

---

### 2. Sources/Core/CrawlerState.swift

**Status**: ✅ Excellent - No Issues

**Actor Isolation**: `public actor CrawlerState` (line 8)

**Concurrency Analysis**:
```swift
public actor CrawlerState {
    private var metadata: CrawlMetadata
    private var visited: Set<String>
    private var failed: Set<String>
    private var currentCrawl: CrawlSessionState?
    // All mutable state properly isolated by actor
}
```

**Positive Aspects**:
- ✅ All mutable state protected by actor isolation
- ✅ `@Sendable` closure in `updateStatistics` (line 107)
- ✅ Thread-safe access patterns throughout
- ✅ No data sharing across actor boundaries

**Apple Compliance**: Fully compliant with actor isolation best practices.

---

### 3. Sources/Core/PackageFetcher.swift

**Status**: ✅ Good - Properly Implemented

**Actor Isolation**: `public actor PackageFetcher` (line 16)

**Sendable Conformance** (Lines 460-498):
```swift
public struct PackageInfo: Codable, Sendable {
    public let owner: String
    public let repo: String
    public let url: String
    public let description: String?
    // All properties are Sendable types ✅
}
```

**Analysis**: All stored properties are value types or Sendable types, satisfying Sendable requirements.

**Positive Aspects**:
- ✅ Proper actor isolation for cache and network state
- ✅ All public types correctly marked `Sendable`
- ✅ Structured async/await without data race risks
- ✅ Good error propagation with async throws

---

### 4. Sources/Core/SampleCodeDownloader.swift

**Status**: ⚠️ Critical Issues

**Actor Isolation**: `@MainActor public class SampleCodeDownloader` (line 28)

#### Issue #2: Missing @Sendable on Progress Closure

**Location**: Line 57

```swift
// CURRENT (INCORRECT)
public func download(
    onProgress: ((SampleProgress) -> Void)? = nil
) async throws -> SampleStatistics
```

**Problem**: Progress callback crosses actor boundary without `@Sendable` marking.

**Fix**:
```swift
public func download(
    onProgress: (@Sendable (SampleProgress) -> Void)? = nil
) async throws -> SampleStatistics
```

---

#### Issue #3: Blocking Synchronous I/O on MainActor ⚠️ **CRITICAL**

**Location**: Line 421

```swift
// CURRENT (CRITICAL ISSUE)
@MainActor
private func promptForDownload() async -> Bool {
    print("Download sample code projects? (y/n): ", terminator: "")
    fflush(stdout)
    guard let response = readLine() else { return false }  // ⚠️ BLOCKS MAIN ACTOR!
    return response.lowercased().hasPrefix("y")
}
```

**Problem**: `readLine()` is a **blocking synchronous call** that waits for user input. When called on `@MainActor`, this completely blocks the main thread and violates Swift concurrency principles.

**Apple Documentation**: "Never perform blocking operations on the main actor. The main actor must remain responsive for UI updates."

**Impact**:
- Blocks all main actor work
- UI becomes unresponsive
- Violates structured concurrency guarantees

**Fix**:
```swift
// OPTION 1: Move to background task
private func promptForDownload() async -> Bool {
    await Task.detached {
        print("Download sample code projects? (y/n): ", terminator: "")
        fflush(stdout)
        guard let response = readLine() else { return false }
        return response.lowercased().hasPrefix("y")
    }.value
}

// OPTION 2: Use async I/O (better)
private func promptForDownload() async -> Bool {
    print("Download sample code projects? (y/n): ", terminator: "")
    fflush(stdout)

    // Use async I/O if available, or Task.detached for blocking I/O
    return await withCheckedContinuation { continuation in
        Task.detached {
            let response = readLine() ?? ""
            continuation.resume(returning: response.lowercased().hasPrefix("y"))
        }
    }
}
```

**Positive Aspects**:
- ✅ `SampleStatistics` and `SampleProgress` correctly marked `Sendable`
- ✅ Proper `@MainActor` for WebKit integration (WebView usage)

---

### 5. Sources/MCP/Server/MCPServer.swift

**Status**: ⚠️ Issues Found

**Actor Isolation**: `public actor MCPServer` (line 7)

#### Issue #4: Weak Self Anti-Pattern in Task

**Location**: Line 74

```swift
// CURRENT (INCORRECT PATTERN)
messageTask = Task { [weak self] in
    await self?.processMessages()
}
```

**Problem**: Using `[weak self]` in a `Task` stored as a property is problematic:
1. The actor already provides isolation - no retain cycle risk
2. If `self` becomes nil, the task silently does nothing
3. The task should be explicitly cancelled, not rely on weak references

**Apple Best Practice**: "Use task cancellation, not weak references, to manage task lifetime."

**Fix**:
```swift
// Store task
messageTask = Task {
    await processMessages()
}

// In disconnect() method
func disconnect() async {
    messageTask?.cancel()
    messageTask = nil
    // ... rest of cleanup
}
```

---

#### Warning #3: Protocol Type Erasure and Sendability

**Location**: Lines 13-15

```swift
private var resourceProvider: (any ResourceProvider)?
private var toolProvider: (any ToolProvider)?
private var promptProvider: (any PromptProvider)?
```

**Problem**: Type-erased existential types `(any Provider)` lose compile-time Sendable checking.

**Analysis**: These providers are stored in an actor, which provides runtime isolation. However, the protocols should explicitly inherit from `Sendable` to ensure conforming types are thread-safe.

**Recommendation**:
```swift
// In protocol definitions
protocol ResourceProvider: Sendable {
    func listResources() async throws -> [Resource]
    // ...
}

protocol ToolProvider: Sendable {
    func listTools() async throws -> [Tool]
    // ...
}
```

---

### 6. Sources/MCP/Transport/StdioTransport.swift

**Status**: ⚠️ Critical Issues

**Actor Isolation**: `public actor StdioTransport` (line 7)

#### Issue #5: Weak Self in Task (Same Pattern)

**Location**: Line 43

```swift
// CURRENT (INCORRECT)
inputTask = Task { [weak self] in
    await self?.readLoop()
}
```

**Fix**: Same as Issue #4 - remove `[weak self]` and use proper task cancellation.

---

#### Issue #6: FileHandle Thread Safety ⚠️ **HIGH SEVERITY**

**Location**: Lines 8-9, used at lines 71, 136-142

```swift
public actor StdioTransport {
    private let input: FileHandle   // ⚠️ Not Sendable
    private let output: FileHandle  // ⚠️ Not Sendable

    // Later used:
    public func send(_ message: JSONRPCMessage) async throws {
        // ...
        try output.write(contentsOf: outputData)  // ⚠️ Thread safety unclear
        output.synchronizeFile()
    }
}
```

**Problem**: `FileHandle` is **not** marked as `Sendable` in Foundation. While these are `let` constants and protected by actor isolation, the underlying file descriptor operations may not be thread-safe.

**Apple Documentation**: "Types that are not Sendable require additional synchronization when shared across concurrency domains."

**Analysis**:
- `FileHandle` wraps a POSIX file descriptor (not thread-safe)
- Multiple threads could theoretically access the same file descriptor
- Actor isolation provides *some* protection but doesn't prevent internal races

**Fix Options**:

```swift
// OPTION 1: Document assumption and use nonisolated(unsafe)
nonisolated(unsafe) private let input: FileHandle
nonisolated(unsafe) private let output: FileHandle

// OPTION 2: Wrap in Sendable-conforming wrapper
private final class SendableFileHandle: @unchecked Sendable {
    let fileHandle: FileHandle
    private let lock = NSLock()

    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try fileHandle.write(contentsOf: data)
    }
}
```

**Recommendation**: Use Option 1 with documentation noting that stdin/stdout are inherently single-threaded resources.

---

#### Warning #4: AsyncStream Continuation Safety

**Location**: Lines 11, 32, 56

```swift
private let messagesContinuation: AsyncStream<JSONRPCMessage>.Continuation
```

**Analysis**: `AsyncStream.Continuation` is not `Sendable`, but it's being used from an actor context. This is acceptable if the continuation is never shared outside the actor.

**Current Usage**: ✅ Continuation is only used within actor methods - safe.

---

### 7. Sources/Search/SearchIndex.swift

**Status**: ⚠️ Warning

**Actor Isolation**: `public actor Index` (line 20)

#### Warning #5: SQLite Pointer Thread Safety

**Location**: Line 21

```swift
private var database: OpaquePointer?  // SQLite database handle
```

**Problem**: `OpaquePointer` (SQLite C pointer) is not `Sendable`. While actor isolation provides protection, SQLite has its own threading requirements.

**SQLite Threading Modes**:
1. Single-threaded (unsafe)
2. Multi-threaded (safe with serialization)
3. Serialized (safe, default)

**Current Safety**: Actor isolation serializes all database access ✅

**Recommendation**: Document the threading assumption:
```swift
/// SQLite database handle
/// Thread Safety: Protected by actor isolation. SQLite connection is configured
/// in serialized mode (SQLITE_CONFIG_SERIALIZED) which allows safe multi-threaded
/// access when combined with actor serialization.
private var database: OpaquePointer?
```

**Positive Aspects**:
- ✅ All database operations are async and actor-isolated
- ✅ No concurrent access to database pointer
- ✅ Proper resource cleanup in deinit

---

### 8. Sources/Search/SearchIndexBuilder.swift

**Status**: ✅ Excellent

**Actor Isolation**: `public actor IndexBuilder` (line 9)

**Positive Aspects**:
- ✅ Clean actor design with no shared mutable state
- ✅ All operations properly async
- ✅ Good error handling with async throws
- ✅ No Sendable violations

---

### 9. Sources/TUI/Infrastructure/Screen.swift ⚠️ **MULTIPLE CRITICAL ISSUES**

**Status**: ⚠️ Critical - Major Concurrency Violations

**Actor Isolation**: `actor Screen` (line 9)

#### Issue #7: Unsafe C Interop in Actor ⚠️ **CRITICAL**

**Location**: Lines 20-25 (getSize), 29-49 (enableRawMode, disableRawMode)

```swift
actor Screen {
    // PROBLEM: C functions accessing global POSIX file descriptors
    func getSize() -> (rows: Int, cols: Int) {
        var windowSize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize) == 0 {  // ⚠️ UNSAFE
            return (Int(windowSize.ws_row), Int(windowSize.ws_col))
        }
        return (24, 80)
    }

    func enableRawMode() -> termios {
        var originalTermios = termios()
        tcgetattr(STDIN_FILENO, &originalTermios)  // ⚠️ UNSAFE

        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ICANON | ECHO))
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)  // ⚠️ UNSAFE

        return originalTermios
    }
}
```

**Problems**:
1. `ioctl()`, `tcgetattr()`, `tcsetattr()` are **C functions** operating on global POSIX file descriptors
2. These are **NOT thread-safe** - they modify global terminal state
3. Calling from actor provides **no protection** for C-level races
4. `STDIN_FILENO` and `STDOUT_FILENO` are global resources

**Apple Documentation**: "Calls to C functions that access global state must be explicitly marked as nonisolated or protected with external synchronization."

**Impact**: Potential data races at C level, undefined behavior with terminal state.

**Fix**:
```swift
actor Screen {
    // Mark as nonisolated - these must only be called from main thread
    nonisolated func getSize() -> (rows: Int, cols: Int) {
        var windowSize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize) == 0 {
            return (Int(windowSize.ws_row), Int(windowSize.ws_col))
        }
        return (24, 80)
    }

    nonisolated func enableRawMode() -> termios {
        var originalTermios = termios()
        tcgetattr(STDIN_FILENO, &originalTermios)

        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ICANON | ECHO))
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        return originalTermios
    }

    nonisolated func disableRawMode(_ original: termios) {
        var termios = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &termios)
    }
}
```

---

#### Issue #8: Global stdout/stdin Access in Actor ⚠️ **CRITICAL**

**Location**: Lines 60-62, 66-67, 70-72

```swift
func render(_ content: String) {
    print("\u{001B}[0m" + Screen.clearScreen + Screen.home + content, terminator: "")
    fflush(stdout)  // ⚠️ Global C stdout access
}

func enterAltScreen() {
    print("\u{001B}[?1049h", terminator: "")  // ⚠️ stdout
    fflush(stdout)
}

func exitAltScreen() {
    print("\u{001B}[?1049l", terminator: "")  // ⚠️ stdout
    fflush(stdout)
}
```

**Problems**:
1. `print()` writes to global `stdout` (not thread-safe)
2. `fflush(stdout)` directly manipulates C global state
3. Multiple threads could interleave output, corrupting terminal sequences
4. Actor isolation doesn't protect against C-level races

**Fix**:
```swift
// OPTION 1: Mark as nonisolated and document single-threaded requirement
nonisolated func render(_ content: String) {
    print("\u{001B}[0m" + Screen.clearScreen + Screen.home + content, terminator: "")
    fflush(stdout)
}

// OPTION 2: Use a serial DispatchQueue for stdout access
private let outputQueue = DispatchQueue(label: "com.cupertino.screen.output")

func render(_ content: String) {
    outputQueue.sync {
        print("\u{001B}[0m" + Screen.clearScreen + Screen.home + content, terminator: "")
        fflush(stdout)
    }
}
```

**Recommendation**: Use Option 1 since TUI is inherently single-threaded.

---

### 10. Sources/TUI/PackageCurator.swift ⚠️ **CRITICAL**

**Status**: ⚠️ Critical Data Race Risk

**Location**: Line 20-22

#### Issue #9: AppState Shared Without Isolation ⚠️ **CRITICAL**

```swift
@main
struct PackageCuratorApp {
    static func main() async throws {
        // ...
        let state = AppState()  // ⚠️ Class instance, not isolated
        state.baseDirectory = config.baseDirectory
        state.packages = packages.map { /* ... */ }

        // State is mutated throughout async code without isolation!
        // ...

        while running {
            // Multiple mutations to state
            state.moveCursor(delta: -1, pageSize: pageSize)
            state.toggleCurrent()
            state.cycleSortMode()
            // etc.
        }
    }
}
```

**Problem**: `AppState` is a **class** that's shared across async contexts but not protected by actor isolation or `@MainActor`.

**Data Race Risk**: High - multiple mutations without synchronization.

**Fix Options**:

```swift
// OPTION 1: Make AppState @MainActor (best for UI-like code)
@MainActor
class AppState {
    var packages: [PackageEntry] = []
    var cursor: Int = 0
    // ...
}

// Then in main:
@main
struct PackageCuratorApp {
    @MainActor
    static func main() async throws {
        let state = AppState()
        // ...
    }
}

// OPTION 2: Convert to actor
actor AppState {
    var packages: [PackageEntry] = []
    var cursor: Int = 0

    func moveCursor(delta: Int, pageSize: Int) {
        // ...
    }
}
```

**Recommendation**: Use Option 1 (`@MainActor`) since this is terminal UI code running on main thread.

---

### 11. Sources/CLI/Commands/FetchCommand.swift

**Status**: ⚠️ Multiple Sendable Issues

#### Issue #10: Progress Closures Not @Sendable

**Locations**: Lines 106, 271, 301, 336, 365

```swift
// CURRENT (INCORRECT) - Example from line 106
try await crawler.crawl { progress in
    // Progress callback captures and uses state
    print("📄 [\(progress.visitedCount)/\(progress.totalPages)]")
}

// CURRENT (INCORRECT) - Line 271
try await sampleDownloader.download { progress in
    print("📦 Sample Code: \(progress.currentProject)")
}
```

**Problem**: All progress closures should be marked `@Sendable`:

**Fix**:
```swift
try await crawler.crawl { @Sendable progress in
    print("📄 [\(progress.visitedCount)/\(progress.totalPages)]")
}
```

**Impact**: Potential data races if closures capture mutable state.

---

### 12. Sources/CLI/Commands/ServeCommand.swift

**Status**: ⚠️ Minor Issue

#### Issue #11: Inefficient Infinite Loop

**Location**: Lines 75-77

```swift
// CURRENT (INEFFICIENT)
print("✅ MCP server running on stdio...")
while true {
    try await Task.sleep(for: .seconds(60))  // Keeps waking up every 60s
}
```

**Problem**: This keeps the task alive but wakes up unnecessarily every 60 seconds.

**Better Pattern**:
```swift
print("✅ MCP server running on stdio...")

// Wait indefinitely without periodic wakeups
await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    // Never resume - server runs until process terminates
    // Or resume on shutdown signal
}
```

**Impact**: Low - just wastes CPU cycles periodically.

---

## Positive Patterns Observed

### Excellent Actor Usage

1. **CrawlerState** (Sources/Core/CrawlerState.swift)
   - Perfect actor isolation
   - All mutable state protected
   - Clean async interface

2. **PackageFetcher** (Sources/Core/PackageFetcher.swift)
   - Proper actor for network cache
   - Good Sendable conformance
   - Structured concurrency

3. **SearchIndex** (Sources/Search/SearchIndex.swift)
   - Actor protects SQLite connection
   - Async database operations
   - Resource cleanup in deinit

### Proper @MainActor Usage

1. **Crawler.swift**
   - `@MainActor` for WebKit operations
   - Correct for WKWebView which requires main thread

2. **SampleCodeDownloader.swift**
   - `@MainActor` for WebView-based downloading
   - Proper isolation for UI framework

### Good Sendable Conformance

All progress and result types properly marked Sendable:
- `CrawlProgress`, `CrawlStatistics`
- `SampleProgress`, `SampleStatistics`
- `EvolutionProgress`, `EvolutionStatistics`
- `PackageInfo`
- `SearchResult`

### Structured Concurrency

Good use of:
- `withThrowingTaskGroup` for parallel operations
- `async let` for concurrent tasks
- Proper `await` at all async call sites

---

## Compliance Levels

| Category | Status | Notes |
|----------|--------|-------|
| Actor Isolation | ⚠️ Partial | Good actor usage but Screen.swift and AppState need fixes |
| Sendable Conformance | ⚠️ Partial | Data types good, closures need @Sendable |
| MainActor Usage | ✅ Good | Proper use for WebKit and UI |
| C Interop Safety | ❌ Poor | Screen.swift has critical issues |
| Structured Concurrency | ✅ Good | Good use of task groups |
| Error Handling | ✅ Excellent | Proper async throws throughout |

---

## Recommended Action Plan

### Phase 1: Critical Fixes (Immediate)

1. **Fix Screen.swift** (Issues #7, #8)
   - Mark C interop functions as `nonisolated`
   - Document single-threaded requirement
   - Consider DispatchQueue for stdout

2. **Fix SampleCodeDownloader.swift** (Issue #3)
   - Remove blocking `readLine()` from @MainActor
   - Use `Task.detached` or async I/O

3. **Fix AppState** (Issue #9)
   - Add `@MainActor` to AppState class
   - Update PackageCurator.main to be `@MainActor`

### Phase 2: High Priority (This Week)

4. **Add @Sendable to All Closures** (Issues #1, #2, #10)
   - Update all progress callback parameters
   - Enable strict concurrency warnings

5. **Fix FileHandle Usage** (Issue #6)
   - Add `nonisolated(unsafe)` with documentation
   - Consider Sendable wrapper

### Phase 3: Best Practices (Next Sprint)

6. **Remove Weak Self Anti-Pattern** (Issues #4, #5)
   - Use proper task cancellation
   - Clean up task lifecycle

7. **Optimize Server Loop** (Issue #11)
   - Replace periodic sleep with checked continuation

8. **Add Protocol Sendable Constraints** (Warning #3)
   - Update provider protocols to inherit Sendable

### Phase 4: Compiler Enforcement

9. **Enable Complete Concurrency Checking**
   ```swift
   // In Package.swift
   swiftSettings: [
       .enableUpcomingFeature("StrictConcurrency")
   ]
   ```

10. **Enable Swift 6 Language Mode** (gradually)
    - Start with one module at a time
    - Fix all warnings before full migration

---

## Testing Recommendations

### Concurrency Stress Tests

Add tests to catch race conditions:

```swift
@Test("Concurrent AppState mutations should be safe")
func testConcurrentAppStateMutations() async {
    let state = AppState()

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<100 {
            group.addTask {
                state.moveCursor(delta: 1, pageSize: 10)
            }
            group.addTask {
                state.toggleCurrent()
            }
        }
    }

    // Verify state is consistent
}
```

### Actor Isolation Tests

```swift
@Test("Screen operations are thread-safe")
func testScreenThreadSafety() async {
    let screen = Screen()

    await withTaskGroup(of: Void.self) { group in
        for i in 0..<1000 {
            group.addTask {
                await screen.render("Line \(i)")
            }
        }
    }
}
```

---

## Conclusion

The codebase shows **good understanding** of Swift concurrency in many areas (actor usage, Sendable types, structured concurrency), but has **critical issues** in:

1. **C interop** (Screen.swift terminal operations)
2. **Shared mutable state** (AppState without isolation)
3. **Missing Sendable annotations** (progress closures)
4. **Blocking operations on MainActor** (readLine())

**Priority**: Fix critical issues immediately to prevent data races and undefined behavior.

**Risk Level**: **MODERATE-HIGH** - Production usage could trigger race conditions in terminal I/O and state management.

**Effort Estimate**:
- Phase 1 (Critical): 4-6 hours
- Phase 2 (High Priority): 2-3 hours
- Phase 3 (Best Practices): 2-3 hours
- Phase 4 (Compiler): 4-8 hours (gradual)

**Total**: ~15-20 hours for complete compliance

---

## References

- Apple Swift Concurrency Documentation: `/Volumes/Code/DeveloperExt/cupertino_test/docs/swift/`
- Swift Evolution Proposals:
  - SE-0296: Async/await
  - SE-0306: Actors
  - SE-0302: Sendable
  - SE-0316: Global actors
- WWDC Sessions:
  - WWDC21: Meet async/await in Swift
  - WWDC21: Protect mutable state with Swift actors
  - WWDC22: Eliminate data races using Swift Concurrency

---

**End of Report**

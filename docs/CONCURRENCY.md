# Swift 6 Concurrency Guide

**Version:** 1.0
**Last Updated:** 2025-11-18
**Swift Version:** 6.2
**Language Mode:** Swift 6 with Strict Concurrency Checking

---

## Table of Contents

1. [Overview](#overview)
2. [Current Usage in Cupertino](#current-usage-in-cupertino)
3. [Actors and Isolation](#actors-and-isolation)
4. [Sendable and Data Race Safety](#sendable-and-data-race-safety)
5. [Async/Await Patterns](#asyncawait-patterns)
6. [Structured Concurrency](#structured-concurrency)
7. [AsyncSequence and Streaming](#asyncsequence-and-streaming)
8. [Combining Concurrency with Functional Patterns](#combining-concurrency-with-functional-patterns)
9. [Best Practices](#best-practices)
10. [Common Pitfalls](#common-pitfalls)
11. [Real Examples from Codebase](#real-examples-from-codebase)

---

## Overview

Cupertino is built with **Swift 6.2** and uses **Swift 6 language mode** with **strict concurrency checking enabled**. This provides compile-time guarantees against data races and enforces proper actor isolation.

### Why Swift 6 Concurrency?

- **Data Race Safety**: Compile-time verification prevents data races
- **Structured Concurrency**: Task hierarchies ensure proper cancellation and cleanup
- **Actor Isolation**: Automatic synchronization for mutable state
- **Sendable Protocol**: Type-safe data sharing across concurrency boundaries
- **Modern Async/Await**: Clean, readable asynchronous code

### Swift 6 Features Used in Cupertino

- ✅ `actor` types for thread-safe state management
- ✅ `@MainActor` for UI-related operations (WKWebView)
- ✅ `Sendable` protocol for safe data sharing
- ✅ `async/await` for asynchronous operations
- ✅ `Task` and `Task.detached` for structured concurrency
- ✅ `TaskGroup` for parallel operations
- ✅ `AsyncStream` for streaming data
- ✅ `isolated` parameters for explicit isolation

---

## Current Usage in Cupertino

### Concurrency Distribution

```
Actors:               12 files
@MainActor:            7 files
@Sendable:            ~50+ types
async/await:          29 files
TaskGroup:             2 files
AsyncStream:           2 files
```

### Key Actor Types

| Actor | Purpose | Location |
|-------|---------|----------|
| `MCPServer` | MCP protocol server coordination | `/Sources/MCPServer/MCPServer.swift` |
| `SearchIndex` | SQLite FTS5 search index | `/Sources/CupertinoSearch/SearchIndex.swift` |
| `CrawlerState` | Crawler metadata & session state | `/Sources/CupertinoCore/CrawlerState.swift` |
| `PackageFetcher` | Swift package metadata fetching | `/Sources/CupertinoCore/PackageFetcher.swift` |
| `StdioTransport` | Stdio transport for MCP | `/Sources/MCPTransport/StdioTransport.swift` |
| `PriorityPackageGenerator` | Priority package list generation | `/Sources/CupertinoCore/PriorityPackageGenerator.swift` |

### MainActor Usage

| Type | Purpose | Location |
|------|---------|----------|
| `DocumentationCrawler` | WKWebView-based crawler | `/Sources/CupertinoCore/Crawler.swift` |
| `SampleCodeDownloader` | Sample code downloads | `/Sources/CupertinoCore/SampleCodeDownloader.swift` |
| `SwiftEvolutionCrawler` | Evolution proposals | `/Sources/CupertinoCore/SwiftEvolutionCrawler.swift` |
| `PDFExporter` | PDF generation | `/Sources/CupertinoCore/PDFExporter.swift` |

---

## Actors and Isolation

### What is an Actor?

An **actor** is a reference type that protects its mutable state by ensuring only one task can access it at a time. All actor methods are implicitly `async` when called from outside the actor.

### When to Use Actors

Use actors when you need:
- **Mutable shared state** accessed by multiple concurrent tasks
- **Automatic synchronization** without manual locks
- **Sequential access** to prevent data races

### Real Example: MCPServer Actor

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPServer/MCPServer.swift`

```swift
/// Main MCP server implementation
/// Handles initialization, request routing, and provider management
public actor MCPServer {
    // Server information
    private let serverInfo: Implementation
    private var capabilities: ServerCapabilities

    // Providers
    private var resourceProvider: (any ResourceProvider)?
    private var toolProvider: (any ToolProvider)?
    private var promptProvider: (any PromptProvider)?

    // Transport
    private var transport: (any MCPTransport)?
    private var messageTask: Task<Void, Never>?

    // State
    private var isInitialized = false
    private var isRunning = false
    private var requestID: Int = 0

    public init(name: String, version: String) {
        serverInfo = Implementation(name: name, version: version)
        capabilities = ServerCapabilities()
    }

    // MARK: - Provider Registration

    /// Register a resource provider
    public func registerResourceProvider(_ provider: some ResourceProvider) {
        resourceProvider = provider
        updateCapabilities()
    }

    // MARK: - Server Lifecycle

    /// Connect to a transport and start the server
    public func connect(_ transport: some MCPTransport) async throws {
        guard !isRunning else {
            throw ServerError.alreadyRunning
        }

        self.transport = transport

        // Start transport
        try await transport.start()

        // Start message processing loop
        messageTask = Task { [weak self] in
            await self?.processMessages()
        }

        isRunning = true
    }
}
```

**Why an actor?**
- Multiple properties need coordinated updates (`isInitialized`, `isRunning`, `requestID`)
- State changes must be atomic (e.g., registering providers and updating capabilities)
- Concurrent requests must be serialized to maintain consistency

### Real Example: SearchIndex Actor

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoSearch/SearchIndex.swift`

```swift
/// SQLite FTS5-based full-text search index for documentation
public actor SearchIndex {
    private var database: OpaquePointer?
    private let dbPath: URL
    private var isInitialized = false

    public init(dbPath: URL = CupertinoConstants.defaultSearchDatabase) async throws {
        self.dbPath = dbPath

        // Ensure directory exists
        let directory = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try await openDatabase()
        try await createTables()
        isInitialized = true
    }

    /// Index a single document
    public func indexDocument(
        uri: String,
        framework: String,
        title: String,
        content: String,
        filePath: String,
        contentHash: String,
        lastCrawled: Date,
        sourceType: String = "apple",
        packageId: Int? = nil
    ) async throws {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        // ... SQLite operations ...
    }
}
```

**Why an actor?**
- Protects the SQLite database pointer (`OpaquePointer?`)
- Ensures serialized access to database operations
- Prevents concurrent writes that could corrupt the database

### Real Example: CrawlerState Actor

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/CrawlerState.swift`

```swift
/// Manages crawler state including metadata and change detection
public actor CrawlerState {
    private let configuration: ChangeDetectionConfiguration
    private var metadata: CrawlMetadata
    private var autoSaveInterval: TimeInterval = CupertinoConstants.Interval.autoSave
    private var lastAutoSave: Date = .init()

    public init(configuration: ChangeDetectionConfiguration) {
        self.configuration = configuration
        metadata = CrawlMetadata()

        // Load existing metadata if available
        if FileManager.default.fileExists(atPath: configuration.metadataFile.path) {
            do {
                metadata = try CrawlMetadata.load(from: configuration.metadataFile)
                CupertinoLogger.crawler.info("✅ Loaded existing metadata: \(metadata.pages.count) pages")
            } catch {
                CupertinoLogger.crawler.warning("⚠️  Failed to load metadata: \(error.localizedDescription)")
                print("   Starting with fresh metadata")
            }
        }
    }

    /// Update statistics
    public func updateStatistics(_ update: @Sendable (inout CrawlStatistics) -> Void) {
        update(&metadata.stats)
    }

    /// Auto-save if needed
    public func autoSaveIfNeeded(
        visited: Set<String>,
        queue: [(url: URL, depth: Int)],
        startURL: URL,
        outputDirectory: URL
    ) async throws {
        let now = Date()
        if now.timeIntervalSince(lastAutoSave) >= autoSaveInterval {
            try saveSessionState(visited: visited, queue: queue, startURL: startURL, outputDirectory: outputDirectory)
        }
    }
}
```

**Key patterns:**
- `@Sendable` closure for safe mutation: `updateStatistics(_ update: @Sendable (inout CrawlStatistics) -> Void)`
- Coordinated state management (metadata, lastAutoSave)
- Safe file I/O coordination

---

## Sendable and Data Race Safety

### What is Sendable?

The `Sendable` protocol indicates that a type can be safely shared across concurrency boundaries. Swift 6's strict concurrency checking enforces this at compile time.

### Types That Are Automatically Sendable

- **Value types** with all `Sendable` properties (structs, enums)
- **Immutable classes** marked with `@unchecked Sendable`
- **Actors** (inherently safe)
- **Functions** and closures marked `@Sendable`

### Real Examples: Sendable Types in Cupertino

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoShared/Models.swift`

```swift
/// Represents a single documentation page
public struct DocumentationPage: Codable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let framework: String
    public let title: String
    public let filePath: URL
    public let contentHash: String
    public let depth: Int
    public let lastCrawled: Date
}

/// Metadata for a single crawled page
public struct PageMetadata: Codable, Sendable {
    public let url: String
    public let framework: String
    public let filePath: String
    public let contentHash: String
    public let depth: Int
    public let lastCrawled: Date
}

/// Statistics for a crawl session
public struct CrawlStatistics: Codable, Sendable {
    public var totalPages: Int
    public var newPages: Int
    public var updatedPages: Int
    public var skippedPages: Int
    public var errors: Int
    public var startTime: Date?
    public var endTime: Date?
}

/// Represents a URL in the crawl queue with depth information
public struct QueuedURL: Codable, Sendable, Hashable {
    public let url: String
    public let depth: Int
}
```

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PackageFetcher.swift`

```swift
public struct PackageInfo: Codable, Sendable {
    public let owner: String
    public let repo: String
    public let stars: Int
    public let description: String?
    public let url: String
    public let archived: Bool
    public let fork: Bool
    public let updatedAt: String?
    public let language: String?
    public let license: String?
    public let error: String?
}

public struct PackageFetchStatistics: Sendable {
    public var totalPackages: Int = 0
    public var successfulFetches: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
}

public struct PackageFetchProgress: Sendable {
    public let current: Int
    public let total: Int
    public let packageName: String
    public let stats: PackageFetchStatistics

    public var percentage: Double {
        Double(current) / Double(total) * 100
    }
}
```

### Sendable Protocols

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPTransport/Transport.swift`

```swift
/// Protocol for MCP transport layers (stdio, HTTP/SSE, etc.)
public protocol MCPTransport: Sendable {
    /// Start the transport and begin accepting messages
    func start() async throws

    /// Stop the transport and clean up resources
    func stop() async throws

    /// Send a JSON-RPC message
    func send(_ message: JSONRPCMessage) async throws

    /// Receive messages from the transport
    var messages: AsyncStream<JSONRPCMessage> { get async }

    /// Check if transport is currently connected
    var isConnected: Bool { get async }
}

/// Union type for all JSON-RPC messages
public enum JSONRPCMessage: Sendable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case error(JSONRPCError)
    case notification(JSONRPCNotification)
}
```

### Sendable Closures

**Pattern from CrawlerState:**

```swift
/// Update statistics with a sendable closure
public func updateStatistics(_ update: @Sendable (inout CrawlStatistics) -> Void) {
    update(&metadata.stats)
}

// Usage:
await state.updateStatistics { stats in
    stats.errors += 1
}
```

**Why `@Sendable`?**
- The closure is executed inside the actor
- It must be safe to send across concurrency boundaries
- Prevents capturing non-Sendable state

---

## Async/Await Patterns

### Basic Async Functions

```swift
// Simple async function
public func search(
    query: String,
    framework: String? = nil,
    limit: Int = 10
) async throws -> [SearchResult] {
    guard let database else {
        throw SearchError.databaseNotInitialized
    }

    // ... perform async work ...
    return results
}
```

### Sequential Async Calls

```swift
// From Crawler.swift
try await crawlPage(url: normalizedURL, depth: depth)
try await state.autoSaveIfNeeded(
    visited: visited,
    queue: queue,
    startURL: configuration.startURL,
    outputDirectory: configuration.outputDirectory
)
```

### Async Properties

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPTransport/Transport.swift`

```swift
public protocol MCPTransport: Sendable {
    /// Receive messages from the transport
    var messages: AsyncStream<JSONRPCMessage> { get async }

    /// Check if transport is currently connected
    var isConnected: Bool { get async }
}
```

**Implementation in StdioTransport:**

```swift
public actor StdioTransport: MCPTransport {
    private let _messages: AsyncStream<JSONRPCMessage>
    private var _isConnected: Bool = false

    public var messages: AsyncStream<JSONRPCMessage> {
        get async { _messages }
    }

    public var isConnected: Bool {
        get async { _isConnected }
    }
}
```

### Awaiting in Loops

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/Crawler.swift`

```swift
// Crawl loop with async/await
while !queue.isEmpty, visited.count < configuration.maxPages {
    let (url, depth) = queue.removeFirst()

    guard let normalizedURL = URLUtilities.normalize(url),
          !visited.contains(normalizedURL.absoluteString)
    else {
        continue
    }

    visited.insert(normalizedURL.absoluteString)

    do {
        try await crawlPage(url: normalizedURL, depth: depth)
        try await state.autoSaveIfNeeded(
            visited: visited,
            queue: queue,
            startURL: configuration.startURL,
            outputDirectory: configuration.outputDirectory
        )
    } catch {
        await state.updateStatistics { $0.errors += 1 }
        logError("Error crawling \(normalizedURL.absoluteString): \(error)")
    }

    // Delay between requests
    try await Task.sleep(for: .seconds(configuration.requestDelay))
}
```

---

## Structured Concurrency

### Task Hierarchy

Structured concurrency ensures:
- **Child tasks** are automatically cancelled when parent is cancelled
- **No task leaks** - all tasks complete before scope exits
- **Error propagation** from child to parent

### Unstructured Tasks

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPServer/MCPServer.swift`

```swift
public func connect(_ transport: some MCPTransport) async throws {
    guard !isRunning else {
        throw ServerError.alreadyRunning
    }

    self.transport = transport
    try await transport.start()

    // Start message processing loop
    messageTask = Task { [weak self] in
        await self?.processMessages()
    }

    isRunning = true
}

public func disconnect() async throws {
    guard isRunning else {
        return
    }

    isRunning = false
    messageTask?.cancel()  // Cancel the task
    messageTask = nil

    try await transport?.stop()
    transport = nil
}
```

**Pattern:**
- Store `Task<Void, Never>` as property
- Use `[weak self]` to avoid retain cycles
- Cancel task in cleanup method

### Task Groups for Parallel Work

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCLI/Commands.swift`

```swift
private mutating func runAllCrawls() async throws {
    ConsoleLogger.info("📚 Crawling all documentation types in parallel:\n")
    let baseCommand = self

    try await withThrowingTaskGroup(of: (CrawlType, Result<Void, Error>).self) { group in
        // Add tasks to group
        for crawlType in CrawlType.allTypes {
            group.addTask {
                await Self.crawlSingleType(crawlType, baseCommand: baseCommand)
            }
        }

        // Collect results
        let results = try await collectCrawlResults(from: &group)
        try validateCrawlResults(results)
    }
}

private static func crawlSingleType(
    _ crawlType: CrawlType,
    baseCommand: Crawl
) async -> (CrawlType, Result<Void, Error>) {
    ConsoleLogger.info("🚀 Starting \(crawlType.displayName)...")
    var crawlCommand = baseCommand
    crawlCommand.type = crawlType
    crawlCommand.outputDir = crawlType.defaultOutputDir

    do {
        try await crawlCommand.run()
        return (crawlType, .success(()))
    } catch {
        return (crawlType, .failure(error))
    }
}

private func collectCrawlResults(
    from group: inout ThrowingTaskGroup<(CrawlType, Result<Void, Error>), Error>
) async throws -> [(CrawlType, Result<Void, Error>)] {
    var results: [(CrawlType, Result<Void, Error>)] = []
    for try await result in group {
        results.append(result)
        let (crawlType, outcome) = result
        switch outcome {
        case .success:
            ConsoleLogger.info("✅ Completed \(crawlType.displayName)")
        case .failure(let error):
            ConsoleLogger.error("❌ Failed \(crawlType.displayName): \(error)")
        }
    }
    return results
}
```

**Key patterns:**
- `withThrowingTaskGroup` for parallel tasks
- Return `Result<Void, Error>` to handle individual failures
- Collect all results before validating
- All tasks run concurrently

### Task Racing Pattern

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/Crawler.swift`

```swift
private func loadPage(url: URL) async throws -> String {
    // Use structured concurrency: proper task racing with withThrowingTaskGroup
    webView.load(URLRequest(url: url))

    // Race timeout vs page load - first to complete wins
    return try await withThrowingTaskGroup(of: String?.self) { group in
        // Task 1: Timeout task returns nil
        group.addTask {
            try await Task.sleep(for: CupertinoConstants.Timeout.pageLoad)
            return nil
        }

        // Task 2: Load page content returns HTML
        group.addTask {
            try await self.loadPageContent()
        }

        // Get first result - true racing behavior
        for try await result in group {
            if let html = result {
                // HTML loaded successfully - cancel timeout task
                group.cancelAll()
                return html
            }
            // If result is nil, timeout won - continue to next iteration
        }

        // If we get here, timeout won the race
        group.cancelAll()
        throw CrawlerError.timeout
    }
}
```

**Pattern:**
- Two tasks race: timeout vs actual work
- First to complete wins
- Loser is automatically cancelled via `group.cancelAll()`

### Task.detached for Breaking Actor Context

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PriorityPackageGenerator.swift`

```swift
private func extractGitHubPackages() async throws -> [PriorityPackageInfo] {
    var packages: [String: PriorityPackageInfo] = [:]

    // Get all markdown files using Task.detached for structured concurrency
    // FileManager.enumerator must run in synchronous context
    let allURLs: [URL] = try await Task.detached(priority: .userInitiated) { @Sendable () -> [URL] in
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: self.swiftOrgDocsPath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw PriorityPackageError.cannotReadDirectory(self.swiftOrgDocsPath.path)
        }

        // Force synchronous iteration in this detached task
        var urls: [URL] = []
        while let element = enumerator.nextObject() {
            if let fileURL = element as? URL, fileURL.pathExtension == "md" {
                urls.append(fileURL)
            }
        }
        return urls
    }.value

    // Process each file
    for fileURL in allURLs {
        // ...
    }

    return Array(packages.values).sorted { $0.owner < $1.owner }
}
```

**Why `Task.detached`?**
- `FileManager.enumerator` is synchronous and doesn't support async/await
- Detached task runs outside the actor's isolation
- Marked `@Sendable` to ensure safety
- Use `.value` to await the result

---

## AsyncSequence and Streaming

### Creating AsyncStream

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPTransport/StdioTransport.swift`

```swift
public actor StdioTransport: MCPTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var inputTask: Task<Void, Never>?
    private let messagesContinuation: AsyncStream<JSONRPCMessage>.Continuation
    private let _messages: AsyncStream<JSONRPCMessage>
    private var _isConnected: Bool = false

    public var messages: AsyncStream<JSONRPCMessage> {
        get async { _messages }
    }

    public init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) {
        self.input = input
        self.output = output

        var continuation: AsyncStream<JSONRPCMessage>.Continuation!
        _messages = AsyncStream { continuation = $0 }
        messagesContinuation = continuation
    }

    public func start() async throws {
        guard !_isConnected else {
            return
        }

        _isConnected = true

        // Start reading from stdin in background task
        inputTask = Task { [weak self] in
            await self?.readLoop()
        }
    }
}
```

### Consuming AsyncStream

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPServer/MCPServer.swift`

```swift
private func processMessages() async {
    guard let transport else {
        return
    }

    let messageStream = await transport.messages
    for await message in messageStream {
        do {
            try await handleMessage(message)
        } catch {
            logError("Error handling message: \(error)")
        }
    }
}
```

### Iterating Over AsyncSequence

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPTransport/StdioTransport.swift`

```swift
private func readLoop() async {
    var buffer = Data()

    do {
        // Use async bytes sequence (non-blocking, async iteration)
        for try await byte in input.bytes {
            guard _isConnected else {
                break
            }

            buffer.append(byte)

            // Process complete lines (newline-delimited JSON)
            if byte == 0x0a { // \n
                let lineData = Data(buffer.dropLast()) // Remove the newline

                if !lineData.isEmpty {
                    // Parse and emit message
                    do {
                        let message = try JSONRPCMessage.decode(from: lineData)
                        messagesContinuation.yield(message)
                    } catch {
                        fputs("Error decoding message: \(error)\n", stderr)
                    }
                }

                buffer.removeAll(keepingCapacity: true)
            }
        }
    } catch {
        if _isConnected {
            fputs("Error reading stdin: \(error)\n", stderr)
        }
    }

    // Clean up when loop exits
    messagesContinuation.finish()
}
```

**Pattern:**
- Use `for await` to iterate over `AsyncSequence`
- Use `yield()` to send values into the stream
- Use `finish()` to signal completion
- Graceful cancellation with `guard _isConnected`

---

## Combining Concurrency with Functional Patterns

### Result Type with Task Groups

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCLI/Commands.swift`

```swift
// Parallel crawls with Result for error handling
try await withThrowingTaskGroup(of: (CrawlType, Result<Void, Error>).self) { group in
    for crawlType in CrawlType.allTypes {
        group.addTask {
            await Self.crawlSingleType(crawlType, baseCommand: baseCommand)
        }
    }

    let results = try await collectCrawlResults(from: &group)
    try validateCrawlResults(results)
}

private static func crawlSingleType(
    _ crawlType: CrawlType,
    baseCommand: Crawl
) async -> (CrawlType, Result<Void, Error>) {
    do {
        try await crawlCommand.run()
        return (crawlType, .success(()))
    } catch {
        return (crawlType, .failure(error))
    }
}
```

**Pattern:**
- Use `Result<Success, Failure>` to capture both success and error cases
- Allows all tasks to complete even if some fail
- Collect results for post-processing
- Separate validation step

### Safe Mutation with Sendable Closures

```swift
/// Update statistics with functional mutation pattern
public func updateStatistics(_ update: @Sendable (inout CrawlStatistics) -> Void) {
    update(&metadata.stats)
}

// Usage:
await state.updateStatistics { stats in
    stats.errors += 1
    stats.totalPages += 1
}
```

**Pattern:**
- Pass mutation logic as a closure
- `@Sendable` ensures safety
- `inout` parameter for direct mutation
- Single entry point for state updates

### Concurrent Map Operations

**File:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PackageFetcher.swift`

```swift
private func sortPackagesByStars(_ packageURLs: [String], priorityURLs: [String]) async throws -> [String] {
    let prioritySet = Set(priorityURLs)
    let regularURLs = packageURLs.filter { !prioritySet.contains($0) }

    var packageStars: [(url: String, stars: Int)] = []

    // Sequential fetch with error handling
    for (index, url) in regularURLs.enumerated() {
        guard let (owner, repo) = extractOwnerRepo(from: url) else {
            packageStars.append((url, 0))
            continue
        }

        do {
            let stars = try await fetchStarCount(owner: owner, repo: repo)
            packageStars.append((url, stars))
            starCache["\(owner)/\(repo)"] = stars
        } catch {
            packageStars.append((url, 0))
            starCache["\(owner)/\(repo)"] = 0
        }

        // Rate limiting
        try await Task.sleep(for: .seconds(0.5))
    }

    // Functional transformation
    let sortedRegular = packageStars.sorted { $0.stars > $1.stars }.map(\.url)
    return priorityURLs + sortedRegular
}
```

**Pattern:**
- Sequential async operations in a loop
- Error handling with Result-like pattern (default value on error)
- Functional transformations (filter, sorted, map)
- Rate limiting with `Task.sleep`

### Parallel Batch Processing

To process items in parallel batches:

```swift
// Process in batches of 10
let batchSize = 10
for batch in packages.chunked(into: batchSize) {
    try await withThrowingTaskGroup(of: PackageInfo.self) { group in
        for package in batch {
            group.addTask {
                try await self.fetchPackageInfo(package)
            }
        }

        for try await info in group {
            results.append(info)
        }
    }

    // Rate limiting between batches
    try await Task.sleep(for: .seconds(1))
}
```

---

## Best Practices

### 1. Use Actors for Mutable Shared State

```swift
// ✅ Good: Actor protects mutable state
public actor SearchIndex {
    private var database: OpaquePointer?

    public func indexDocument(...) async throws {
        // Automatically serialized
    }
}

// ❌ Bad: Class with manual locking
public class SearchIndex {
    private var database: OpaquePointer?
    private let lock = NSLock()

    public func indexDocument(...) throws {
        lock.lock()
        defer { lock.unlock() }
        // Manual locking is error-prone
    }
}
```

### 2. Mark All Data Transfer Types as Sendable

```swift
// ✅ Good: Value type marked Sendable
public struct SearchResult: Codable, Sendable {
    public let uri: String
    public let framework: String
    public let title: String
}

// ❌ Bad: Missing Sendable conformance
public struct SearchResult: Codable {  // Compiler warning in Swift 6
    public let uri: String
}
```

### 3. Use @MainActor for UI Operations

```swift
// ✅ Good: MainActor for WKWebView
@MainActor
public final class DocumentationCrawler: NSObject {
    private var webView: WKWebView!

    public func crawl() async throws -> CrawlStatistics {
        // All methods run on main actor
        let html = try await loadPage(url: url)
        return stats
    }
}

// ❌ Bad: Background thread with WKWebView
public final class DocumentationCrawler {
    private var webView: WKWebView!  // Crash! Must be on main thread
}
```

### 4. Use Structured Concurrency

```swift
// ✅ Good: Structured concurrency with TaskGroup
try await withThrowingTaskGroup(of: Void.self) { group in
    for url in urls {
        group.addTask {
            try await self.download(url)
        }
    }
}
// All tasks complete before exiting scope

// ❌ Bad: Unstructured tasks that can leak
for url in urls {
    Task {  // These tasks can outlive the function!
        try await self.download(url)
    }
}
```

### 5. Handle Task Cancellation

```swift
// ✅ Good: Check for cancellation
for item in items {
    try Task.checkCancellation()
    await process(item)
}

// ✅ Good: Cooperative cancellation
while !queue.isEmpty {
    guard !Task.isCancelled else {
        break
    }
    await processNext()
}
```

### 6. Use Task.detached Sparingly

```swift
// ✅ Good: Detached for breaking isolation
let urls = try await Task.detached { @Sendable () -> [URL] in
    let fileManager = FileManager.default
    return fileManager.contentsOfDirectory(...)
}.value

// ❌ Bad: Unnecessary detachment
let result = try await Task.detached {
    try await self.doWork()  // Just use regular async call
}.value
```

### 7. Prefer Async Properties Over Sync Getters

```swift
// ✅ Good: Async property for actor state
public actor MyActor {
    private var _count: Int = 0

    public var count: Int {
        get async { _count }
    }
}

// ❌ Bad: Sync getter forces isolation boundary
public actor MyActor {
    public var count: Int  // Compiler error!
}
```

### 8. Use Sendable Closures in Actor Methods

```swift
// ✅ Good: Sendable closure parameter
public func updateStatistics(_ update: @Sendable (inout CrawlStatistics) -> Void) {
    update(&metadata.stats)
}

// ❌ Bad: Non-sendable closure
public func updateStatistics(_ update: (inout CrawlStatistics) -> Void) {  // Warning!
    update(&metadata.stats)
}
```

---

## Common Pitfalls

### 1. Forgetting to Mark Types as Sendable

```swift
// ❌ Problem
public struct MyData {
    public let value: String
}

actor MyActor {
    func store(_ data: MyData) {  // Warning: MyData is not Sendable
        // ...
    }
}

// ✅ Solution
public struct MyData: Sendable {
    public let value: String
}
```

### 2. Accessing Actor State Synchronously

```swift
// ❌ Problem
actor Counter {
    var count = 0
}

let counter = Counter()
print(counter.count)  // Error: actor-isolated property

// ✅ Solution
let count = await counter.count
print(count)
```

### 3. Mixing Actors and MainActor

```swift
// ❌ Problem
@MainActor
class ViewController {
    func setup() async {
        let server = MCPServer(name: "test", version: "1.0")
        try await server.connect(transport)  // OK

        // Later...
        server.registerResourceProvider(provider)  // Error! Not on main actor
    }
}

// ✅ Solution
@MainActor
class ViewController {
    func setup() async {
        let server = MCPServer(name: "test", version: "1.0")
        try await server.connect(transport)

        // Must await actor calls
        await server.registerResourceProvider(provider)
    }
}
```

### 4. Unstructured Task Leaks

```swift
// ❌ Problem - Tasks can outlive function
func startProcessing() async {
    for item in items {
        Task {  // Leaks! Function exits before tasks complete
            await process(item)
        }
    }
}  // Function returns immediately

// ✅ Solution - Use TaskGroup
func startProcessing() async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for item in items {
            group.addTask {
                await process(item)
            }
        }
    }  // Waits for all tasks to complete
}
```

### 5. Ignoring Cancellation

```swift
// ❌ Problem - Long running task ignores cancellation
func processAll() async {
    for i in 1...1000000 {
        await process(i)  // Never checks cancellation!
    }
}

// ✅ Solution - Check cancellation periodically
func processAll() async throws {
    for i in 1...1000000 {
        try Task.checkCancellation()  // Throws if cancelled
        await process(i)
    }
}
```

### 6. Creating Retain Cycles with Unstructured Tasks

```swift
// ❌ Problem - Strong reference cycle
class MyClass {
    var task: Task<Void, Never>?

    func start() {
        task = Task {
            await self.doWork()  // Strong reference to self!
        }
    }
}

// ✅ Solution - Use [weak self]
class MyClass {
    var task: Task<Void, Never>?

    func start() {
        task = Task { [weak self] in
            await self?.doWork()
        }
    }
}
```

### 7. Not Finishing AsyncStream Continuation

```swift
// ❌ Problem - Stream never finishes
actor Producer {
    var continuation: AsyncStream<Int>.Continuation?

    func start() {
        continuation?.yield(42)
        // Never calls continuation.finish()!
    }
}

// ✅ Solution - Always finish streams
actor Producer {
    var continuation: AsyncStream<Int>.Continuation?

    func start() {
        continuation?.yield(42)
    }

    func stop() {
        continuation?.finish()  // Signal completion
    }
}
```

---

## Real Examples from Codebase

### Example 1: Actor-Based Server with Transport

**Location:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPServer/MCPServer.swift`

**Pattern:** Actor coordinating multiple async resources

```swift
public actor MCPServer {
    private var transport: (any MCPTransport)?
    private var messageTask: Task<Void, Never>?
    private var isRunning = false

    public func connect(_ transport: some MCPTransport) async throws {
        self.transport = transport
        try await transport.start()

        messageTask = Task { [weak self] in
            await self?.processMessages()
        }

        isRunning = true
    }

    private func processMessages() async {
        guard let transport else { return }

        let messageStream = await transport.messages
        for await message in messageStream {
            do {
                try await handleMessage(message)
            } catch {
                logError("Error handling message: \(error)")
            }
        }
    }

    public func disconnect() async throws {
        isRunning = false
        messageTask?.cancel()
        messageTask = nil
        try await transport?.stop()
    }
}
```

**Key concepts:**
- Actor for server state management
- Unstructured task for background message processing
- AsyncStream consumption
- Proper cleanup with cancellation

### Example 2: AsyncStream for I/O

**Location:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/MCPTransport/StdioTransport.swift`

**Pattern:** AsyncStream for reading stdin

```swift
public actor StdioTransport: MCPTransport {
    private let messagesContinuation: AsyncStream<JSONRPCMessage>.Continuation
    private let _messages: AsyncStream<JSONRPCMessage>

    public var messages: AsyncStream<JSONRPCMessage> {
        get async { _messages }
    }

    public init() {
        var continuation: AsyncStream<JSONRPCMessage>.Continuation!
        _messages = AsyncStream { continuation = $0 }
        messagesContinuation = continuation
    }

    private func readLoop() async {
        for try await byte in input.bytes {
            guard _isConnected else { break }

            buffer.append(byte)

            if byte == 0x0a {
                let message = try JSONRPCMessage.decode(from: lineData)
                messagesContinuation.yield(message)
                buffer.removeAll()
            }
        }

        messagesContinuation.finish()
    }
}
```

**Key concepts:**
- AsyncStream for streaming data
- Continuation for yielding values
- Graceful termination with `finish()`

### Example 3: TaskGroup for Parallel Work with Result

**Location:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCLI/Commands.swift`

**Pattern:** Parallel crawls with error aggregation

```swift
try await withThrowingTaskGroup(of: (CrawlType, Result<Void, Error>).self) { group in
    for crawlType in CrawlType.allTypes {
        group.addTask {
            await Self.crawlSingleType(crawlType, baseCommand: baseCommand)
        }
    }

    var results: [(CrawlType, Result<Void, Error>)] = []
    for try await result in group {
        results.append(result)
        let (crawlType, outcome) = result
        switch outcome {
        case .success:
            ConsoleLogger.info("✅ Completed \(crawlType.displayName)")
        case .failure(let error):
            ConsoleLogger.error("❌ Failed \(crawlType.displayName): \(error)")
        }
    }

    // Validate after all complete
    let failures = results.filter { if case .failure = $0.1 { return true }; return false }
    if !failures.isEmpty {
        throw ExitCode.failure
    }
}
```

**Key concepts:**
- TaskGroup for parallel execution
- Result type to handle individual failures
- Collect all results before throwing
- Allows partial success

### Example 4: Task Racing for Timeout

**Location:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/Crawler.swift`

**Pattern:** Race page load against timeout

```swift
private func loadPage(url: URL) async throws -> String {
    webView.load(URLRequest(url: url))

    return try await withThrowingTaskGroup(of: String?.self) { group in
        // Timeout task
        group.addTask {
            try await Task.sleep(for: .seconds(30))
            return nil
        }

        // Page load task
        group.addTask {
            try await self.loadPageContent()
        }

        // First to complete wins
        for try await result in group {
            if let html = result {
                group.cancelAll()
                return html
            }
        }

        group.cancelAll()
        throw CrawlerError.timeout
    }
}
```

**Key concepts:**
- TaskGroup for racing
- First result wins
- Automatic cancellation of loser
- Structured timeout pattern

### Example 5: MainActor for WKWebView

**Location:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/Crawler.swift`

**Pattern:** MainActor class calling actor methods

```swift
@MainActor
public final class DocumentationCrawler: NSObject {
    private let state: CrawlerState  // Actor
    private var webView: WKWebView!

    public func crawl() async throws -> CrawlStatistics {
        while !queue.isEmpty {
            let (url, depth) = queue.removeFirst()

            // Calling actor methods with await
            try await crawlPage(url: normalizedURL, depth: depth)
            try await state.autoSaveIfNeeded(
                visited: visited,
                queue: queue,
                startURL: configuration.startURL,
                outputDirectory: configuration.outputDirectory
            )
        }

        var finalStats = await state.getStatistics()
        return finalStats
    }

    private func loadPageContent() async throws -> String {
        // WKWebView API requires MainActor
        try await webView.evaluateJavaScript(
            "document.documentElement.outerHTML",
            in: nil,
            contentWorld: .page
        )
    }
}
```

**Key concepts:**
- `@MainActor` for WKWebView requirements
- Calling actor methods with `await`
- Mixing MainActor and regular actors
- Coordinated state management

### Example 6: Task.detached for Sync APIs

**Location:** `/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PriorityPackageGenerator.swift`

**Pattern:** Breaking actor isolation for FileManager

```swift
public actor PriorityPackageGenerator {
    private func extractGitHubPackages() async throws -> [PriorityPackageInfo] {
        // FileManager.enumerator is synchronous - use Task.detached
        let allURLs: [URL] = try await Task.detached(priority: .userInitiated) { @Sendable () -> [URL] in
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: self.swiftOrgDocsPath,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw PriorityPackageError.cannotReadDirectory(self.swiftOrgDocsPath.path)
            }

            var urls: [URL] = []
            while let element = enumerator.nextObject() {
                if let fileURL = element as? URL, fileURL.pathExtension == "md" {
                    urls.append(fileURL)
                }
            }
            return urls
        }.value

        // Process results back in actor context
        for fileURL in allURLs {
            // ...
        }
    }
}
```

**Key concepts:**
- `Task.detached` for synchronous APIs
- `@Sendable` closure requirement
- `.value` to await result
- Return to actor context for processing

---

## Summary

Cupertino leverages Swift 6 concurrency features extensively:

✅ **Actors** for thread-safe state management (12+ actors)
✅ **@MainActor** for UI operations (WKWebView)
✅ **Sendable** for safe data sharing (50+ types)
✅ **Async/await** for clean asynchronous code
✅ **TaskGroup** for parallel operations
✅ **AsyncStream** for I/O streaming
✅ **Result types** for error aggregation in parallel tasks
✅ **Task.detached** for breaking isolation when needed

### Key Takeaways

1. **Use actors** instead of manual locking
2. **Mark all data types** as `Sendable`
3. **Prefer structured concurrency** over unstructured tasks
4. **Use TaskGroup** for parallel work
5. **Combine Result with TaskGroup** for graceful error handling
6. **AsyncStream** for producer/consumer patterns
7. **@MainActor** for UI-related code
8. **Task.detached** sparingly for sync APIs

---

## Further Reading

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Swift Evolution SE-0296: Async/await](https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md)
- [Swift Evolution SE-0306: Actors](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- [Swift Evolution SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-sendable-and-sendable-closures.md)
- [WWDC 2021: Meet async/await in Swift](https://developer.apple.com/videos/play/wwdc2021/10132/)
- [WWDC 2021: Protect mutable state with Swift actors](https://developer.apple.com/videos/play/wwdc2021/10133/)

---

**Document Version:** 1.0
**Created:** 2025-11-18
**Author:** Claude (Anthropic)
**Project:** Cupertino - Apple Documentation CLI & MCP Server

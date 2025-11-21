# Swift Structured Concurrency - Comprehensive Reference Guide

**Extracted from Apple Developer Documentation**
**Source:** `/Volumes/Code/DeveloperExt/cupertinodocs/docs/swift/`
**Last Updated:** 2025-11-21
**Swift Version:** 6.0+

---

## Table of Contents

1. [Introduction to Swift Concurrency](#introduction)
2. [Core Concepts](#core-concepts)
3. [Tasks](#tasks)
4. [Actors](#actors)
5. [AsyncStream & AsyncSequence](#asyncstream)
6. [Task Groups](#task-groups)
7. [Sendable Protocol](#sendable)
8. [MainActor](#mainactor)
9. [Task Executors](#executors)
10. [Best Practices](#best-practices)
11. [Performance Considerations](#performance)
12. [Migration Guide](#migration)
13. [API Reference](#api-reference)

---

## <a name="introduction"></a>1. Introduction to Swift Concurrency

Swift's structured concurrency model provides a safe, efficient way to write concurrent code. Introduced in Swift 5.5 and refined through Swift 6, it replaces traditional callback-based and GCD-based approaches with language-level features.

### Key Benefits

- **Safety:** Compiler-enforced data race prevention
- **Clarity:** Sequential-looking code for asynchronous operations
- **Structure:** Clear task hierarchies and automatic cancellation
- **Performance:** Cooperative task scheduling on thread pools
- **Debugging:** Better stack traces and error propagation

### The Building Blocks

```
┌─────────────────────────────────────────┐
│         Swift Concurrency Stack         │
├─────────────────────────────────────────┤
│  async/await (Language Syntax)          │
│  ↓                                      │
│  Tasks (Execution Units)                │
│  ↓                                      │
│  Actors (Synchronization)               │
│  ↓                                      │
│  Executors (Scheduling)                 │
│  ↓                                      │
│  Thread Pool (Runtime)                  │
└─────────────────────────────────────────┘
```

---

## <a name="core-concepts"></a>2. Core Concepts

### async/await

The foundation of Swift concurrency. Functions marked `async` can suspend execution without blocking threads.

```swift
func fetchUser(id: String) async throws -> User {
    let data = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data.0)
}

// Call site
let user = try await fetchUser(id: "123")
```

**Key Points:**
- `await` marks suspension points where control can be yielded
- Suspension doesn't block the thread
- Thread may be different after resumption
- Maintains sequential code flow

### Structured Concurrency

All async work is organized into a hierarchy of tasks:

```
Parent Task
├─── Child Task 1
│    ├─── Grandchild Task 1a
│    └─── Grandchild Task 1b
└─── Child Task 2
```

**Rules:**
1. Parent task waits for all children to complete
2. Canceling parent cancels all children
3. Child task failure can propagate to parent
4. Structured scoping with `async let` and `withTaskGroup`

### Sendable

Types that can safely cross concurrency boundaries:

```swift
// Sendable types
struct User: Sendable {
    let id: String
    let name: String
}

// Non-Sendable (has mutable state)
class Counter {
    var value = 0 // ❌ Not Sendable
}

// Sendable with @unchecked (use cautiously)
class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
```

---

## <a name="tasks"></a>3. Tasks

### Task Anatomy

```swift
@frozen
struct Task<Success, Failure> where Success: Sendable, Failure: Error
```

A `Task` represents a unit of asynchronous work.

### Task Lifecycle

```
Created → Running → Suspended ⇄ Running → Completed
                                          ↓
                                   Success or Failure
```

### Task Creation Patterns

#### 1. Structured Tasks (async let)

```swift
async let user = fetchUser(id: "123")
async let posts = fetchPosts(userId: "123")
async let friends = fetchFriends(userId: "123")

// Implicitly awaits all
let profile = Profile(
    user: await user,
    posts: await posts,
    friends: await friends
)
```

**Characteristics:**
- Child task of current task
- Automatic cancellation propagation
- Waits at scope exit

#### 2. Unstructured Tasks

```swift
class DataService {
    private var syncTask: Task<Void, Never>?

    func startSync() {
        syncTask = Task {
            while !Task.isCancelled {
                await performSync()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopSync() {
        syncTask?.cancel()
        syncTask = nil
    }
}
```

**Characteristics:**
- Inherits context (actor, priority)
- Manual lifetime management
- Must explicitly cancel

#### 3. Detached Tasks

```swift
Task.detached(priority: .background) {
    await performIndependentWork()
}
```

**Characteristics:**
- No context inheritance
- Completely independent
- Use sparingly (breaks structure)

### Task Priority

```swift
public enum TaskPriority: Int, Sendable {
    case background = 0
    case utility = 1
    case userInitiated = 2
    case high = 3
}
```

**Priority Escalation:**
- If high-priority task awaits low-priority task, low is escalated
- Prevents priority inversion
- Automatic and transparent

### Task Cancellation

#### Checking for Cancellation

```swift
func processItems(_ items: [Item]) async throws {
    for item in items {
        // Method 1: Throw if cancelled
        try Task.checkCancellation()

        // Method 2: Check boolean
        guard !Task.isCancelled else {
            return
        }

        await process(item)
    }
}
```

#### Cooperative Cancellation

```swift
func downloadFile(url: URL) async throws -> Data {
    let task = URLSession.shared.dataTask(with: url)

    // Set up cancellation handler
    try await withTaskCancellationHandler {
        return try await task.value
    } onCancel: {
        task.cancel()
    }
}
```

### Task Local Values

```swift
enum Logger {
    @TaskLocal static var requestID: String?
}

func handleRequest() async {
    await Logger.$requestID.withValue("req-123") {
        await processRequest() // Can access Logger.requestID
    }
}
```

---

## <a name="actors"></a>4. Actors

### Actor Definition

Actors provide synchronized access to mutable state:

```swift
actor BankAccount {
    private var balance: Double
    private let accountNumber: String

    init(accountNumber: String, initialBalance: Double) {
        self.accountNumber = accountNumber
        self.balance = initialBalance
    }

    func deposit(_ amount: Double) {
        balance += amount
    }

    func withdraw(_ amount: Double) throws {
        guard balance >= amount else {
            throw BankError.insufficientFunds
        }
        balance -= amount
    }

    func getBalance() -> Double {
        balance
    }

    // Non-isolated (synchronous, no data race protection)
    nonisolated func getAccountNumber() -> String {
        accountNumber // OK: let property
    }
}
```

### Actor Protocol

```swift
public protocol Actor: AnyObject, Sendable {
    nonisolated var unownedExecutor: UnownedSerialExecutor { get }
}
```

All `actor` types implicitly conform to `Actor` protocol.

### Actor Isolation

```swift
actor Counter {
    private var value = 0

    func increment() {
        value += 1 // Synchronous within actor
    }
}

let counter = Counter()
await counter.increment() // Async from outside
```

**Isolation Rules:**
1. Actor methods can synchronously access actor state
2. External access requires `await`
3. Actor properties cannot be directly accessed externally
4. `nonisolated` members have no isolation

### Actor Reentrancy

**Critical Concept:** Actors can be reentered at suspension points!

```swift
actor Account {
    private var balance = 1000.0

    func withdraw(_ amount: Double) async throws {
        print("Balance before check: \\(balance)")

        guard balance >= amount else {
            throw BankError.insufficientFunds
        }

        // ⚠️ SUSPENSION POINT - Actor can be reentered!
        await performNetworkValidation(amount)

        // ⚠️ Balance might have changed!
        print("Balance after network: \\(balance)")

        // Must re-check!
        guard balance >= amount else {
            throw BankError.insufficientFunds
        }

        balance -= amount
    }
}

// Scenario:
// Thread 1: withdraw(600) - checks balance (1000), suspends at network call
// Thread 2: withdraw(600) - checks balance (1000), suspends at network call
// Thread 1: resumes, balance still 1000, withdraws 600, balance = 400
// Thread 2: resumes, balance is 400, must re-check!
```

**Solution:** Always re-check conditions after suspension points.

### Actor-Isolated Parameters

```swift
actor Database {
    func save(_ record: Record) { }
}

@MainActor
class ViewController {
    let database: Database

    func saveData() async {
        // database is passed to different actor context
        await database.save(record)
    }
}
```

### Global Actors

```swift
@globalActor
actor DatabaseActor {
    static let shared = DatabaseActor()
}

@DatabaseActor
class DatabaseManager {
    // All methods run on DatabaseActor
    func query() { }
}

@DatabaseActor
func performDatabaseWork() {
    // Runs on DatabaseActor
}
```

---

## <a name="mainactor"></a>5. MainActor

### Definition

```swift
@globalActor
public actor MainActor: GlobalActor {
    public static let shared: MainActor
}
```

Singleton actor representing the main thread.

### Usage Patterns

#### 1. Class-Level Isolation

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var data: [Item] = []

    func loadData() async {
        // Entire method runs on MainActor
        data = try await fetchData()
    }
}
```

#### 2. Property-Level Isolation

```swift
class DataManager {
    @MainActor var uiState: UIState

    func updateState() async {
        await MainActor.run {
            uiState = .loaded
        }
    }
}
```

#### 3. Function-Level Isolation

```swift
class Service {
    @MainActor
    func updateUI() {
        // Guaranteed on main thread
        label.text = "Updated"
    }

    func fetchData() async {
        let data = try await download()
        await updateUI()
    }
}
```

### MainActor Assumptions

```swift
@MainActor
class ViewController {
    func setup() {
        // Already on MainActor, no need for await
        MainActor.assumeIsolated {
            updateUI()
        }
    }

    func updateUI() {
        // Synchronous UI update
    }
}
```

### MainActor in SwiftUI

```swift
@MainActor
@Observable
class AppViewModel {
    var users: [User] = []
    var isLoading = false

    func refresh() async {
        isLoading = true
        users = try await fetchUsers()
        isLoading = false
    }
}

struct ContentView: View {
    @State var viewModel = AppViewModel()

    var body: some View {
        List(viewModel.users) { user in
            Text(user.name)
        }
        .task {
            await viewModel.refresh()
        }
    }
}
```

---

## <a name="asyncstream"></a>6. AsyncStream & AsyncSequence

### AsyncSequence Protocol

```swift
public protocol AsyncSequence {
    associatedtype Element
    associatedtype AsyncIterator: AsyncIteratorProtocol

    func makeAsyncIterator() -> AsyncIterator
}

public protocol AsyncIteratorProtocol {
    associatedtype Element

    mutating func next() async throws -> Element?
}
```

### AsyncStream

For non-throwing sequences:

```swift
public struct AsyncStream<Element> {
    public init(
        _ elementType: Element.Type = Element.self,
        bufferingPolicy: Continuation.BufferingPolicy = .unbounded,
        _ build: (Continuation) -> Void
    )

    public struct Continuation: Sendable {
        public func yield(_ value: Element)
        public func finish()

        public var onTermination: (@Sendable (Termination) -> Void)? { get nonmutating set }
    }
}
```

#### Example: Timer Stream

```swift
func timerStream(interval: Duration) -> AsyncStream<Date> {
    AsyncStream { continuation in
        let timer = Timer.scheduledTimer(withTimeInterval: interval.seconds, repeats: true) { _ in
            continuation.yield(Date())
        }

        continuation.onTermination = { @Sendable _ in
            timer.invalidate()
        }
    }
}

for await date in timerStream(interval: .seconds(1)) {
    print("Tick: \\(date)")
}
```

### AsyncThrowingStream

For throwing sequences:

```swift
func networkStream(url: URL) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        let session = URLSession.shared
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                continuation.finish(throwing: error)
                return
            }

            if let data = data {
                continuation.yield(data)
            }

            continuation.finish()
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        task.resume()
    }
}
```

### Buffering Policies

```swift
public enum BufferingPolicy: Sendable {
    case unbounded
    case bufferingOldest(Int)
    case bufferingNewest(Int)
}
```

**unbounded:** No limit, all elements buffered
**bufferingOldest(n):** Keep first n, drop new elements when full
**bufferingNewest(n):** Keep last n, drop old elements when full

### AsyncSequence Operators

```swift
extension AsyncSequence {
    // Transform elements
    public func map<T>(_ transform: (Element) async throws -> T)
        -> AsyncThrowingMapSequence<Self, T>

    // Filter elements
    public func filter(_ isIncluded: (Element) async throws -> Bool)
        -> AsyncThrowingFilterSequence<Self>

    // Transform and flatten
    public func flatMap<T>(_ transform: (Element) async throws -> T)
        -> AsyncThrowingFlatMapSequence<Self, T>

    // Remove nil values
    public func compactMap<T>(_ transform: (Element) async throws -> T?)
        -> AsyncThrowingCompactMapSequence<Self, T>

    // Limit elements
    public func prefix(_ count: Int) -> AsyncPrefixSequence<Self>

    // Skip elements
    public func dropFirst(_ count: Int) -> AsyncDropFirstSequence<Self>

    // Aggregation
    public func reduce<Result>(
        _ initialResult: Result,
        _ nextPartialResult: (Result, Element) async throws -> Result
    ) async rethrows -> Result
}
```

---

## <a name="task-groups"></a>7. Task Groups

### TaskGroup (Non-Throwing)

```swift
await withTaskGroup(of: String.self) { group in
    for id in userIDs {
        group.addTask {
            await fetchUsername(id: id)
        }
    }

    for await username in group {
        print("User: \\(username)")
    }
}
```

### ThrowingTaskGroup

```swift
try await withThrowingTaskGroup(of: Data.self) { group in
    for url in urls {
        group.addTask {
            try await download(from: url)
        }
    }

    var results: [Data] = []
    for try await data in group {
        results.append(data)
    }
    return results
}
```

### Task Group Operations

```swift
extension TaskGroup {
    // Add new task
    mutating func addTask(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> ChildTaskResult
    )

    // Wait for next completion
    mutating func next() async -> ChildTaskResult?

    // Cancel all tasks
    func cancelAll()

    // Check if empty
    var isEmpty: Bool { get }
}
```

### Discarding Task Groups

For fire-and-forget parallel work:

```swift
await withDiscardingTaskGroup { group in
    for notification in notifications {
        group.addTask {
            await sendNotification(notification)
        }
    }
    // Implicitly awaits all tasks
}
```

---

## <a name="sendable"></a>8. Sendable Protocol

### Definition

```swift
public protocol Sendable {}
```

Marker protocol indicating thread-safe types.

### Automatic Conformance

These types are automatically Sendable:

```swift
// Value types with Sendable members
struct User: Sendable {
    let id: String
    let name: String
}

// Enums with Sendable associated values
enum Result<T: Sendable, E: Error>: Sendable {
    case success(T)
    case failure(E)
}

// Frozen structs
@frozen struct Point: Sendable {
    let x: Int
    let y: Int
}

// Functions
let closure: @Sendable () -> Void = { }
```

### Manual Conformance

```swift
// Actor (always Sendable)
actor DataStore: Sendable {
    private var cache: [String: Data] = [:]
}

// Class with internal synchronization
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
```

### @Sendable Functions

```swift
func performAsync(
    operation: @Sendable @escaping () async -> Void
) {
    Task {
        await operation()
    }
}
```

### Sendable Checking

Enable strict checking:

```swift
// In Package.swift
.target(
    name: "MyTarget",
    swiftSettings: [
        .unsafeFlags([
            "-Xfrontend", "-strict-concurrency=complete"
        ])
    ]
)
```

---

## <a name="executors"></a>9. Task Executors

### TaskExecutor Protocol

```swift
public protocol TaskExecutor: Sendable {
    func enqueue(_ job: consuming ExecutorJob)
}
```

### SerialExecutor Protocol

```swift
public protocol SerialExecutor: TaskExecutor {
    func asUnownedSerialExecutor() -> UnownedSerialExecutor
}
```

### Custom Executor Example

```swift
import Dispatch

final class QueueExecutor: SerialExecutor, @unchecked Sendable {
    private let queue: DispatchQueue

    init(label: String) {
        self.queue = DispatchQueue(label: label)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

// Usage
let executor = QueueExecutor(label: "com.app.custom")

actor CustomActor {
    nonisolated let unownedExecutor: UnownedSerialExecutor

    init(executor: QueueExecutor) {
        self.unownedExecutor = executor.asUnownedSerialExecutor()
    }
}
```

---

## <a name="best-practices"></a>10. Best Practices

### 1. Prefer Structured Concurrency

```swift
// ✅ Good: Structured
async let users = fetchUsers()
async let posts = fetchPosts()
let data = await (users, posts)

// ❌ Avoid: Unstructured unless necessary
Task { await fetchUsers() }
Task { await fetchPosts() }
```

### 2. Use Actors for Mutable State

```swift
// ✅ Good: Actor-protected
actor UserCache {
    private var cache: [String: User] = [:]

    func store(_ user: User) {
        cache[user.id] = user
    }
}

// ❌ Bad: Unprotected mutable state
class UserCache {
    var cache: [String: User] = [:] // Data race!
}
```

### 3. Handle Cancellation

```swift
// ✅ Good: Respects cancellation
func processItems(_ items: [Item]) async throws {
    for item in items {
        try Task.checkCancellation()
        await process(item)
    }
}

// ❌ Bad: Ignores cancellation
func processItems(_ items: [Item]) async {
    for item in items {
        await process(item) // Continues even if cancelled
    }
}
```

### 4. Use MainActor for UI

```swift
// ✅ Good: Explicit MainActor
@MainActor
class ViewModel: ObservableObject {
    @Published var data: [Item] = []
}

// ❌ Bad: Manual dispatch
class ViewModel: ObservableObject {
    @Published var data: [Item] = []

    func update() {
        DispatchQueue.main.async {
            self.data = newData
        }
    }
}
```

### 5. Avoid Excessive Task Creation

```swift
// ✅ Good: Task group for batch
await withTaskGroup(of: Result.self) { group in
    for item in items {
        group.addTask { await process(item) }
    }
}

// ❌ Bad: Individual tasks
for item in items {
    Task { await process(item) }
}
```

### 6. Document Isolation

```swift
/// Fetches user data from the network.
/// - Important: This function is MainActor-isolated and will perform UI updates.
@MainActor
func fetchAndDisplayUser() async throws {
    // Implementation
}
```

### 7. Use AsyncStream for Callbacks

```swift
// ✅ Good: AsyncStream
var locationUpdates: AsyncStream<Location> {
    AsyncStream { continuation in
        manager.onUpdate = { continuation.yield($0) }
    }
}

// ❌ Bad: Callbacks
var onLocationUpdate: ((Location) -> Void)?
```

---

## <a name="performance"></a>11. Performance Considerations

### Thread Pool

Swift concurrency uses a **cooperative thread pool**:

- Number of threads ≈ CPU cores
- Tasks yield at suspension points
- No thread-per-task overhead

### Task Overhead

Creating tasks has minimal overhead but isn't free:

```swift
// ✅ Reasonable: Thousands of tasks
for url in urls { // 1000 URLs
    group.addTask { await fetch(url) }
}

// ❌ Excessive: Millions of tiny tasks
for i in 0..<1_000_000 { // Too fine-grained
    group.addTask { i * 2 }
}
```

### Actor Contention

Actors serialize access - avoid hotspots:

```swift
// ❌ Bad: Shared actor becomes bottleneck
actor GlobalCache {
    private var data: [String: Data] = [:]
}

let cache = GlobalCache() // Single point of contention

// ✅ Better: Sharded actors
class ShardedCache {
    private let shards: [actor Cache]

    func shard(for key: String) -> Cache {
        shards[key.hashValue % shards.count]
    }
}
```

### AsyncSequence Efficiency

```swift
// ✅ Efficient: Lazy transformation
let results = stream
    .filter { $0.isValid }
    .map { $0.transform() }

// ❌ Inefficient: Intermediate arrays
var filtered: [Element] = []
for await element in stream {
    if element.isValid {
        filtered.append(element)
    }
}
```

---

## <a name="migration"></a>12. Migration Guide

### From GCD

```swift
// Before: GCD
DispatchQueue.global().async {
    let data = self.fetchData()
    DispatchQueue.main.async {
        self.updateUI(with: data)
    }
}

// After: Swift Concurrency
Task {
    let data = await fetchData()
    await MainActor.run {
        updateUI(with: data)
    }
}
```

### From Completion Handlers

```swift
// Before: Completion handler
func fetchUser(id: String, completion: @escaping (Result<User, Error>) -> Void) {
    // Implementation
}

// After: async/await
func fetchUser(id: String) async throws -> User {
    try await withCheckedThrowingContinuation { continuation in
        fetchUser(id: id) { result in
            continuation.resume(with: result)
        }
    }
}
```

### From Delegates

```swift
// Before: Delegate
protocol DataDelegate {
    func dataDidUpdate(_ data: Data)
}

// After: AsyncStream
var dataUpdates: AsyncStream<Data> {
    AsyncStream { continuation in
        self.onUpdate = { data in
            continuation.yield(data)
        }
    }
}
```

---

## <a name="api-reference"></a>13. API Reference

### Task

- `init(priority:operation:)` - Create task
- `value` - Wait for result
- `cancel()` - Request cancellation
- `isCancelled` - Check cancellation
- `checkCancellation()` - Throw if cancelled
- `sleep(for:)` - Suspend for duration
- `yield()` - Yield control
- `currentPriority` - Get current priority

### Actor

- `unownedExecutor` - Get executor
- `assumeIsolated(_:)` - Assume isolation
- `assertIsolated()` - Assert isolation
- `preconditionIsolated()` - Precondition isolation

### AsyncStream

- `init(_:bufferingPolicy:_:)` - Create stream
- `Continuation.yield(_:)` - Emit element
- `Continuation.finish()` - Complete stream

### TaskGroup

- `addTask(priority:operation:)` - Add task
- `next()` - Get next result
- `cancelAll()` - Cancel all
- `isEmpty` - Check if empty

---

## Appendix A: Common Patterns

### Retry with Backoff

```swift
func retry<T>(
    maxAttempts: Int = 3,
    operation: () async throws -> T
) async throws -> T {
    var delay: Duration = .seconds(1)

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            guard attempt < maxAttempts else { throw error }
            try await Task.sleep(for: delay)
            delay *= 2
        }
    }

    fatalError()
}
```

### Timeout

```swift
func withTimeout<T>(
    _ duration: Duration,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

### Debounce

```swift
actor Debouncer<T> {
    private var task: Task<Void, Never>?
    private let delay: Duration
    private let action: (T) async -> Void

    init(delay: Duration, action: @escaping (T) async -> Void) {
        self.delay = delay
        self.action = action
    }

    func submit(_ value: T) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action(value)
        }
    }
}
```

---

## Appendix B: Compiler Flags

### Strict Concurrency Checking

```swift
// Package.swift
.target(
    name: "MyTarget",
    swiftSettings: [
        .unsafeFlags([
            "-Xfrontend", "-strict-concurrency=complete",
            "-Xfrontend", "-warn-concurrency",
            "-Xfrontend", "-enable-actor-data-race-checks"
        ])
    ]
)
```

### Migration Flags

```swift
// Gradual migration
.unsafeFlags([
    "-Xfrontend", "-strict-concurrency=minimal"  // Warnings only
])
```

---

## Appendix C: Further Reading

### Swift Evolution Proposals

- **SE-0296:** Async/await
- **SE-0306:** Actors
- **SE-0314:** AsyncStream and AsyncThrowingStream
- **SE-0338:** Clarify execution of non-actor-isolated async functions
- **SE-0392:** Custom Actor Executors
- **SE-0417:** Task Executor Preference

### Apple Documentation

- [Concurrency - The Swift Programming Language](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Swift Standard Library - Concurrency](https://developer.apple.com/documentation/swift/swift-standard-library/concurrency)

### WWDC Sessions

- WWDC21: Meet async/await in Swift
- WWDC21: Protect mutable state with Swift actors
- WWDC21: Explore structured concurrency in Swift
- WWDC22: Eliminate data races using Swift Concurrency

---

**Document Version:** 1.0
**Extracted From:** 139 Apple Developer Documentation files
**Source Location:** `/Volumes/Code/DeveloperExt/cupertinodocs/docs/swift/`
**Maintained By:** Development Team

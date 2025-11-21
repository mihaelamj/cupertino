# Swift Concurrency Cookbook
## 40 Practical Recipes for Common Multithreading Problems

**Compiled from Apple Developer Documentation**
**Source:** `/Volumes/Code/DeveloperExt/cupertinodocs/docs/swift/`
**Last Updated:** 2025-11-21

---

## Table of Contents

### Fundamentals
1. [Converting Callback-Based API to async/await](#recipe-1)
2. [Basic Task Creation and Execution](#recipe-2)
3. [Handling Task Cancellation](#recipe-3)
4. [Checking for Cancellation Points](#recipe-4)
5. [Task Priority Management](#recipe-5)

### Actors
6. [Creating a Thread-Safe Data Store with Actor](#recipe-6)
7. [Using MainActor for UI Updates](#recipe-7)
8. [Actor Isolation and Safe Access](#recipe-8)
9. [Distributed Actors for Client-Server Communication](#recipe-9)
10. [Actor Reentrancy Handling](#recipe-10)

### AsyncStream
11. [Creating AsyncStream from Callbacks](#recipe-11)
12. [AsyncStream with Buffering](#recipe-12)
13. [Handling Stream Cancellation](#recipe-13)
14. [Multi-Producer AsyncStream](#recipe-14)
15. [AsyncThrowingStream for Error Propagation](#recipe-15)

### Task Groups
16. [Parallel Processing with TaskGroup](#recipe-16)
17. [Dynamic Task Creation in Groups](#recipe-17)
18. [Collecting Results from Task Group](#recipe-18)
19. [Error Handling in Task Groups](#recipe-20)
20. [ThrowingTaskGroup for Failing Tasks](#recipe-20)

### AsyncSequence
21. [Transforming AsyncSequence with map](#recipe-21)
22. [Filtering Async Streams](#recipe-22)
23. [Combining Multiple AsyncSequences](#recipe-23)
24. [AsyncSequence with Timeout](#recipe-24)
25. [Buffering AsyncSequence Elements](#recipe-25)

### Synchronization
26. [Actor-Based Mutex Pattern](#recipe-26)
27. [Using AsyncLock for Critical Sections](#recipe-27)
28. [Coordinating Multiple Async Operations](#recipe-28)
29. [Debouncing with AsyncStream](#recipe-29)
30. [Throttling High-Frequency Events](#recipe-30)

### Error Handling
31. [Structured Error Propagation](#recipe-31)
32. [Retry Logic with Exponential Backoff](#recipe-32)
33. [Timeout Implementation](#recipe-33)
34. [Graceful Degradation](#recipe-34)
35. [Error Recovery in Task Groups](#recipe-35)

### Advanced Patterns
36. [Custom TaskExecutor Implementation](#recipe-36)
37. [SerialExecutor for Actor Customization](#recipe-37)
38. [Unstructured Tasks and Detached Tasks](#recipe-38)
39. [AsyncSequence Operators Chaining](#recipe-39)
40. [Building Reactive Pipelines](#recipe-40)

---

## Fundamentals

<a name="recipe-1"></a>
### Recipe 1: Converting Callback-Based API to async/await

**Problem:** You have legacy callback-based APIs that need to integrate with modern async/await code.

**Solution:**
```swift
// Legacy callback API
class NetworkManager {
    func fetchData(completion: @escaping (Result<Data, Error>) -> Void) {
        // ... implementation
    }
}

// Convert to async/await
extension NetworkManager {
    func fetchData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            fetchData { result in
                continuation.resume(with: result)
            }
        }
    }
}

// Usage
let data = try await networkManager.fetchData()
```

**When to use:**

**Real-World Scenarios:**
- **Legacy SDK Integration:** Converting CoreLocation's CLLocationManagerDelegate to async/await for modern SwiftUI apps
- **Third-Party Library Bridging:** Wrapping Alamofire, Firebase, or other callback-based networking libraries
- **Gradual Migration:** Updating existing codebases incrementally without breaking existing callback-based code
- **UIKit Delegate Patterns:** Converting UIImagePickerControllerDelegate, UIDocumentPickerDelegate to async APIs

**Specific Examples:**
- E-commerce apps using Stripe SDK (callback-based) need to integrate with async payment flows
- Social media apps converting Parse SDK or older SDKs to modern async architecture
- Healthcare apps wrapping FHIR client libraries with callback-based APIs
- Media apps converting AVFoundation delegate patterns to async/await for video processing

**Performance Considerations:**
- Zero overhead conversion - continuation is optimized by compiler
- Use `withCheckedContinuation` for non-throwing, `withCheckedThrowingContinuation` for throwing
- One-shot only: continuation.resume() can only be called once (runtime will crash if called multiple times)

**Common Gotchas:**
- Must call resume() exactly once - missing it causes memory leaks, calling twice crashes
- Capture self weakly if needed to prevent retain cycles
- For multi-value callbacks, use tuples or custom result types

---

<a name="recipe-2"></a>
### Recipe 2: Basic Task Creation and Execution

**Problem:** Need to start asynchronous work without blocking the current context.

**Solution:**
```swift
// Unstructured task (fires and forgets)
Task {
    let result = try await fetchUserData()
    print("Got result: \\(result)")
}

// Detached task (completely independent)
Task.detached {
    await performBackgroundWork()
}

// Task with priority
Task(priority: .high) {
    await urgentOperation()
}

// Waiting for task completion
let task = Task {
    return try await heavyComputation()
}
let result = try await task.value
```

**When to use:**

**Real-World Scenarios:**
- **Analytics/Telemetry:** Fire-and-forget logging that shouldn't block UI or business logic
- **Background Sync:** Syncing local database changes to server without blocking user actions
- **Resource Preloading:** Prefetching images, videos, or data the user might need soon
- **Cleanup Operations:** Deleting temporary files, clearing caches, pruning old data

**Specific Examples:**
- Chat app sending "user is typing" indicators (fire-and-forget with Task)
- News app prefetching article images for upcoming stories (Task with priority: .utility)
- Fitness app syncing workout data to HealthKit in background (Task.detached with priority: .background)
- E-commerce app logging product view events to analytics (Task, no await needed)

**When to Use Task vs Task.detached:**
- **Task**: Inherits priority, task-local values, and actor context - use for most cases
- **Task.detached**: Completely independent, no context inheritance - use for truly independent background work that shouldn't inherit current context

**Performance Considerations:**
- Unstructured tasks are not automatically cancelled when parent scope exits
- Store Task handle if you need to cancel later: `let task = Task { ... }; task.cancel()`
- Don't overuse detached tasks - they bypass priority escalation and can cause priority inversions

---

<a name="recipe-3"></a>
### Recipe 3: Handling Task Cancellation

**Problem:** Long-running tasks need to respond to cancellation requests.

**Solution:**
```swift
func processLargeDataset(_ items: [Item]) async throws {
    for item in items {
        // Check for cancellation
        try Task.checkCancellation()

        // Or manually check
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        await process(item)
    }
}

// Cancel a task
let task = Task {
    try await processLargeDataset(items)
}

// Later...
task.cancel()
```

**When to use:**

**Real-World Scenarios:**
- **Large File Processing:** Image/video processing that user might cancel mid-operation
- **Batch Operations:** Processing thousands of records where user might navigate away
- **Search Operations:** User typing in search bar, cancelling previous searches
- **Download Managers:** Multi-file downloads where user can cancel individual or all downloads

**Specific Examples:**
- Photo editing app applying filters to 100+ photos (check every 10 items)
- Document scanner app processing 50-page PDF (check after each page)
- Machine learning app running inference on video frames (check every frame)
- Database migration processing millions of records (check every 1000 records)

**Implementation Patterns:**
- **Periodic Checking:** Check every N iterations for CPU-bound loops
- **Suspension Points:** All await points automatically check for cancellation in standard library
- **Immediate Bailout:** Use `try Task.checkCancellation()` to throw CancellationError
- **Graceful Handling:** Use `guard !Task.isCancelled` for cleanup before exiting

**Common Gotchas:**
- Cancellation is cooperative - your code must check for it
- URLSession, FileHandle, and other system APIs check cancellation automatically
- Don't ignore CancellationError - let it propagate to cancel the entire task tree

---

<a name="recipe-4"></a>
### Recipe 4: Checking for Cancellation Points

**Problem:** Need to make async operations cancellation-aware at appropriate points.

**Solution:**
```swift
actor DataProcessor {
    func processItems(_ items: [Item]) async throws -> [Result] {
        var results: [Result] = []

        for (index, item) in items.enumerated() {
            // Check every 10 items
            if index % 10 == 0 {
                try Task.checkCancellation()
            }

            let result = await process(item)
            results.append(result)
        }

        return results
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Progressive UI Updates:** Updating UI every 10 items processed to show progress
- **Memory-Intensive Operations:** Giving system opportunity to cancel before OOM
- **User-Responsive Batch Operations:** Ensuring UI stays responsive during heavy processing
- **Long Network Operations:** Breaking large downloads into chunks with cancellation points

**Specific Examples:**
- Email app syncing 10,000 emails (check every 100 emails, update progress)
- Photo library importing 500 photos (check every 10, show thumbnails progressively)
- Data export generating large CSV files (check every 1000 rows)
- Social media app loading infinite scroll feed (check before each network request)

**Best Practices:**
- Balance between responsiveness and overhead (checking too often adds overhead)
- Check at natural boundaries: loop iterations, page boundaries, chunk completions
- Combine with progress reporting for better UX
- Don't check inside tight loops (< 1ms iterations) - adds significant overhead

---

<a name="recipe-5"></a>
### Recipe 5: Task Priority Management

**Problem:** Some tasks are more urgent than others and need prioritized execution.

**Solution:**
```swift
// High priority for UI operations
Task(priority: .high) {
    let criticalData = try await fetchCriticalData()
    await MainActor.run {
        updateUI(with: criticalData)
    }
}

// Background priority for analytics
Task(priority: .background) {
    await sendAnalytics()
}

// Get current task priority
let currentPriority = Task.currentPriority

// Task priority escalation
Task(priority: .low) {
    // If a high-priority task awaits this, priority escalates
    await performWork()
}
```

**When to use:**

**Real-World Scenarios:**
- **UI-Critical Operations:** User tapped button, need immediate response (priority: .high or .userInitiated)
- **Background Analytics:** Sending telemetry that shouldn't compete with UI (priority: .background)
- **Opportunistic Sync:** Syncing data when system resources available (priority: .utility)
- **Resource Contention:** Managing limited resources like CPU, network bandwidth

**Specific Examples:**
- Search app: User query at .high priority, result prefetching at .low priority
- Video streaming: Current chunk at .userInitiated, next 5 chunks at .utility, analytics at .background
- Game: Player input handling at .high, asset loading at .utility, cloud save at .background
- Banking app: Transaction submission at .high, statement download at .utility, usage analytics at .background

**Priority Levels:**
- **.high**: Time-critical UI operations (use sparingly)
- **.userInitiated**: User-requested operations (button taps, swipe actions)
- **.medium** (default): General async work
- **.utility**: Background work user is aware of (downloads, sync)
- **.background**: Housekeeping user isn't aware of (analytics, cleanup)

**Priority Escalation:**
- If high-priority task awaits low-priority task, low task automatically escalates
- Prevents priority inversion deadlocks
- Don't rely on escalation - set correct priority initially

**Performance Considerations:**
- Too many high-priority tasks defeats the purpose
- Background tasks yield to higher priority work
- Priority affects GCD queue selection under the hood

---

## Actors

<a name="recipe-6"></a>
### Recipe 6: Creating a Thread-Safe Data Store with Actor

**Problem:** Need thread-safe access to shared mutable state.

**Solution:**
```swift
actor DataStore {
    private var cache: [String: Data] = [:]

    func store(data: Data, forKey key: String) {
        cache[key] = data
    }

    func retrieve(forKey key: String) -> Data? {
        cache[key]
    }

    func clear() {
        cache.removeAll()
    }
}

// Usage
let store = DataStore()
await store.store(data: someData, forKey: "user")
let retrieved = await store.retrieve(forKey: "user")
```

**When to use:**

**Real-World Scenarios:**
- **Image Cache:** Thread-safe cache for downloaded images accessed by multiple views
- **Shopping Cart:** Mutable cart state accessed from product list, detail view, checkout
- **User Session:** Auth tokens, user profile data accessed across app
- **Configuration Manager:** Feature flags, settings shared across modules

**Specific Examples:**
- E-commerce: ShoppingCart actor managing items, quantities, total price
- Social media: FeedCache actor storing posts, preventing duplicate loads
- Messaging: UnreadCounter actor tracking badge count from multiple chat threads
- Music app: PlaybackQueue actor managing next/previous track, shuffle state

**Why Actor Instead of Class + Lock:**
- Compiler-enforced thread safety (can't forget to lock)
- Automatic serialization of access (no deadlocks)
- Reentrancy handling at suspension points
- Better composability with async/await

**Performance Considerations:**
- Actor calls have small overhead (dispatch queue hop)
- For read-heavy workloads, consider nonisolated let for immutable properties
- Group multiple mutations in single actor method to reduce hops
- Actors serialize access - long-running methods block other callers

**Migration from Classes:**
```swift
// Before: Class with NSLock
class DataStore {
    private let lock = NSLock()
    private var cache: [String: Data] = [:]
    func store(data: Data, forKey key: String) {
        lock.lock()
        cache[key] = data
        lock.unlock()
    }
}

// After: Actor (compiler-enforced safety)
actor DataStore {
    private var cache: [String: Data] = [:]
    func store(data: Data, forKey key: String) {
        cache[key] = data  // No manual locking needed
    }
}
```

---

<a name="recipe-7"></a>
### Recipe 7: Using MainActor for UI Updates

**Problem:** UI updates must happen on the main thread.

**Solution:**
```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var users: [User] = []

    func loadUsers() async {
        // This runs on main actor
        users = try await fetchUsers()
    }
}

// Mark individual functions
class DataManager {
    @MainActor
    func updateUI(with data: Data) {
        // Guaranteed to run on main thread
        label.text = String(data: data, encoding: .utf8)
    }

    func fetchData() async {
        let data = try await download()
        await updateUI(with: data)
    }
}

// Explicit main actor execution
await MainActor.run {
    label.text = "Updated"
}
```

**When to use:**

**Real-World Scenarios:**
- **SwiftUI ViewModels:** ObservableObject classes that publish UI state
- **UIKit View Controllers:** Updating labels, images, table views from async operations
- **UI Coordinators:** Managing navigation, alerts, sheets from background work
- **Animation Controllers:** Triggering animations after async data loads

**Specific Examples:**
- News app: ViewModel fetching articles, updating @Published properties
- Photo gallery: Loading images in background, displaying on UIImageView
- Form validation: Async validation, updating error labels on main thread
- Chat app: Receiving messages, inserting rows in UITableView

**Three Ways to Use MainActor:**

1. **@MainActor on Class** (Recommended for ViewModels):
```swift
@MainActor
class ArticleViewModel: ObservableObject {
    @Published var articles: [Article] = []
    // All methods run on main actor by default
    func loadArticles() async { ... }
}
```

2. **@MainActor on Function**:
```swift
class DataManager {
    @MainActor
    func updateUI() { ... }  // Only this method on main actor
}
```

3. **MainActor.run { }** (Explicit hop):
```swift
func fetchData() async {
    let data = await download()  // Background
    await MainActor.run {
        label.text = String(data: data, encoding: .utf8)  // Main thread
    }
}
```

**Common Patterns:**
- SwiftUI: Mark entire ViewModel with @MainActor
- UIKit: Mark individual UI update methods with @MainActor
- Mixed: Background processing, then MainActor.run for UI updates

**Performance Considerations:**
- Don't do heavy work on MainActor - blocks UI thread
- Fetch data on background, then hop to MainActor only for UI updates
- @MainActor functions can call non-MainActor functions (context switch)
- Non-MainActor functions must await MainActor functions

**Warning:**
```swift
// ❌ Wrong - blocks main thread
@MainActor
func loadData() async {
    let data = try await downloadLargeFile()  // Blocks UI!
}

// ✅ Correct - only UI updates on main thread
func loadData() async {
    let data = try await downloadLargeFile()  // Background
    await MainActor.run {
        self.displayData(data)  // Only UI on main
    }
}
```

---

<a name="recipe-8"></a>
### Recipe 8: Actor Isolation and Safe Access

**Problem:** Need to access actor-isolated state safely from different contexts.

**Solution:**
```swift
actor Counter {
    private var value = 0

    func increment() {
        value += 1
    }

    func getValue() -> Int {
        value
    }

    // Synchronous access (use with caution)
    nonisolated func unsafeValue() -> Int {
        // ⚠️ This is unsafe - value is not protected
        // Only use for non-mutable access
        return 0
    }
}

// Assume isolated for testing
extension Counter {
    func testHelper() {
        assumeIsolated { isolatedSelf in
            // Direct synchronous access for testing
            print(isolatedSelf.value)
        }
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Testing Actors:** Synchronously accessing actor state in unit tests
- **Performance Optimization:** Avoiding await overhead for immutable data
- **Legacy Integration:** Providing synchronous APIs for backward compatibility
- **Debugging:** Accessing actor state in debugger or logging

**Specific Examples:**
- Unit tests asserting actor state without complex async test setup
- Analytics actor exposing nonisolated computed properties for immutable counters
- Actor providing synchronous getters for configuration values loaded at init
- Logging actor state for debugging without await in print statements

**nonisolated vs await:**
- **nonisolated**: No actor isolation, no thread safety guarantees, synchronous access
- **await**: Full actor isolation, thread-safe, asynchronous

**When to Use nonisolated:**
- Immutable properties set in init
- Computed properties that don't access mutable state
- Functions that only call other async functions (acting as wrappers)
- Constants and type properties

**Common Gotchas:**
- nonisolated loses thread safety - only safe for immutable data
- assumeIsolated is dangerous - use only in tests or when you can prove isolation
- Don't use nonisolated just to avoid await - it defeats actor purpose

---

<a name="recipe-9"></a>
### Recipe 9: Distributed Actors for Client-Server Communication

**Problem:** Need to communicate between processes or networked systems.

**Solution:**
```swift
import Distributed

distributed actor GameServer {
    distributed func move(player: String, to position: Position) async throws {
        // Implementation
    }

    distributed func getGameState() async throws -> GameState {
        // Implementation
    }
}

// Client usage
let server: GameServer = try GameServer.resolve(id: serverId, using: actorSystem)
try await server.move(player: "Alice", to: Position(x: 5, y: 10))
```

**When to use:**

**Real-World Scenarios:**
- **Multiplayer Games:** Client communicating with game server actors
- **Microservices:** Service-to-service communication with location transparency
- **IoT Systems:** Smart home hub communicating with device actors
- **Distributed Computing:** Worker nodes exposing actors for task processing

**Specific Examples:**
- Real-time multiplayer game with GameServer actor handling player moves
- Chat system with RoomActor on server, clients calling distributed methods
- Trading platform with OrderBook actor distributed across data centers
- Scientific computing with ComputeNode actors processing chunks of data

**Key Features:**
- Location transparency: Call distributed actor like local actor
- Automatic serialization/deserialization of arguments and results
- Network failure handling with Swift errors
- Actor identity resolution across processes/machines

**Requirements:**
- Arguments and returns must conform to Codable
- Errors thrown must conform to Error and Codable
- ActorSystem provides transport layer implementation
- Currently experimental - API may change

**When NOT to Use:**
- High-frequency method calls (network overhead per call)
- Large data transfers (serialize in chunks instead)
- Local-only actors (regular actors are more efficient)

---

<a name="recipe-10"></a>
### Recipe 10: Actor Reentrancy Handling

**Problem:** Actors can be reentered during suspension points, leading to unexpected state.

**Solution:**
```swift
actor BankAccount {
    private var balance: Double = 1000.0
    private var isProcessing = false

    func withdraw(_ amount: Double) async throws {
        // Guard against reentrancy
        guard !isProcessing else {
            throw BankError.operationInProgress
        }

        isProcessing = true
        defer { isProcessing = false }

        guard balance >= amount else {
            throw BankError.insufficientFunds
        }

        // Suspension point - actor can be reentered!
        await performNetworkValidation(amount)

        // Balance might have changed during suspension
        guard balance >= amount else {
            throw BankError.insufficientFunds
        }

        balance -= amount
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Banking Operations:** Preventing double withdrawals during network calls
- **Resource Allocation:** Ensuring resources aren't over-allocated during async checks
- **State Machines:** Preventing invalid state transitions during async operations
- **Transaction Processing:** Maintaining consistency during multi-step async transactions

**Specific Examples:**
- Banking app: Withdraw checks balance, then async network call - balance might change during suspension
- Ticket booking: Check seat availability, then async payment - seat might be taken during payment processing
- File upload: Check quota, then async upload - quota might be exceeded during upload
- Game: Check inventory, then async crafting - items might be consumed during crafting

**Actor Reentrancy Explained:**
```swift
actor BankAccount {
    var balance = 1000.0

    func withdraw(_ amount: Double) async {
        guard balance >= amount else { return }  // Check 1

        // ⚠️ SUSPENSION POINT - actor can be reentered!
        await networkValidation(amount)

        // ⚠️ balance might have changed!
        // Another withdraw() call might have executed during suspension
        balance -= amount  // BUG: Might overdraw!
    }
}
```

**Solution Patterns:**

1. **Guard Flag Pattern** (shown in recipe):
```swift
private var isProcessing = false
guard !isProcessing else { throw Error.busy }
isProcessing = true
defer { isProcessing = false }
```

2. **Re-validate After Suspension**:
```swift
guard balance >= amount else { throw Error.insufficient }
await networkCall()
guard balance >= amount else { throw Error.insufficient }  // Check again!
balance -= amount
```

3. **Optimistic Locking**:
```swift
let snapshot = balance
await asyncWork()
guard balance == snapshot else { throw Error.modified }
```

**Critical Insight:**
- Actor guarantees: No data races, serialized access
- Actor does NOT guarantee: State unchanged across suspension points
- Every await is a potential reentrancy point

**Real-World Impact:**
- Stripe SDK: Uses reentrancy guards for payment processing
- Firebase: Transactions handle reentrancy with optimistic locking
- Core Data: NSManagedObjectContext uses similar patterns

---

## AsyncStream

<a name="recipe-11"></a>
### Recipe 11: Creating AsyncStream from Callbacks

**Problem:** Convert delegate/callback patterns to async sequences.

**Solution:**
```swift
class LocationManager {
    var onLocationUpdate: ((Location) -> Void)?
}

extension LocationManager {
    var locationUpdates: AsyncStream<Location> {
        AsyncStream { continuation in
            self.onLocationUpdate = { location in
                continuation.yield(location)
            }

            continuation.onTermination = { @Sendable _ in
                self.onLocationUpdate = nil
            }

            self.startUpdating()
        }
    }
}

// Usage
for await location in locationManager.locationUpdates {
    print("New location: \\(location)")
}
```

**When to use:**

**Real-World Scenarios:**
- **Location Services:** Converting CLLocationManagerDelegate to AsyncStream
- **Bluetooth:** CBCentralManagerDelegate/CBPeripheralDelegate to async sequences
- **Notifications:** NotificationCenter observers to AsyncStream
- **Sensor Data:** Accelerometer, gyroscope, compass updates

**Specific Examples:**
- Navigation app: Location updates stream for real-time tracking
- Fitness tracker: Heart rate monitor BLE peripheral streaming data
- Weather app: Local notification stream for weather alerts
- AR app: Device motion updates for camera orientation

**Key Pattern:**
```swift
extension SomeDelegate {
    var updates: AsyncStream<UpdateType> {
        AsyncStream { continuation in
            // 1. Set delegate/callback
            self.onUpdate = { update in
                continuation.yield(update)  // Forward to stream
            }

            // 2. Cleanup on termination
            continuation.onTermination = { @Sendable _ in
                self.onUpdate = nil
                self.stopUpdates()
            }

            // 3. Start producing events
            self.startUpdates()
        }
    }
}
```

**Common Delegate Patterns to Convert:**
- CLLocationManagerDelegate → locationUpdates: AsyncStream<CLLocation>
- URLSessionTaskDelegate → progressUpdates: AsyncStream<Progress>
- AVCaptureVideoDataOutputSampleBufferDelegate → videoFrames: AsyncStream<CMSampleBuffer>
- NotificationCenter → notifications(named:): AsyncStream<Notification>

**Benefits Over Delegates:**
- Composable with other async/await code
- Natural backpressure handling with buffering
- Automatic cleanup with onTermination
- No delegate protocol boilerplate

---

<a name="recipe-12"></a>
### Recipe 12: AsyncStream with Buffering

**Problem:** Producer creates elements faster than consumer can process.

**Solution:**
```swift
let stream = AsyncStream<Int>(bufferingPolicy: .bufferingNewest(10)) { continuation in
    for i in 1...100 {
        continuation.yield(i)
    }
    continuation.finish()
}

// Unbounded buffer (default)
let unbounded = AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
    // No elements are dropped
}

// Buffering oldest (drops new elements when full)
let bufferOldest = AsyncStream<Event>(bufferingPolicy: .bufferingOldest(5)) { continuation in
    // Keeps first 5 elements, drops new ones
}
```

**When to use:**

**Real-World Scenarios:**
- **High-Frequency Sensors:** Accelerometer data at 100Hz, consumer processes at 10Hz
- **Video Frames:** Camera producing 60fps, processing only 30fps
- **Stock Tickers:** Market data updates faster than UI can render
- **Log Streams:** Application logging at high rate, console displaying subset

**Specific Examples:**
- Fitness app: Accelerometer at 100Hz, only keep latest 10 for gesture recognition
- Video editor: Frame stream with bufferingOldest(30) for scrubbing
- Trading app: Price updates with bufferingNewest(100) to show recent prices
- Game: Input events with unbounded buffer to not drop any user actions

**Buffering Policies:**

1. **.unbounded** (default):
   - Stores ALL elements until consumed
   - Risk: Memory growth if consumer is slow
   - Use for: Critical events that can't be dropped (user input, transactions)

2. **.bufferingNewest(n)**:
   - Keeps latest n elements, drops oldest
   - Use for: Real-time data where latest value matters (sensor data, stock prices)

3. **.bufferingOldest(n)**:
   - Keeps first n elements, drops new ones
   - Use for: Rate limiting, fairness (first-come-first-served)

**Performance Considerations:**
- Unbounded buffers can cause OOM with fast producer + slow consumer
- Buffered(10) is usually good starting point for UI updates
- Monitor memory if producer is much faster than consumer
- Consider debouncing/throttling instead of large buffers

---

<a name="recipe-13"></a>
### Recipe 13: Handling Stream Cancellation

**Problem:** Need to clean up resources when stream consumer cancels iteration.

**Solution:**
```swift
func networkStream() -> AsyncStream<Data> {
    AsyncStream { continuation in
        let connection = NetworkConnection()

        connection.onData = { data in
            continuation.yield(data)
        }

        connection.onComplete = {
            continuation.finish()
        }

        continuation.onTermination = { @Sendable termination in
            switch termination {
            case .finished:
                print("Stream completed normally")
            case .cancelled:
                print("Stream was cancelled")
                connection.disconnect()
            @unknown default:
                break
            }
        }

        connection.connect()
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **WebSocket Connections:** User navigates away, need to close socket
- **File Downloads:** User cancels download, need to delete partial file
- **Database Cursors:** Stream iteration cancelled, need to close cursor
- **Hardware Resources:** Camera/microphone streaming cancelled, need to release

**Specific Examples:**
- Chat app: WebSocket stream cancelled when user logs out - disconnect cleanly
- Video player: Video chunk stream cancelled when user stops playback - cancel network requests
- Document scanner: Page scanning stream cancelled - stop camera capture
- Audio recorder: Recording stream cancelled - finalize and save audio file

**Termination Reasons:**

```swift
continuation.onTermination = { @Sendable termination in
    switch termination {
    case .finished:
        // Stream completed normally (continuation.finish() was called)
        print("Completed successfully")
        cleanup()

    case .cancelled:
        // Consumer stopped iterating (task cancelled, break from loop)
        print("User cancelled")
        cancelOngoingWork()
        deletePartialResults()

    @unknown default:
        // Future termination reasons
        break
    }
}
```

**Common Cleanup Patterns:**

1. **Network Cleanup**:
```swift
case .cancelled:
    urlSessionTask.cancel()
    connection.disconnect()
```

2. **File Cleanup**:
```swift
case .cancelled:
    try? FileManager.default.removeItem(at: partialFile)
```

3. **Hardware Cleanup**:
```swift
case .cancelled:
    captureSession.stopRunning()
    audioEngine.stop()
```

**Critical Reminder:**
- onTermination closure MUST be @Sendable (no capturing mutable state)
- Cleanup happens automatically when consumer breaks loop or task is cancelled
- Don't forget to unregister callbacks to prevent memory leaks

---

<a name="recipe-14"></a>
### Recipe 14: Multi-Producer AsyncStream

**Problem:** Multiple sources need to feed into a single async stream.

**Solution:**
```swift
actor StreamCoordinator<T> {
    private var continuation: AsyncStream<T>.Continuation?
    private let stream: AsyncStream<T>

    init() {
        stream = AsyncStream { self.continuation = $0 }
    }

    func yield(_ value: T) {
        continuation?.yield(value)
    }

    func finish() {
        continuation?.finish()
    }

    var asyncStream: AsyncStream<T> { stream }
}

// Usage
let coordinator = StreamCoordinator<Event>()

Task {
    await coordinator.yield(Event(type: "A"))
}

Task {
    await coordinator.yield(Event(type: "B"))
}

for await event in await coordinator.asyncStream {
    print(event)
}
```

**When to use:**

**Real-World Scenarios:**
- **Multi-Device Sync:** Multiple devices pushing updates to single event stream
- **Sensor Fusion:** Combining accelerometer, gyroscope, magnetometer into unified stream
- **Chat Rooms:** Multiple users posting messages to shared message stream
- **Distributed Logging:** Multiple services sending logs to centralized stream

**Specific Examples:**
- Collaboration app: Multiple users editing document, changes merged into single update stream
- Smart home: Multiple sensors (motion, temperature, door) feeding into event stream
- Trading platform: Multiple exchanges publishing prices to unified ticker stream
- Game server: Multiple players sending actions aggregated into game event stream

**Why Actor Coordinator:**
```swift
// ❌ Wrong - continuation not Sendable!
var continuation: AsyncStream<Event>.Continuation?
Task {
    continuation?.yield(event)  // Crash: continuation not thread-safe
}

// ✅ Correct - actor provides thread safety
actor StreamCoordinator<T> {
    private var continuation: AsyncStream<T>.Continuation?
    // Actor isolation makes continuation access thread-safe
}
```

**Pattern Variations:**

1. **Fan-In with Priorities**:
```swift
actor PriorityStreamCoordinator<T> {
    func yield(_ value: T, priority: TaskPriority) {
        // Higher priority values yielded first
    }
}
```

2. **Buffered Fan-In**:
```swift
actor BufferedCoordinator<T> {
    private var buffer: [T] = []
    func yield(_ value: T) async {
        // Buffer and batch yields
    }
}
```

**Real-World Complexity:**
- Stripe webhooks: Multiple webhook sources feeding payment event stream
- Kubernetes: Multiple pods logging to single aggregated stream
- IoT: Edge devices publishing to cloud-aggregated stream

---

<a name="recipe-15"></a>
### Recipe 15: AsyncThrowingStream for Error Propagation

**Problem:** Stream operations can fail and need to propagate errors.

**Solution:**
```swift
func downloadStream(url: URL) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                continuation.finish(throwing: error)
                return
            }

            guard let data = data else {
                continuation.finish(throwing: NetworkError.noData)
                return
            }

            continuation.yield(data)
            continuation.finish()
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        task.resume()
    }
}

// Usage with error handling
do {
    for try await chunk in downloadStream(url: fileURL) {
        process(chunk)
    }
} catch {
    print("Download failed: \\(error)")
}
```

**When to use:**

**Real-World Scenarios:**
- **File Downloads:** Network failures during chunked downloads
- **JSON Parsing:** Malformed data in stream of API responses
- **Database Queries:** Connection errors during result streaming
- **Image Processing:** Corrupt images in batch processing stream

**Specific Examples:**
- Podcast app: Downloading episodes, network error should fail stream with retry option
- RSS reader: Parsing feed items, XML parse error should terminate stream with error
- Photo backup: Uploading photos, auth error should stop stream and re-login
- Video transcoding: Processing frames, codec error should fail with diagnostic info

**AsyncThrowingStream vs AsyncStream:**

| Feature | AsyncStream | AsyncThrowingStream |
|---------|-------------|---------------------|
| Can throw | ❌ No | ✅ Yes |
| Error handling | N/A | `for try await` + `do-catch` |
| Performance | Slightly faster | Minimal overhead |
| Use case | Infallible streams | Fallible operations |

**Error Handling Patterns:**

1. **Fail Fast**:
```swift
continuation.finish(throwing: error)  // Stop immediately on first error
```

2. **Error Recovery**:
```swift
do {
    for try await item in stream {
        process(item)
    }
} catch NetworkError.rateLimited {
    await Task.sleep(for: .seconds(60))
    // Retry with new stream
} catch {
    // Log and continue with cached data
}
```

3. **Partial Results**:
```swift
var results: [Result<Data, Error>] = []
do {
    for try await data in stream {
        results.append(.success(data))
    }
} catch {
    // Return partial results collected so far
    return results
}
```

**Common Mistakes:**
- Don't swallow errors silently - always log or handle
- continuation.yield() after finish(throwing:) does nothing
- Error type must be Error (not custom error types in generic)

---

## Task Groups

<a name="recipe-16"></a>
### Recipe 16: Parallel Processing with TaskGroup

**Problem:** Need to process multiple items concurrently and collect results.

**Solution:**
```swift
func fetchAllUsers(ids: [String]) async throws -> [User] {
    try await withThrowingTaskGroup(of: User.self) { group in
        for id in ids {
            group.addTask {
                try await fetchUser(id: id)
            }
        }

        var users: [User] = []
        for try await user in group {
            users.append(user)
        }
        return users
    }
}

// Parallel image downloads
func downloadImages(urls: [URL]) async -> [UIImage] {
    await withTaskGroup(of: UIImage?.self) { group in
        for url in urls {
            group.addTask {
                try? await downloadImage(from: url)
            }
        }

        var images: [UIImage] = []
        for await image in group {
            if let image = image {
                images.append(image)
            }
        }
        return images
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Batch API Requests:** Fetching user profiles for 100 user IDs in parallel
- **Parallel Downloads:** Downloading multiple images/files simultaneously
- **Data Processing:** Processing independent data chunks across CPU cores
- **Validation:** Validating multiple forms fields concurrently

**Specific Examples:**
- Social media: Fetch 50 friend profiles in parallel (20x faster than sequential)
- Photo gallery: Download 20 thumbnails concurrently with TaskGroup
- E-commerce: Validate shipping address, payment, inventory in parallel
- Analytics: Process daily reports for 30 days concurrently

**Performance Benefits:**
```swift
// Sequential: 10 users × 200ms = 2000ms total
for id in userIDs {
    let user = try await fetchUser(id)
}

// Parallel with TaskGroup: 200ms total (10 concurrent requests)
try await withThrowingTaskGroup(of: User.self) { group in
    for id in userIDs {
        group.addTask { try await fetchUser(id) }
    }
    // ...collect results
}
```

**When to Use withTaskGroup vs withThrowingTaskGroup:**
- **withTaskGroup**: Tasks don't throw (or errors handled internally)
- **withThrowingTaskGroup**: Tasks can throw, want to propagate errors

**Best Practices:**
- Limit concurrency for external APIs (use sliding window if > 10 tasks)
- TaskGroup is structured - exits when all children complete or scope ends
- Results arrive in completion order, NOT submission order
- Use this pattern when number of tasks known upfront

---

<a name="recipe-17"></a>
### Recipe 17: Dynamic Task Creation in Groups

**Problem:** Don't know number of tasks upfront, need to add them dynamically.

**Solution:**
```swift
func crawlWebsite(startURL: URL, maxDepth: Int) async -> Set<URL> {
    await withTaskGroup(of: Set<URL>.self) { group in
        var visited: Set<URL> = [startURL]
        var toVisit: Set<URL> = [startURL]

        while !toVisit.isEmpty {
            let url = toVisit.removeFirst()

            group.addTask {
                return await self.extractLinks(from: url)
            }

            if let links = await group.next() {
                let newLinks = links.subtracting(visited)
                visited.formUnion(newLinks)
                toVisit.formUnion(newLinks)
            }
        }

        return visited
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Web Crawling:** Don't know how many pages until you crawl them
- **Directory Traversal:** Recursive file system operations with unknown depth
- **Graph Algorithms:** BFS/DFS where edges discovered during traversal
- **Dependency Resolution:** Package manager resolving transitive dependencies

**Specific Examples:**
- Search engine crawler: Start with seed URLs, discover more while crawling
- File indexer: Traverse directories, subdirectories discovered dynamically
- Social network: Follow friend-of-friend relationships to build network
- Package manager: Resolve npm/Swift package dependencies transitively

**Key Pattern:**
```swift
while !toVisit.isEmpty {
    group.addTask { /* process next item */ }

    if let result = await group.next() {  // Wait for ONE task
        // Use result to potentially add MORE tasks
        toVisit.formUnion(result.newItemsDiscovered)
    }
}
```

**Performance Considerations:**
- group.next() waits for ANY task (not FIFO order)
- Limits concurrency naturally (add one, wait for one)
- Good for recursive problems with unknown bounds
- Use maxConcurrency wrapper if needed to limit parallel tasks

---

<a name="recipe-18"></a>
### Recipe 18: Collecting Results from Task Group

**Problem:** Need to aggregate results from parallel tasks in specific ways.

**Solution:**
```swift
// Collect all results
func sumParallel(_ numbers: [Int]) async -> Int {
    await withTaskGroup(of: Int.self) { group in
        for number in numbers {
            group.addTask {
                return number * 2
            }
        }

        var sum = 0
        for await result in group {
            sum += result
        }
        return sum
    }
}

// Collect into dictionary
func fetchUserProfiles(ids: [String]) async -> [String: Profile] {
    await withTaskGroup(of: (String, Profile).self) { group in
        for id in ids {
            group.addTask {
                let profile = await fetchProfile(id: id)
                return (id, profile)
            }
        }

        var profiles: [String: Profile] = [:]
        for await (id, profile) in group {
            profiles[id] = profile
        }
        return profiles
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Aggregation:** Sum, average, min/max across parallel computations
- **Collection Building:** Dictionary, set, array from parallel fetches
- **Data Merging:** Combining results from multiple data sources
- **Reporting:** Generating aggregate statistics from parallel queries

**Specific Examples:**
- Analytics dashboard: Aggregate metrics from 12 months processed in parallel
- Search engine: Collect results from multiple search indexes concurrently
- Social media: Build user profile dictionary from parallel API calls
- E-commerce: Calculate total inventory value across parallel warehouse queries

**Collection Patterns:**

1. **Array (Ordered)**:
```swift
// Results arrive in completion order (unordered)
var results: [User] = []
for await user in group {
    results.append(user)  // Order not guaranteed
}
```

2. **Dictionary (Keyed)**:
```swift
// Use tuple return to preserve mapping
withTaskGroup(of: (String, Profile).self) { group in
    var profiles: [String: Profile] = [:]
    for await (id, profile) in group {
        profiles[id] = profile  // Key preserved
    }
}
```

3. **Reduce (Aggregated)**:
```swift
// Aggregate on-the-fly
var sum = 0
for await value in group {
    sum += value  // Reduce without intermediate array
}
```

**Performance Tip:**
- Don't collect all results if you only need aggregate
- Process results as they arrive for memory efficiency
- Use reduce pattern to avoid intermediate collection

---

<a name="recipe-19"></a>
### Recipe 19: Error Handling in Task Groups

**Problem:** Some tasks in group may fail, need to handle errors appropriately.

**Solution:**
```swift
func downloadFiles(urls: [URL]) async throws -> [Data] {
    try await withThrowingTaskGroup(of: Data.self) { group in
        for url in urls {
            group.addTask {
                try await download(from: url)
            }
        }

        var results: [Data] = []
        do {
            for try await data in group {
                results.append(data)
            }
        } catch {
            // Cancel all remaining tasks
            group.cancelAll()
            throw error
        }
        return results
    }
}

// Partial failure handling
func downloadFilesWithErrors(urls: [URL]) async -> [Result<Data, Error>] {
    await withTaskGroup(of: Result<Data, Error>.self) { group in
        for url in urls {
            group.addTask {
                Result {
                    try await download(from: url)
                }
            }
        }

        var results: [Result<Data, Error>] = []
        for await result in group {
            results.append(result)
        }
        return results
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Batch Uploads:** Some files upload successfully, others fail - report both
- **Multi-API Integration:** Fetch from multiple services, some might be down
- **Data Migration:** Migrate records, track successes and failures separately
- **Health Checks:** Ping multiple servers, collect which are up/down

**Specific Examples:**
- Photo backup: Upload 100 photos, report 95 succeeded, 5 failed with reasons
- RSS aggregator: Fetch 20 feeds, 18 succeed, 2 timeout - show available content
- Deployment tool: Deploy to 10 servers, 9 succeed, 1 fails - rollback only failed
- Notification service: Send push notifications, track delivery failures

**Two Error Strategies:**

1. **Fail Fast** (ThrowingTaskGroup):
```swift
// First error cancels all remaining tasks
try await withThrowingTaskGroup { group in
    for item in items { group.addTask { try await process(item) } }
    for try await result in group { results.append(result) }
    // If any throws, remaining tasks cancelled immediately
}
```

2. **Partial Success** (Result pattern):
```swift
// All tasks complete, track individual failures
await withTaskGroup(of: Result<Data, Error>.self) { group in
    // Each task wraps result in Result type
    group.addTask { Result { try await download(url) } }
    // Collect all results, separate successes from failures later
}
```

**Use Fail Fast When:**
- Transaction must be atomic (all or nothing)
- First error indicates systemic problem
- No point continuing if one fails (e.g., pipeline steps)

**Use Partial Success When:**
- Independent operations (one failure doesn't affect others)
- Want to maximize successful operations
- Need detailed per-item error reporting

---

<a name="recipe-20"></a>
### Recipe 20: ThrowingTaskGroup for Failing Tasks

**Problem:** Any task failure should fail the entire group.

**Solution:**
```swift
func processInParallel(_ items: [Item]) async throws -> [Result] {
    try await withThrowingTaskGroup(of: Result.self) { group in
        for item in items {
            group.addTask {
                try await process(item)
            }
        }

        var results: [Result] = []
        // If any task throws, iteration stops and error propagates
        for try await result in group {
            results.append(result)
        }
        return results
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Database Transactions:** All queries must succeed or rollback
- **Multi-Step Workflows:** Payment → Inventory → Shipping (all must succeed)
- **Data Validation:** Multiple validators, any failure invalidates entire input
- **Deployment Pipelines:** Build → Test → Deploy (stop on first failure)

**Specific Examples:**
- E-commerce checkout: Charge card, reserve inventory, create shipping label - any failure aborts
- Bank transfer: Debit source account, credit dest account, log transaction - atomic operation
- CI/CD pipeline: Compile, test, lint, security scan - stop at first failure
- Data import: Validate schema, check constraints, insert records - all-or-nothing

**Transactional Processing Pattern:**
```swift
// All operations succeed or none do
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { try await chargePayment() }
    group.addTask { try await reserveInventory() }
    group.addTask { try await createShippingLabel() }

    // If ANY task throws:
    // 1. Error propagates immediately
    // 2. Remaining tasks are cancelled
    // 3. Caller can rollback/cleanup
    for try await _ in group { }
}
```

**Error Propagation:**
- First thrown error stops iteration immediately
- group.cancelAll() called automatically
- Other tasks get cancellation (check Task.isCancelled)
- Caller's catch block handles rollback

**Comparison with Result Pattern:**
| Feature | ThrowingTaskGroup | Result Pattern |
|---------|-------------------|----------------|
| Error handling | First error fails all | All complete |
| Use case | Atomic operations | Independent ops |
| Performance | Fail fast (efficient) | Always completes |
| Cleanup | Automatic cancel | Manual tracking |

---

## AsyncSequence

<a name="recipe-21"></a>
### Recipe 21: Transforming AsyncSequence with map

**Problem:** Need to transform elements in an async sequence.

**Solution:**
```swift
let numbers = AsyncStream<Int> { continuation in
    for i in 1...10 {
        continuation.yield(i)
    }
    continuation.finish()
}

// Map transformation
let doubled = numbers.map { $0 * 2 }

for await value in doubled {
    print(value) // 2, 4, 6, 8...
}

// CompactMap to filter nil values
let strings = ["1", "2", "abc", "4"]
let parsedNumbers = strings.async.compactMap { Int($0) }

for await number in parsedNumbers {
    print(number) // 1, 2, 4
}
```

**When to use:**

**Real-World Scenarios:**
- **API Response Processing:** Transform JSON to model objects in stream
- **Data Formatting:** Convert temperatures, currencies, dates in pipeline
- **Image Processing:** Resize, filter, compress images as they stream
- **Text Processing:** Parse, sanitize, format log lines in stream

**Specific Examples:**
- Analytics: Stream of raw events → map to formatted metrics → display
- CSV Import: Stream rows → map to objects → validate → insert
- Image gallery: Stream URLs → map to downloaded images → thumbnail → display
- Search: Stream query results → map to highlighted snippets → rank

**AsyncSequence Operators:**
```swift
stream
    .map { $0 * 2 }              // Transform each element
    .compactMap { Int($0) }      // Filter nil, transform
    .filter { $0 > 10 }          // Keep only matching
    .prefix(100)                  // Take first 100
    .drop(while: { $0 < 5 })     // Skip until condition
```

**Performance:**
- Lazy evaluation - only processes when consumed
- Memory efficient - no intermediate collections
- Composable - chain multiple operators
- Type-safe transformations at compile time

---

<a name="recipe-22"></a>
### Recipe 22: Filtering Async Streams

**Problem:** Need to filter elements from an async sequence based on criteria.

**Solution:**
```swift
let events = AsyncStream<Event> { continuation in
    // ... emit events
}

// Filter even numbers
let evenNumbers = stream.filter { $0 % 2 == 0 }

// Filter with async predicate
let validatedItems = items.filter { item in
    await validate(item)
}

for await item in validatedItems {
    process(item)
}
```

**When to use:**

**Real-World Scenarios:**
- **Event Filtering:** Filter button taps, scroll events, notifications by criteria
- **Data Cleaning:** Remove invalid/duplicate entries from data streams
- **Access Control:** Filter events based on user permissions
- **Content Moderation:** Filter inappropriate content in real-time streams

**Specific Examples:**
- Chat app: Filter messages for current conversation only
- Analytics: Filter events by user segment or time range
- IoT: Filter sensor readings outside normal range (anomaly detection)
- Social media: Filter posts by keywords, hashtags, or user preferences

**Async Predicates:**
```swift
// Async validation (e.g., check database)
let validItems = stream.filter { item in
    await validator.isValid(item)  // Can await!
}
```

**Common Patterns:**
- Filter + map: Clean data then transform
- Filter duplicates: Use Set to track seen items
- Filter by time: Check timestamps in predicate

---

<a name="recipe-23"></a>
### Recipe 23: Combining Multiple AsyncSequences

**Problem:** Need to process multiple async sequences together.

**Solution:**
```swift
// Merge multiple streams
func merge<T>(_ sequences: [AsyncStream<T>]) -> AsyncStream<T> {
    AsyncStream { continuation in
        let group = TaskGroup { group in
            for sequence in sequences {
                group.addTask {
                    for await value in sequence {
                        continuation.yield(value)
                    }
                }
            }
        }

        Task {
            await group.waitForAll()
            continuation.finish()
        }
    }
}

// Zip two sequences
func zip<A, B>(_ a: AsyncStream<A>, _ b: AsyncStream<B>) -> AsyncStream<(A, B)> {
    AsyncStream { continuation in
        Task {
            var iteratorA = a.makeAsyncIterator()
            var iteratorB = b.makeAsyncIterator()

            while let valueA = await iteratorA.next(),
                  let valueB = await iteratorB.next() {
                continuation.yield((valueA, valueB))
            }

            continuation.finish()
        }
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Multi-Source Aggregation:** Combine logs from multiple servers
- **Sensor Fusion:** Merge accelerometer, gyroscope, magnetometer data
- **Multi-API Responses:** Combine results from multiple search engines
- **Event Correlation:** Match events from different streams by timestamp

**Specific Examples:**
- Monitoring dashboard: Merge metrics from 50 microservices into single stream
- Trading platform: Combine price feeds from NYSE, NASDAQ, LSE
- Weather app: Merge forecasts from multiple weather services
- Video conferencing: Combine audio/video streams from participants

**Merge vs Zip:**
- **Merge**: Interleaves all elements (any order), completes when all finish
- **Zip**: Pairs elements (synchronized), completes when shortest finishes

**Use Merge for:** Independent events that should be processed as they arrive
**Use Zip for:** Related events that must be processed together (e.g., matching timestamps)

---

<a name="recipe-24"></a>
### Recipe 24: AsyncSequence with Timeout

**Problem:** Need to timeout async sequence iteration after a duration.

**Solution:**
```swift
extension AsyncSequence {
    func timeout(after duration: Duration) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for try await element in self {
                    continuation.yield(element)
                }
                continuation.finish()
            }

            Task {
                try await Task.sleep(for: duration)
                task.cancel()
                continuation.finish(throwing: TimeoutError())
            }
        }
    }
}

// Usage
let stream = networkStream().timeout(after: .seconds(30))

do {
    for try await data in stream {
        process(data)
    }
} catch is TimeoutError {
    print("Operation timed out")
}
```

**When to use:**

**Real-World Scenarios:**
- **API Timeouts:** Network requests shouldn't hang forever
- **User Input Deadlines:** Form submission must complete within time limit
- **Resource Allocation:** Claim resources or timeout and retry
- **Batch Processing:** Process items with time budget per item

**Specific Examples:**
- Payment processing: 30-second timeout for payment gateway response
- Search queries: 5-second timeout for search results
- File uploads: 60-second timeout per chunk upload
- Database queries: 10-second timeout for complex queries

**Timeout Strategies:**
1. **Hard Timeout**: Cancel immediately at deadline
2. **Soft Timeout**: Try again with cached/fallback data
3. **Progressive Timeout**: Extend deadline if making progress

**Common Timeouts:**
- UI operations: 3-5 seconds
- API calls: 30-60 seconds
- Background sync: 5 minutes
- Long operations: 15 minutes

---

<a name="recipe-25"></a>
### Recipe 25: Buffering AsyncSequence Elements

**Problem:** Consumer is slower than producer, need to buffer elements.

**Solution:**
```swift
extension AsyncSequence {
    func buffered(limit: Int) -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: .bufferingNewest(limit)) { continuation in
            Task {
                for await element in self {
                    continuation.yield(element)
                }
                continuation.finish()
            }
        }
    }
}

// Usage
let buffered = highFrequencyStream.buffered(limit: 100)

for await value in buffered {
    await slowProcess(value)
}
```

**When to use:**

**Real-World Scenarios:**
- **High-Frequency Sensors:** GPS/accelerometer producing faster than processing
- **Log Streaming:** Application logging faster than UI can display
- **Stock Tickers:** Market data updates faster than chart can render
- **Video Processing:** Camera frames faster than ML model can process

**Specific Examples:**
- Fitness app: Accelerometer at 100Hz, buffer latest 50 for gesture detection
- Trading app: Price updates at 1000/sec, buffer latest 100 for chart
- Game: Network updates at 60fps, buffer latest 10 for interpolation
- Video editor: Buffer 120 frames for scrubbing preview

**Buffer Sizing:**
- Too small: Drops important data
- Too large: Increases latency, memory usage
- Rule of thumb: 2-5x consumer processing rate

**Backpressure Handling:**
- .bufferingNewest: Always current (real-time data)
- .bufferingOldest: Fair queue (events must be processed)
- .unbounded: No drops (risk OOM)

---

## Synchronization

<a name="recipe-26"></a>
### Recipe 26: Actor-Based Mutex Pattern

**Problem:** Need mutual exclusion for critical sections.

**Solution:**
```swift
actor Mutex<T> {
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<Result>(_ operation: (inout T) async throws -> Result) async rethrows -> Result {
        try await operation(&value)
    }

    func get() -> T {
        value
    }

    func set(_ newValue: T) {
        value = newValue
    }
}

// Usage
let counter = Mutex(0)

await counter.withLock { count in
    count += 1
}

let current = await counter.get()
```

**When to use:**

**Real-World Scenarios:**
- **Resource Pooling:** Manage limited connection/thread pools
- **Counter Synchronization:** Thread-safe counters, statistics
- **Configuration Updates:** Atomic configuration changes
- **Retry Coordination:** Serialize retry attempts across tasks

**Specific Examples:**
- Database connection pool: Mutex protecting available connections
- Rate limiter: Counter tracking API calls with exclusive increment
- Feature flag manager: Atomic reads/writes of configuration
- Download manager: Coordinate concurrent downloads to same file

**Why Actor-Based Mutex:**
- Compiler-enforced correctness (vs manual locks)
- No deadlocks (actors can't deadlock themselves)
- Async-friendly (works with suspension)
- Composable with other async code

**Actor Mutex vs NSLock:**
| Feature | Actor Mutex | NSLock |
|---------|-------------|--------|
| Thread-safe | ✅ | ✅ |
| Async-compatible | ✅ | ❌ Blocks thread |
| Deadlock-free | ✅ | ❌ Can deadlock |
| Compiler-checked | ✅ | ❌ Runtime only |

---

<a name="recipe-27"></a>
### Recipe 27: Using AsyncLock for Critical Sections

**Problem:** Need to serialize access to non-Sendable resources.

**Solution:**
```swift
actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            isLocked = false
        }
    }

    func withLock<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { Task { await release() } }
        return try await operation()
    }
}

// Usage
let lock = AsyncLock()

await lock.withLock {
    // Critical section
    updateSharedResource()
}
```

**When to use:**

**Real-World Scenarios:**
- **File System Access:** Serialize writes to prevent corruption
- **Hardware Resources:** Exclusive access to camera, audio device
- **Legacy Library Wrapping:** Protect non-thread-safe C/ObjC libraries
- **Initialization Guarantees:** Ensure single initialization of expensive resources

**Specific Examples:**
- File writer: Ensure one write at a time to log file
- Camera manager: Only one component can access camera at once
- SQLite wrapper: Serialize queries (SQLite isn't thread-safe by default)
- Asset loader: Load expensive assets one at a time

**AsyncLock Use Cases:**
- Wrapping non-Sendable types that can't become actors
- Protecting external resources (files, hardware)
- Migration from locks to async (gradual transition)

**Warning:** Most use cases better served by actors. Use AsyncLock only when:
1. Wrapping legacy/external non-Sendable resources
2. Need explicit lock/unlock semantics
3. Temporary migration pattern

---

<a name="recipe-28"></a>
### Recipe 28: Coordinating Multiple Async Operations

**Problem:** Need to wait for multiple conditions before proceeding.

**Solution:**
```swift
actor Coordinator {
    private var conditions: Set<String> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal(_ condition: String) {
        conditions.insert(condition)
        checkAndResumeWaiters()
    }

    func waitForAll(_ required: Set<String>) async {
        if required.isSubset(of: conditions) {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func checkAndResumeWaiters() {
        // Check if all conditions met and resume waiters
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

// Usage
let coordinator = Coordinator()

Task {
    await coordinator.signal("dataLoaded")
}

Task {
    await coordinator.signal("uiReady")
}

await coordinator.waitForAll(["dataLoaded", "uiReady"])
print("All systems ready!")
```

**When to use:**

**Real-World Scenarios:**
- **App Launch Coordination:** Wait for database, network, auth before showing UI
- **Multi-Service Initialization:** Start services, wait for all to be ready
- **Dependency Management:** Wait for dependencies before starting dependent services
- **Phased Rollout:** Coordinate phases (prepare → activate → finalize)

**Specific Examples:**
- App startup: Wait for CoreData + Auth + Remote Config before splash → home
- Game loading: Wait for assets + shaders + audio before starting gameplay
- CI/CD: Wait for build + test + lint before deploying
- Migration: Wait for schema migration + data migration before app launch

**Real-World Pattern:**
```swift
// App Launcher
let coordinator = Coordinator()

Task { await database.initialize(); await coordinator.signal("db") }
Task { await auth.login(); await coordinator.signal("auth") }
Task { await config.fetch(); await coordinator.signal("config") }

await coordinator.waitForAll(["db", "auth", "config"])
// Now safe to launch app!
```

**Alternative: TaskGroup**
For simple all-complete scenarios, TaskGroup is simpler. Use Coordinator when:
- Partial completion triggers actions
- Complex dependency graphs
- Need to signal from different contexts

---

<a name="recipe-29"></a>
### Recipe 29: Debouncing with AsyncStream

**Problem:** High-frequency events need to be debounced to last value.

**Solution:**
```swift
extension AsyncStream {
    func debounce(for duration: Duration) -> AsyncStream<Element> {
        AsyncStream { continuation in
            Task {
                var iterator = self.makeAsyncIterator()
                var lastValue: Element?
                var debounceTask: Task<Void, Never>?

                while let value = await iterator.next() {
                    lastValue = value
                    debounceTask?.cancel()

                    debounceTask = Task {
                        try? await Task.sleep(for: duration)
                        if let value = lastValue {
                            continuation.yield(value)
                        }
                    }
                }

                continuation.finish()
            }
        }
    }
}

// Usage
let searchStream = textFieldStream.debounce(for: .milliseconds(300))

for await searchText in searchStream {
    await performSearch(searchText)
}
```

**When to use:**

**Real-World Scenarios:**
- **Search-as-you-type:** Debounce user typing, query after pause
- **Autosave:** Debounce document changes, save after editing stops
- **Form Validation:** Validate after user stops typing
- **Window Resize:** Recalculate layout after resizing stops

**Specific Examples:**
- Search bar: User types "hello" → only search after 300ms pause (not 5 times)
- Text editor: Auto-save document 2 seconds after last keystroke
- Password validation: Check strength 500ms after user stops typing
- Map zoom: Reload tiles after user stops zooming for 200ms

**Debounce vs Throttle:**
- **Debounce**: Wait for quiet period, execute ONCE after silence
- **Throttle**: Execute at MOST once per time period, even if still active

**Use Debounce when:**
- Want to wait for user to finish (search, form input)
- Only care about final state (window size, slider position)
- Expensive operation shouldn't run repeatedly

**Performance Impact:**
```swift
// Without debounce: 5 searches for "hello" (h, he, hel, hell, hello)
// With 300ms debounce: 1 search for "hello" after pause
// 5x fewer network requests!
```

---

<a name="recipe-30"></a>
### Recipe 30: Throttling High-Frequency Events

**Problem:** Need to limit event rate to prevent overload.

**Solution:**
```swift
extension AsyncStream {
    func throttle(for duration: Duration) -> AsyncStream<Element> {
        AsyncStream { continuation in
            Task {
                var iterator = self.makeAsyncIterator()
                var lastYieldTime: ContinuousClock.Instant?

                while let value = await iterator.next() {
                    let now = ContinuousClock.now

                    if let last = lastYieldTime {
                        let elapsed = now - last
                        if elapsed < duration {
                            continue
                        }
                    }

                    continuation.yield(value)
                    lastYieldTime = now
                }

                continuation.finish()
            }
        }
    }
}

// Usage
let locationStream = gpsUpdates.throttle(for: .seconds(1))

for await location in locationStream {
    updateMap(with: location)
}
```

**When to use:**

**Real-World Scenarios:**
- **GPS Updates:** Location updates every 100ms, but only process every 1s
- **Sensor Data:** Accelerometer at 100Hz, throttle to 10Hz for processing
- **Scroll Events:** Infinite scroll triggering, throttle to prevent duplicate loads
- **API Rate Limiting:** Allow 1 request per second maximum

**Specific Examples:**
- Navigation app: GPS updates 10x/sec, throttle to 1x/sec for UI updates
- Fitness tracker: Heart rate sensor 60Hz, throttle to 1Hz for display
- Social feed: Scroll event triggers, throttle to 1 per 500ms to load more posts
- Analytics: Button click tracking, throttle to prevent duplicate events

**Throttle vs Debounce:**
- **Throttle**: Execute at regular intervals while active (continuous updates)
- **Debounce**: Execute once after quiet period (wait for completion)

**Use Throttle when:**
- High-frequency events need rate limiting (GPS, sensors)
- Want regular updates while activity ongoing (not just at end)
- Enforcing API rate limits
- Reducing UI update frequency

**Real Example:**
```swift
// GPS updates 10/sec throttled to 1/sec
// 90% reduction in UI updates, 10% latency increase
// User doesn't notice 1-second delay, but UI stays smooth
```

---

## Error Handling

<a name="recipe-31"></a>
### Recipe 31: Structured Error Propagation

**Problem:** Need to propagate errors through async call chains clearly.

**Solution:**
```swift
enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingFailed
}

func fetchAndDecode<T: Decodable>(url: URL) async throws -> T {
    guard url.scheme == "https" else {
        throw NetworkError.invalidURL
    }

    let (data, _) = try await URLSession.shared.data(from: url)

    guard !data.isEmpty else {
        throw NetworkError.noData
    }

    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw NetworkError.decodingFailed
    }
}

// Usage with detailed error handling
do {
    let user: User = try await fetchAndDecode(url: userURL)
    print(user)
} catch NetworkError.invalidURL {
    print("Invalid URL scheme")
} catch NetworkError.noData {
    print("No data received")
} catch NetworkError.decodingFailed {
    print("Failed to decode response")
} catch {
    print("Unexpected error: \\(error)")
}
```

**When to use:**

**Real-World Scenarios:**
- **API Integration:** Clear error types for network, parsing, validation failures
- **Form Validation:** Specific errors for each validation rule
- **File Operations:** Distinguish not-found, permission-denied, disk-full
- **Multi-Layer Systems:** Errors propagate through layers with context

**Specific Examples:**
- REST API client: NetworkError.timeout, .invalidResponse, .serverError(code)
- Payment processing: PaymentError.declined, .insufficientFunds, .invalidCard
- File upload: UploadError.fileTooLarge, .unsupportedType, .quotaExceeded
- Authentication: AuthError.invalidCredentials, .accountLocked, .sessionExpired

**Error Design Principles:**
1. **Specific Error Types**: Enum with associated values
2. **Actionable Messages**: User knows what went wrong and how to fix
3. **Contextual Information**: Include relevant data (status code, field name)
4. **Recovery Suggestions**: LocalizedError.recoverySuggestion

**Best Practices:**
```swift
// ✅ Good: Specific, actionable
throw ValidationError.emailInvalid(email)

// ❌ Bad: Generic, unhelpful
throw NSError(domain: "Error", code: -1)
```

---

<a name="recipe-32"></a>
### Recipe 32: Retry Logic with Exponential Backoff

**Problem:** Operations fail transiently and should be retried with increasing delays.

**Solution:**
```swift
func retry<T>(
    maxAttempts: Int = 3,
    initialDelay: Duration = .seconds(1),
    multiplier: Double = 2.0,
    operation: () async throws -> T
) async throws -> T {
    var currentDelay = initialDelay

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            if attempt == maxAttempts {
                throw error
            }

            print("Attempt \\(attempt) failed, retrying in \\(currentDelay)...")
            try await Task.sleep(for: currentDelay)
            currentDelay = currentDelay * multiplier
        }
    }

    fatalError("Unreachable")
}

// Usage
let data = try await retry(maxAttempts: 5) {
    try await downloadFile(from: url)
}
```

**When to use:**

**Real-World Scenarios:**
- **Network Failures:** Retry transient errors (timeout, 503), not permanent (404, 401)
- **Database Locks:** Retry on deadlock/busy, exponential backoff
- **Rate Limiting:** Retry after delay when rate-limited (429)
- **Cloud Services:** Retry on temporary service unavailability

**Specific Examples:**
- API calls: Retry 3x with 1s, 2s, 4s delays for network errors
- Database writes: Retry 5x with exponential backoff for lock contention
- File uploads: Retry with backoff for 503 Service Unavailable
- Authentication: Retry token refresh on transient network errors

**Exponential Backoff Benefits:**
- Gives system time to recover
- Reduces thundering herd (all clients retrying simultaneously)
- Industry standard (AWS, Google APIs use this)

**When NOT to Retry:**
- Client errors (400, 401, 403, 404) - won't succeed on retry
- Data validation errors - need user correction
- Permanent failures - waste resources

**Common Retry Configs:**
- **Quick operations**: 3 retries, 1s initial, 2x multiplier = 1s, 2s, 4s
- **Important operations**: 5 retries, 2s initial, 2x multiplier = 2s, 4s, 8s, 16s, 32s
- **Background sync**: 10 retries, 5s initial, 1.5x multiplier

---

<a name="recipe-33"></a>
### Recipe 33: Timeout Implementation

**Problem:** Operations should fail after maximum duration.

**Solution:**
```swift
func withTimeout<T>(
    duration: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// Usage
do {
    let data = try await withTimeout(duration: .seconds(30)) {
        try await fetchLargeFile()
    }
} catch is TimeoutError {
    print("Operation timed out")
}
```

**When to use:**

**Real-World Scenarios:**
- **API Calls:** Don't let network requests hang indefinitely
- **Database Queries:** Complex queries should timeout, not block forever
- **User Operations:** Show error after reasonable time, don't freeze UI
- **Resource Acquisition:** Timeout waiting for locks, connections

**Specific Examples:**
- Payment gateway: 30s timeout for payment processing
- Search API: 5s timeout, show "still loading" if exceeded
- Image upload: 60s per image, fail and retry if exceeded
- WebSocket connect: 10s timeout, fallback to polling

**Timeout Implementation Strategies:**

1. **Task Race Pattern** (shown in recipe):
   - Two tasks: operation + sleep
   - Whichever completes first wins
   - Cancel the other

2. **Deadline Pattern**:
   - Calculate deadline = now + timeout
   - Check deadline before each step

3. **System Timeout**:
   - URLSession has built-in timeoutInterval
   - Use when available

**User Experience:**
- Short timeout (3-5s): Show inline error, allow retry
- Medium timeout (30-60s): Show progress, "still working..."
- Long timeout (5+ min): Background operation, notification on completion

---

<a name="recipe-34"></a>
### Recipe 34: Graceful Degradation

**Problem:** Fallback to cached/default data when primary source fails.

**Solution:**
```swift
actor DataManager {
    private var cache: [String: Data] = [:]

    func fetchWithFallback(key: String, url: URL) async -> Data {
        do {
            // Try network first
            let data = try await download(from: url)
            cache[key] = data
            return data
        } catch {
            // Fall back to cache
            if let cached = cache[key] {
                print("Using cached data")
                return cached
            }

            // Final fallback to default
            print("Using default data")
            return defaultData
        }
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Offline-First Apps:** Show cached content when network unavailable
- **CDN Fallbacks:** Try CDN, fall back to origin server
- **Multi-Source Data:** Try primary API, fall back to secondary
- **Default Content:** Show placeholder when real content fails to load

**Specific Examples:**
- News app: Try network → cache → show "offline" message
- Image loading: Try CDN → origin server → placeholder image
- Weather app: Try live API → cached forecast → generic advice
- Configuration: Try remote config → local config → hardcoded defaults

**Fallback Strategy Levels:**

1. **Level 1 - Primary Source**: Live network data
2. **Level 2 - Cached Data**: Slightly stale but usable
3. **Level 3 - Default Data**: Generic/placeholder
4. **Level 4 - Graceful Failure**: Error message, retry button

**Real-World Pattern:**
```swift
// Try primary
do {
    return try await fetchFromNetwork()
} catch {
    // Try secondary
    if let cached = await cache.get(key) {
        return cached
    }
    // Fallback to default
    return defaultValue
}
```

**Progressive Enhancement:**
- Load placeholder immediately (Level 3)
- Replace with cache if available (Level 2)
- Replace with live data when loaded (Level 1)

---

<a name="recipe-35"></a>
### Recipe 35: Error Recovery in Task Groups

**Problem:** Some tasks in group can fail, but work should continue.

**Solution:**
```swift
func fetchAllWithRecovery(urls: [URL]) async -> [Result<Data, Error>] {
    await withTaskGroup(of: (Int, Result<Data, Error>).self) { group in
        for (index, url) in urls.enumerated() {
            group.addTask {
                let result = await Result {
                    try await download(from: url)
                }
                return (index, result)
            }
        }

        var results = Array(repeating: Result<Data, Error>.failure(MissingDataError()), count: urls.count)

        for await (index, result) in group {
            results[index] = result
        }

        return results
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Batch Processing:** Process 1000 items, some fail - continue with rest
- **Multi-Endpoint Sync:** Sync with multiple services, some might be down
- **Parallel Validation:** Validate multiple fields, collect all errors
- **Distributed Operations:** Operation across multiple nodes, partial failure OK

**Specific Examples:**
- Email service: Send to 100 recipients, track successes/failures per recipient
- Data migration: Migrate 10000 records, collect failures for manual review
- Multi-cloud backup: Backup to AWS + Azure + GCP, succeed if 2/3 work
- Form validation: Check all fields, show all errors (not just first)

**Result Pattern Benefits:**
- All operations complete (no early exit)
- Per-item success/failure tracking
- Detailed error reporting
- Partial success scenarios

**Error Analysis:**
```swift
let results = await processWithRecovery(items)

let successes = results.compactMap { try? $0.get() }
let failures = results.compactMap { result in
    if case .failure(let error) = result { return error }
    return nil
}

print("✅ \(successes.count) succeeded")
print("❌ \(failures.count) failed")
// Report detailed failures for investigation
```

**Use Cases:**
- **Must complete all**: Use Result pattern
- **Stop on first error**: Use ThrowingTaskGroup
- **Mixed approach**: Some failures OK, but too many = abort

---

## Advanced Patterns

<a name="recipe-36"></a>
### Recipe 36: Custom TaskExecutor Implementation

**Problem:** Need custom execution context for specialized scheduling.

**Solution:**
```swift
import Dispatch

final class QueueExecutor: TaskExecutor, @unchecked Sendable {
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func enqueue(_ job: consuming ExecutorJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }
}

// Usage
let customQueue = DispatchQueue(label: "com.app.custom")
let executor = QueueExecutor(queue: customQueue)

Task(executorPreference: executor) {
    // Runs on custom queue
    await performWork()
}
```

**When to use:**

**Real-World Scenarios:**
- **Legacy Integration:** Integrate async/await with existing DispatchQueue-based code
- **Custom Scheduling:** Specialized scheduling requirements (real-time, priority queues)
- **Performance Tuning:** Control exactly which queue tasks run on
- **Migration Path:** Gradual migration from GCD to Swift Concurrency

**Specific Examples:**
- Audio processing app: Tasks must run on real-time priority queue
- Game engine: Render tasks on dedicated high-priority queue
- Database library: Serialize all operations on custom serial queue
- Legacy framework: Wrap existing queue-based API with TaskExecutor

**When to Use:**
- Bridging legacy GCD code during migration
- Performance-critical code needing specific queue
- Third-party libraries requiring specific execution context
- Gradual adoption of Swift Concurrency

**When NOT to Use:**
- New code (use actors, TaskGroups instead)
- No specific queue requirements (default executor is fine)
- Performance not critical (overhead not worth complexity)

**Warning:** TaskExecutor is advanced API. Most apps don't need it. Consider:
1. Can actors solve your problem? (Usually yes)
2. Is default executor insufficient? (Usually no)
3. Do you have specific queue requirements? (Rarely)

---

<a name="recipe-37"></a>
### Recipe 37: SerialExecutor for Actor Customization

**Problem:** Actor needs to run on specific execution context (e.g., main queue).

**Solution:**
```swift
final class MainQueueExecutor: SerialExecutor, @unchecked Sendable {
    func enqueue(_ job: consuming ExecutorJob) {
        DispatchQueue.main.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

actor MainQueueActor {
    nonisolated let unownedExecutor: UnownedSerialExecutor

    init() {
        let executor = MainQueueExecutor()
        self.unownedExecutor = executor.asUnownedSerialExecutor()
    }

    func updateUI() {
        // Guaranteed to run on main queue
        print("On main thread: \\(Thread.isMainThread)")
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Main Thread Actors:** Custom actor guaranteed to run on main thread (like MainActor)
- **Serial Queue Actors:** Actor with specific serial queue for legacy compatibility
- **Real-Time Actors:** Audio/video processing actors on real-time priority queue
- **Testing:** Mock executors for deterministic actor testing

**Specific Examples:**
- UI framework: CustomUIActor running on main queue (alternative to @MainActor)
- Database wrapper: DatabaseActor running on dedicated serial queue
- Audio engine: AudioProcessorActor on real-time priority thread
- Test framework: TestExecutor for synchronous actor testing

**MainActor Under the Hood:**
```swift
// MainActor is essentially:
@globalActor
actor MainActor {
    static let shared = MainActor(executor: MainQueueExecutor())
}

// Where MainQueueExecutor is a SerialExecutor
final class MainQueueExecutor: SerialExecutor {
    func enqueue(_ job: consuming ExecutorJob) {
        DispatchQueue.main.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
}
```

**Custom Global Actor Pattern:**
```swift
@globalActor
actor DatabaseActor {
    static let shared = DatabaseActor(executor: DatabaseExecutor())
}

// Now use like MainActor:
@DatabaseActor
func queryDatabase() { ... }
```

**Extreme Caution:** SerialExecutor is expert-level API. Bugs can cause:
- Deadlocks
- Data races
- Crashes
- Performance issues

Only use if you deeply understand Swift Concurrency internals.

---

<a name="recipe-38"></a>
### Recipe 38: Unstructured Tasks and Detached Tasks

**Problem:** Need long-lived tasks independent of current context.

**Solution:**
```swift
// Unstructured task (inherits context)
class BackgroundService {
    private var task: Task<Void, Never>?

    func start() {
        task = Task {
            while !Task.isCancelled {
                await performBackgroundWork()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
    }
}

// Detached task (no context inheritance)
Task.detached(priority: .background) {
    await performIndependentWork()
}

// Long-lived service
actor DataSyncService {
    private var syncTask: Task<Void, Never>?

    func startSyncing() {
        syncTask = Task {
            for await update in remoteUpdates {
                await processUpdate(update)
            }
        }
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **Background Services:** Long-running services independent of current context
- **Fire-and-Forget Operations:** Analytics, logging that shouldn't inherit priority
- **Persistent Tasks:** Tasks that outlive their creating scope
- **Global Singletons:** Singleton services managing their own task lifecycle

**Specific Examples:**
- Analytics service: Background task continuously processing events
- Location tracker: Long-running task monitoring location, updating server
- Sync manager: Persistent task syncing local changes to server
- Download queue: Service managing multiple unstructured download tasks

**Task vs Task.detached:**

| Feature | Task | Task.detached |
|---------|------|---------------|
| Priority inheritance | ✅ Inherits | ❌ Independent |
| Task-local values | ✅ Inherits | ❌ None |
| Actor context | ✅ Inherits | ❌ None |
| Cancellation propagation | ✅ Parent→child | ❌ Independent |
| Use case | Related work | Truly independent |

**Common Pattern:**
```swift
class BackgroundService {
    private var task: Task<Void, Never>?

    func start() {
        task = Task {
            while !Task.isCancelled {
                await performWork()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
```

**Lifecycle Management:**
- Store Task handle to cancel later
- Check Task.isCancelled in long loops
- Clean up resources on cancellation
- Don't leak unstructured tasks (always store handle if you might need to cancel)

---

<a name="recipe-39"></a>
### Recipe 39: AsyncSequence Operators Chaining

**Problem:** Complex transformations need multiple operators chained.

**Solution:**
```swift
let stream = AsyncStream<Int> { continuation in
    for i in 1...100 {
        continuation.yield(i)
    }
    continuation.finish()
}

let processed = stream
    .filter { $0 % 2 == 0 }           // Keep even numbers
    .map { $0 * 2 }                   // Double them
    .prefix(10)                        // Take first 10
    .dropFirst(2)                      // Skip first 2

for await value in processed {
    print(value)
}

// Custom operator
extension AsyncSequence {
    func mapAsync<T>(_ transform: @escaping (Element) async throws -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await element in self {
                        let transformed = try await transform(element)
                        continuation.yield(transformed)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

**When to use:**

**Real-World Scenarios:**
- **ETL Pipelines:** Extract → Transform → Load data processing
- **Real-Time Processing:** Sensor data through multiple processing stages
- **Data Cleansing:** Raw data → validate → normalize → enrich → store
- **Reactive UI:** User input → debounce → validate → transform → render

**Specific Examples:**
- Log processor: Raw logs → parse → filter → aggregate → store
- Image pipeline: URLs → download → resize → compress → upload → thumbnail
- Analytics: Events → filter → transform → batch → send to server
- Search: Query → debounce → validate → search → highlight → rank → display

**AsyncSequence Operator Patterns:**

```swift
// Complex pipeline example
let results = rawEvents
    .filter { $0.userId == currentUser }     // Filter relevant
    .map { parseEvent($0) }                   // Transform
    .compactMap { try? validate($0) }        // Validate (drop invalid)
    .prefix(100)                              // Limit results
    .buffer(limit: 10)                        // Backpressure
    .debounce(for: .milliseconds(300))       // Rate limit
```

**Custom Operators:**
```swift
extension AsyncSequence {
    // Batch elements
    func batched(size: Int) -> AsyncStream<[Element]> { ... }

    // Rate limit
    func rateLimit(_ interval: Duration) -> AsyncStream<Element> { ... }

    // Retry on failure
    func retry(maxAttempts: Int) -> AsyncThrowingStream<Element, Error> { ... }
}
```

**Performance:**
- Lazy evaluation - no intermediate collections
- Memory efficient - processes one at a time
- Composable - mix standard + custom operators
- Type-safe - compiler validates pipeline

---

<a name="recipe-40"></a>
### Recipe 40: Building Reactive Pipelines

**Problem:** Need complex reactive data flow with transformations and side effects.

**Solution:**
```swift
actor ReactivePipeline<Input, Output> {
    typealias Transform = (Input) async throws -> Output

    private let input: AsyncStream<Input>
    private var transforms: [Any] = []

    init(input: AsyncStream<Input>) {
        self.input = input
    }

    func map<T>(_ transform: @escaping (Output) async throws -> T) -> ReactivePipeline<Input, T> {
        let newPipeline = ReactivePipeline<Input, T>(input: self.input)
        newPipeline.transforms = self.transforms + [transform]
        return newPipeline
    }

    func sink(_ handler: @escaping (Output) async -> Void) async {
        for await value in input {
            // Apply all transforms
            var current: Any = value
            for transform in transforms {
                // Apply transform (simplified)
                current = value
            }

            if let output = current as? Output {
                await handler(output)
            }
        }
    }
}

// Usage
await ReactivePipeline(input: eventStream)
    .map { $0.userId }
    .map { await fetchUser($0) }
    .sink { user in
        print("Processed user: \\(user.name)")
    }
```

**When to use:**

**Real-World Scenarios:**
- **Reactive UI:** User interactions → business logic → state updates → UI rendering
- **Event-Driven Systems:** Events flow through processing pipeline
- **Data Streaming:** Continuous data through transformations and side effects
- **Complex Workflows:** Multi-stage processing with branching/merging

**Specific Examples:**
- Search app: Keystrokes → debounce → API call → parse → filter → render
- Trading platform: Price updates → filter by symbol → calculate indicators → update chart
- IoT dashboard: Sensor readings → validate → aggregate → alert → store → visualize
- Chat app: Messages → filter → translate → moderate → store → render

**Reactive Pipeline Pattern:**
```swift
// Event Source
let userActions: AsyncStream<UserAction> = ...

// Processing Pipeline
await userActions
    .filter { $0.isValid }                    // Validation
    .map { await processAction($0) }         // Business logic
    .map { await updateState($0) }           // State management
    .sink { result in                         // Side effects
        await updateUI(result)
        await logAnalytics(result)
    }
```

**Comparison with Combine:**

| Feature | Reactive Pipeline (async/await) | Combine |
|---------|--------------------------------|---------|
| Learning curve | Simpler (just async/await) | Steeper (operators) |
| Type system | Native Swift | Custom types |
| Error handling | Standard try/catch | Failure type |
| Backpressure | Natural (await) | Manual |
| Performance | Excellent | Excellent |
| iOS Version | iOS 13+ (async) | iOS 13+ |

**When to Use:**
- Complex event-driven logic
- Multiple transformation stages
- Side effects at various points
- Backpressure handling needed

**Migration Path from Combine:**
- Publishers → AsyncStream
- map/filter/compactMap → same operators on AsyncSequence
- sink → for await loop or custom sink
- .eraseToAnyPublisher() → AsyncStream type erasure

---

## Appendix

### Compiler Flags for Strict Concurrency

Add to your Swift compiler flags for maximum safety:

```bash
-Xfrontend -strict-concurrency=complete
-Xfrontend -warn-concurrency
-Xfrontend -enable-actor-data-race-checks
```

### Common Pitfalls

1. **Actor Reentrancy:** Actors can be reentered at suspension points
2. **Capture Lists:** Be careful with weak/unowned in async closures
3. **Task Cancellation:** Not all APIs check for cancellation automatically
4. **Sendable Conformance:** Ensure thread-safe types conform to Sendable
5. **MainActor Isolation:** UI updates must be on MainActor

### Further Reading

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Swift Evolution Proposals](https://github.com/apple/swift-evolution)
  - SE-0296: Async/await
  - SE-0306: Actors
  - SE-0314: AsyncStream
  - SE-0417: Task Executor API

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**Extracted From:** Apple Developer Documentation (/Volumes/Code/DeveloperExt/cupertinodocs/)

# Swift 6 Language Mode: Structured Concurrency & Actor Rules

## Documentation Sources
- SE-0296: Async/Await (Swift 5.5)
- SE-0304: Structured Concurrency (Swift 5.5)
- SE-0306: Actors (Swift 5.5)
- SE-0317: async let bindings (Swift 5.5)
- SE-0302: Sendable and @Sendable closures (Swift 5.5)
- SE-0313: Improved control over actor isolation (Swift 5.7)
- SE-0338: Clarify execution of non-actor-isolated async functions (Swift 5.7)
- SE-0337: Incremental migration to concurrency checking (Swift 5.7)
- SE-0381: DiscardingTaskGroup (Swift 5.9)
- SE-0414: Region-based Isolation (Swift 6.0)
- SE-0430: transferring isolation regions of parameter and result values (Swift 6.0)
- Swift 6.0 Language Mode Documentation

> **Note:** Swift 6 refers to the **language mode**, not the compiler version. You can use Swift 6 language mode with Swift 5.10+ compilers.

---

## PART 1: TASKS & STRUCTURED CONCURRENCY

### Rule 1: Task Fundamentals
**Swift Version:** 5.5+
**Source:** SE-0304:127-136

- **Every asynchronous function runs as part of a task**
- A task runs **one function at a time** (no internal concurrency within the task)
- When an async function calls another async function, it runs in the **same task**
- Tasks can be in three states: **suspended**, **running**, or **completed**
- A suspended task may be:
  - **Schedulable**: ready to run, waiting for available thread
  - **Waiting**: blocked on external event (I/O, timer, etc.)

**Critical Understanding:**
```swift
// The same TASK can run on DIFFERENT threads
func example() async {
    print(Thread.current)  // Thread A
    await someWork()       // Suspends task
    print(Thread.current)  // Might be Thread B!
    // Same task, potentially different thread
}
```

### Rule 2: Child Tasks Must Complete Before Parent Returns
**Swift Version:** 5.5+
**Source:** SE-0304:164-167

> "A function that creates a child task must wait for it to end before returning. This structure means that functions can locally reason about all the work currently being done for the current task."

- **Child tasks have bounded duration** - cannot outlast parent
- Must **implicitly or explicitly await** all child tasks before scope exits
- This enables **static reasoning** about task trees
- Cancellation propagates **downward only** (not upward to parent)

### Rule 3: Task Groups
**Swift Version:** 5.5+
**Source:** SE-0304:210-249

- **withThrowingTaskGroup** creates a scope for child tasks
- All child tasks must **complete when scope exits**
- Child tasks are **implicitly cancelled** if scope exits with error
- Results can be collected **in completion order** (not submission order)
- Task groups uphold **structured concurrency guarantees**

```swift
try await withThrowingTaskGroup(of: Result.self) { group in
    group.addTask { /* work */ }
    // Must consume all results before exiting
    for try await result in group {
        // Process results
    }
    // Scope exit waits for all tasks
}
```

### Rule 3a: Discarding Task Groups
**Swift Version:** 5.9+
**Source:** SE-0381

Use `withDiscardingTaskGroup` when you don't need results:

```swift
await withDiscardingTaskGroup { group in
    for item in items {
        group.addTask {
            await process(item)
            // Results automatically discarded
        }
    }
    // Implicitly awaits all tasks, but doesn't collect results
}
```

**Benefits:**
- More efficient - no memory allocated for results
- Clearer intent in code
- No need for `for await _ in group {}`

### Rule 4: Task Priority
**Swift Version:** 5.5+
**Source:** SE-0304:186-205

- Child tasks **automatically inherit parent priority**
- Detached tasks **do not inherit** priority (no parent)
- **Priority escalation** occurs when:
  - Higher-priority task waits for lower-priority task
  - Higher-priority task enqueued on same actor
- Executors **should** (not "must") **honor priority over submission order**

### Rule 5: async let Implicit Cancellation & Awaiting
**Swift Version:** 5.5+
**Source:** SE-0317:304-330

> "As we return from the function without ever having awaited on the values, both of them will be **implicitly cancelled and awaited on** before returning"

- **CRITICAL:** Unused `async let` tasks are **implicitly awaited** at scope exit
- Function always takes **max(time(task1), time(task2), ...)** to complete
- Cannot "early return" without awaiting remaining tasks
- **Implicit cancellation happens, but task still waits to complete**

```swift
async let f = fast()  // 300ms
async let s = slow()  // 3s
return "done"
// implicitly: f.cancel()
// implicitly: s.cancel()
// implicitly: await f  ← STILL WAITS for cancellation to complete
// implicitly: await s  ← STILL WAITS
// Total time: 3 seconds (not instant!)
```

**Important:** Cancellation is **cooperative**. The `slow()` task might take the full 3s even when cancelled!

### Rule 6: async let vs Task Groups for Racing
**Swift Version:** 5.5+
**Source:** SE-0317:501-517

- **async let does NOT implement racing** (implicit await defeats it)
- For **true racing**, use **withThrowingTaskGroup** + `group.next()`
- Racing pattern:

```swift
try await withThrowingTaskGroup(of: Result.self) { group in
    group.addTask { /* option 1 */ }
    group.addTask { /* option 2 */ }

    guard let winner = try await group.next() else {
        throw Error()
    }

    group.cancelAll()  // Cancel loser

    // IMPORTANT: Even after cancelAll(), drain remaining results
    // if tasks could complete before cancellation takes effect
    for try await _ in group {
        // Discard any additional results
    }

    return winner
}
```

---

## PART 2: ACTORS

### Rule 7: Actor Isolation
**Swift Version:** 5.5+
**Source:** SE-0306:84-109

- Actors protect mutable state through **actor isolation**
- Stored instance properties can **only be accessed on self**
- All instance members are **actor-isolated by default**
- Actor-isolated code can freely reference other **actor-isolated on same instance**
- **Non-isolated** code cannot synchronously access actor-isolated state

### Rule 8: Cross-Actor References
**Swift Version:** 5.5+
**Source:** SE-0306:111-117

Two ways to access actor-isolated state from outside:

1. **Immutable state** (let constants with value types) - synchronous OK
2. **Async function calls** - turned into messages in actor's mailbox

```swift
actor BankAccount {
    let accountNumber: Int     // ✓ Can access synchronously
    var balance: Double        // ✗ Must use async

    func deposit(amount: Double) async {
        balance += amount
    }
}

let account = BankAccount(...)
print(account.accountNumber)    // ✓ Synchronous OK
await account.deposit(100)      // ✓ Async required
```

### Rule 9: Actor Reentrancy & State Validation
**Swift Version:** 5.5+
**Source:** SE-0306:18-23, SE-0306:299-448

- Actors are **reentrant by default**
- After an `await`, actor state **may have changed**
- Multiple tasks can be **suspended** in same actor
- Only **one task executes** at a time
- Must **not assume state unchanged** after suspension points

**Critical Example:**
```swift
actor DecisionMaker {
    var opinion: Decision = .noIdea

    func thinkOfGoodIdea() async -> Decision {
        opinion = .goodIdea                       // <1>
        await friend.tell(opinion, heldBy: self)  // <2> SUSPENSION POINT
        return opinion // 🤨 Could be .badIdea!   // <3>
    }

    func thinkOfBadIdea() async -> Decision {
        opinion = .badIdea                       // <4> Could interleave!
        await friend.tell(opinion, heldBy: self) // <5>
        return opinion                           // <6>
    }
}
```

**Timeline of Execution:**
1. Task A: `opinion = .goodIdea`
2. Task A: suspends at `await friend.tell(...)`
3. Task B: `opinion = .badIdea` (interleaved!)
4. Task B: suspends
5. Task A: resumes, returns `opinion` (now `.badIdea`!)

**Best Practice - Validate After await:**
```swift
func thinkOfGoodIdea() async -> Decision {
    opinion = .goodIdea
    let snapshot = opinion  // Capture before await
    await friend.tell(opinion, heldBy: self)

    // Validate: did state change?
    guard opinion == snapshot else {
        // Handle race condition
        return .conflict
    }
    return opinion
}
```

**Better Pattern - Encapsulate State:**
```swift
actor DecisionMaker {
    private var _opinion: Decision = .noIdea

    // Synchronous critical section - no interleaving
    private func updateOpinion(_ new: Decision) {
        _opinion = new
    }

    func thinkOfGoodIdea() async -> Decision {
        updateOpinion(.goodIdea)  // Atomic update
        await friend.tell(_opinion, heldBy: self)
        // State might have changed, but we've encapsulated the update
        return getCurrentOpinion()
    }

    private func getCurrentOpinion() -> Decision {
        _opinion  // Synchronous read
    }
}
```

### Rule 10: Actor Executors
**Swift Version:** 5.5+
**Source:** SE-0304:174-185, SE-0306:115

- Each actor has a **serial executor**
- Executors run tasks **one-at-a-time**
- Executors **SHOULD** (not "must") honor **priority** over submission order
- Different from `DispatchQueue` (which is strictly FIFO)
- Actors use **lightweight queue** optimized for async/await
- This is a **Quality of Implementation** detail, not a language guarantee

### Rule 11: Isolated Parameters
**Swift Version:** 5.7+
**Source:** SE-0313

**Synchronous access to actor state** via isolated parameters:

```swift
actor Island {
    var flock: [Chicken] = []
}

// Function takes isolated reference
func process(on island: isolated Island) {
    island.flock.append(Chicken())  // Synchronous access OK!
    // Compiler guarantees we're already on island's executor
}

let myIsland = Island()
// Caller must have access to the actor
await process(on: myIsland)  // Hops to island's executor
```

**Benefits:**
- No `await` needed inside `process()`
- Compiler enforces isolation at call site
- Clearer than passing actor and awaiting inside

### Rule 12: Non-Isolated Async Function Execution
**Swift Version:** 5.7+
**Source:** SE-0338

**Critical behavior change in Swift 5.7:**

`async` functions that are **not actor-isolated** run on a **generic executor**:

```swift
extension MyActor {
    func update() async {
        // Runs on MyActor's executor
        let update = await session.readConsistentUpdate()
        // Returns to MyActor's executor
        name = update.name
    }
}

extension MyNetworkSession {
    // NOT actor-isolated
    func readConsistentUpdate() async -> Update {
        // Switches OFF actor to generic executor when called
        let update = await readUpdateOnce()
        // Returns to generic executor (not actor)
        return update
    }
}
```

**Key Points:**
- Non-isolated async functions **switch executors on every entry**
- This includes calls, returns, and resumptions
- Different from actor-isolated functions which stay on actor's executor

---

## PART 3: MAINACTOR & GLOBAL ACTORS

### Rule 13: @MainActor Isolation
**Swift Version:** 5.5+
**Source:** SE-0316, SE-0306

- `@MainActor` marks code to run on main thread
- Entire **class** can be `@MainActor` (all members isolated)
- **Individual methods** can be `@MainActor`
- WKWebView and UI types are **@MainActor-isolated**

```swift
@MainActor
class DocumentationCrawler {
    private var webView: WKWebView!  // MainActor-isolated

    func loadPage() async throws -> String {
        // Runs on MainActor
        webView.load(...)
    }
}
```

### Rule 14: nonisolated for Background Work
**Swift Version:** 5.7+
**Source:** SE-0313

**Prevent blocking MainActor:**

```swift
@MainActor
class ViewModel {
    private var data: [Item] = []

    // BAD: Blocks MainActor during network call!
    func fetch() async {
        let items = await network.fetchItems()
        data = items
    }

    // GOOD: Runs on background executor
    nonisolated func fetch() async {
        let items = await network.fetchItems()
        await updateData(items)  // Hops to MainActor
    }

    private func updateData(_ items: [Item]) {
        data = items  // Runs on MainActor
    }
}
```

### Rule 15: Dynamic Isolation Checking
**Swift Version:** 6.0+
**Source:** Swift 6.0 Documentation

**Runtime isolation verification:**

```swift
@MainActor
func updateUI() {
    MainActor.assertIsolated()  // Crashes if not on MainActor
    label.text = "Updated"
}

// Unsafe: assume isolation without checking
func dangerousAccess() {
    MainActor.assumeIsolated {
        // Synchronously access MainActor state
        // ⚠️ Crashes if assumption is wrong!
        label.text = "Danger"
    }
}
```

---

## PART 4: SENDABLE & ISOLATION BOUNDARIES

### Rule 16: Sendable Protocol Fundamentals
**Swift Version:** 5.5+
**Source:** SE-0302

**Sendable** types can be safely passed across isolation boundaries:

- Value types (structs) are **implicitly Sendable** if all members are
- Classes must **explicitly conform** and be immutable or synchronized
- **Non-Sendable** values cannot cross isolation boundaries (strict mode)

### Rule 17: Implicit Sendable Conformances
**Swift Version:** 5.5+
**Source:** SE-0302

Automatic conformance rules vary by visibility:

```swift
// 1. Non-public types: Implicit conformance
struct MyPerson {  // Implicitly Sendable!
    var name: String, age: Int
}

// 2. Public non-frozen: Must be explicit
public struct PublicPerson {  // Does NOT implicitly conform
    var name: String, age: Int
}

// 3. Frozen public: Implicit conformance
@frozen public struct FrozenPublic {  // Implicitly Sendable!
    var name: String, age: Int
}
```

**Why?** API resilience - public types might add non-Sendable members later.

### Rule 18: Sendable Checking for Async Calls
**Swift Version:** 5.7+ (enforced in 6.0)
**Source:** SE-0338

Arguments and results of **ALL** `async` calls must be `Sendable` **unless**:
1. Caller and callee are both isolated to the **same actor**, OR
2. Caller and callee are both **non-isolated**

**Dangerous Example (Allowed in Swift 5, Error in Swift 6):**
```swift
class NonSendableValue {
    var count = 0
    func operate() { count += 1 }
}

actor MyActor {
    var isolated: NonSendableValue = NonSendableValue()

    func inside_one() async {
        await outside(argument: isolated) // ❌ ERROR in Swift 6!
    }
}

func outside(argument: NonSendableValue) async {
    await Task.sleep(nanoseconds: 1_000)
    argument.operate()  // ⚠️ RACE: Can happen concurrently with actor access!
}
```

**Fix:**
```swift
func inside_one() async {
    // Make a Sendable copy
    let count = isolated.count
    await outside(count: count)
}

func outside(count: Int) async {
    // Work with Sendable value
}
```

### Rule 19: Region-Based Isolation
**Swift Version:** 6.0+
**Source:** SE-0414:1-100

Can transfer non-Sendable values using **region analysis**:

```swift
class Client {
    var name: String
    var friend: Client?
    init(name: String) { self.name = name }
}

actor ClientStore {
    static let shared = ClientStore()
    private var clients: [Client] = []

    func addClient(_ client: Client) {
        clients.append(client)
    }
}

func openAccount(name: String) async {
    let john = Client(name: "John")
    let joanna = Client(name: "Joanna")
    // Regions: [(john), (joanna)] - Different isolation regions!

    await ClientStore.shared.addClient(john)
    // Regions: [{(john), ClientStore.shared}, (joanna)]
    // john has been transferred to ClientStore's region

    await ClientStore.shared.addClient(joanna) // ✓ OK! Different region
    // Regions: [{(john, joanna), ClientStore.shared}]
}
```

**Region Merging:**
```swift
let john = Client(name: "John")
let joanna = Client(name: "Joanna")

john.friend = joanna  // Regions MERGE!
// Regions: [(john, joanna)]

await ClientStore.shared.addClient(john)
// Regions: [{(john, joanna), ClientStore.shared}]

await ClientStore.shared.addClient(joanna)
// ❌ ERROR! joanna already transferred (same region as john)
```

### Rule 20: Transferring Parameters
**Swift Version:** 6.0+
**Source:** SE-0430

Explicit `transferring` keyword for non-Sendable transfers:

```swift
class NonSendable {
    var value: Int
}

func transfer(transferring value: NonSendable) async {
    // Compiler ensures 'value' is never used again in caller
    await someActor.store(value)
}

let myValue = NonSendable(value: 42)
await transfer(transferring: myValue)
// ❌ ERROR: Cannot use myValue after transfer
```

**Benefits:**
- Explicit transfer intent in API
- Compiler enforces single ownership
- Safe transfer of non-Sendable values

---

## PART 5: SWIFT 6 MIGRATION & TOOLING

### Rule 21: Strict Concurrency Checking Levels
**Swift Version:** 5.7+ (default in 6.0)
**Source:** SE-0337, Swift 6.0 Documentation

**Three levels of concurrency checking:**

```bash
# 1. Minimal (Swift 5 default) - Few warnings
-strict-concurrency=minimal

# 2. Targeted (warnings for concurrency-aware code only)
-strict-concurrency=targeted

# 3. Complete (Swift 6 default) - All violations are errors
-strict-concurrency=complete
```

**In SwiftPM:**
```swift
// Package.swift
.target(
    name: "MyTarget",
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .enableExperimentalFeature("StrictConcurrency")
    ]
)
```

### Rule 22: @preconcurrency for Gradual Migration
**Swift Version:** 5.7+
**Source:** SE-0337

Suppress warnings during migration:

```swift
// Suppress Sendable warnings for legacy module
@preconcurrency import LegacyModule

// Gradually adopt concurrency features
@preconcurrency protocol OldProtocol {
    func legacyMethod() -> NonSendableType
}
```

**Use Cases:**
- Third-party dependencies not yet updated
- Large codebases migrating incrementally
- Objective-C interop

### Rule 23: Compiler Flags for Migration
**Swift Version:** 5.7+ (flags), 6.0+ (language mode)
**Source:** Swift 6.0 Documentation

```bash
# Enable Swift 6 language mode
swift build -swift-version 6

# Check for concurrency warnings without erroring
swift build -Xswiftc -warn-concurrency

# Enable specific upcoming features
swift build -Xswiftc -enable-upcoming-feature -Xswiftc StrictConcurrency

# Test with complete checking
swift test -Xswiftc -strict-concurrency=complete
```

---

## PART 6: FORBIDDEN PATTERNS (OLD CONCURRENCY)

### Rule 24: NO DispatchQueue in Structured Concurrency
**Swift Version:** 5.5+ (recommendation)
**Source:** SE-0304, SE-0306:115

**FORBIDDEN:**
```swift
DispatchQueue.main.async { }
DispatchQueue.global().async { }
DispatchQueue.main.asyncAfter(deadline: .now() + 5) { }
```

**USE INSTEAD:**
```swift
Task { @MainActor in }              // Main thread work
Task.detached { }                   // Background work
try await Task.sleep(for: .seconds(5))  // Delays
```

**EXCEPTION: Legacy Interop Only**
```swift
// Rare case: Objective-C API requires DispatchQueue
someObjCAPI.setCompletionQueue(DispatchQueue.main)
```

### Rule 25: NO Manual Continuations for Built-in APIs
**Swift Version:** 5.5+ (async APIs available)
**Source:** SE-0300

**FORBIDDEN (when async API exists):**
```swift
withCheckedThrowingContinuation { continuation in
    webView.evaluateJavaScript(...) { result, error in
        continuation.resume(...)
    }
}
```

**USE INSTEAD:**
```swift
try await webView.evaluateJavaScript(..., in: nil, contentWorld: .page)
```

### Rule 26: NO NSOperationQueue, pthread, Thread
**Swift Version:** 5.5+ (recommendation)
**Source:** Swift Concurrency Design

**FORBIDDEN:**
```swift
Thread.detachNewThread { }
NSOperationQueue.main.addOperation { }
pthread_create(...)
```

**USE INSTEAD:**
- Task-based concurrency
- Actors for synchronization
- Structured concurrency primitives

---

## PART 7: MODERN ASYNC APIS

### Rule 27: Task.sleep API
**Swift Version:** 5.5+ (nanoseconds), 5.7+ (Duration-based)
**Source:** SE-0374: Clock, Instant, Duration

```swift
// Modern API (preferred)
try await Task.sleep(for: .seconds(5))
try await Task.sleep(until: .now + .seconds(5))

// Old API (still works, but avoid)
try await Task.sleep(nanoseconds: 5_000_000_000)
```

### Rule 28: Task Executor Preference
**Swift Version:** 6.0+
**Source:** Apple Swift Concurrency Documentation

Fine-grained control over child task execution:

```swift
await withTaskExecutorPreference(myCustomExecutor) {
    async let x = work1()
    async let y = work2()
    // Both x and y will prefer to run on myCustomExecutor
    let results = await (x, y)
}
```

---

## COMPLIANCE CHECKLIST

### ✅ REQUIRED for Swift 6 Language Mode:

1. [ ] No `DispatchQueue` usage (except legacy interop)
2. [ ] No `NSOperationQueue` usage
3. [ ] No manual `Thread` creation
4. [ ] No `withCheckedContinuation` for APIs with async versions
5. [ ] Use `withThrowingTaskGroup` for task racing
6. [ ] All child tasks explicitly or implicitly awaited
7. [ ] Proper `@MainActor` annotations for UI code
8. [ ] Use `nonisolated` for background work in MainActor types
9. [ ] All cross-isolation values are `Sendable`
10. [ ] Validate actor state after `await` in reentrant methods
11. [ ] Enable `-strict-concurrency=complete`
12. [ ] No blocking operations in async contexts

### ⚠️ COMMON MISTAKES:

1. **Using `async let` for racing** - It doesn't work! (implicit await)
2. **Forgetting implicit await** - `async let` blocks on scope exit
3. **Using old callback APIs** - Check for async versions first
4. **Mixing DispatchQueue with Tasks** - Pick one paradigm
5. **Assuming FIFO order** - Actors honor priority, not order
6. **Not validating after await** - Actor state may have changed
7. **Over-isolating to MainActor** - Use `nonisolated` for background work
8. **Assuming synchronous actor access** - Need `await` for methods
9. **Passing non-Sendable across isolation** - Use `transferring` or make Sendable
10. **Not using region-based isolation** - Can transfer non-Sendable safely

### 📚 MIGRATION BEST PRACTICES:

1. **Enable warnings gradually:**
   ```bash
   # Start with targeted
   -strict-concurrency=targeted
   # Move to complete when ready
   -strict-concurrency=complete
   ```

2. **Use @preconcurrency for dependencies:**
   ```swift
   @preconcurrency import ThirdPartySDK
   ```

3. **Test each module incrementally:**
   ```swift
   .target(
       name: "Module1",
       swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
   )
   ```

4. **Use MainActor.assertIsolated() in tests:**
   ```swift
   func testMainActorIsolation() {
       MainActor.assertIsolated()
       // Test UI code
   }
   ```

5. **Audit for data races:**
   ```bash
   swift build -Xswiftc -warn-concurrency 2>&1 | grep -i "race\|sendable\|isolation"
   ```

---

## VERIFICATION COMMANDS

```bash
# Check for forbidden patterns
grep -r "DispatchQueue" Sources/ --exclude-dir=.build
grep -r "NSOperationQueue" Sources/ --exclude-dir=.build
grep -r "Thread.detach" Sources/ --exclude-dir=.build
grep -r "withCheckedContinuation" Sources/ --exclude-dir=.build

# Build with strict concurrency checking
swift build -Xswiftc -strict-concurrency=complete

# Enable Swift 6 language mode
swift build -swift-version 6

# Check for concurrency warnings
swift build -Xswiftc -warn-concurrency

# Run tests with complete checking
swift test -Xswiftc -strict-concurrency=complete

# Verify swift-parsing compatibility
swift package resolve
swift build --target TemplateParser
```

---

## ADDITIONAL RESOURCES

### Swift Evolution Proposals (Priority Order):

1. **SE-0304** - Structured Concurrency (MUST READ)
2. **SE-0306** - Actors (MUST READ)
3. **SE-0302** - Sendable and @Sendable closures
4. **SE-0317** - async let bindings
5. **SE-0338** - Non-actor-isolated async execution (IMPORTANT)
6. **SE-0414** - Region-based Isolation (Swift 6)
7. **SE-0381** - DiscardingTaskGroup
8. **SE-0430** - transferring parameters
9. **SE-0337** - Incremental migration
10. **SE-0313** - Improved actor isolation control

### Key Concepts to Master:

- Task trees and structured concurrency
- Actor reentrancy and state validation
- Sendable protocol and implicit conformance
- Region-based isolation mechanics
- Executor switching behavior
- Priority inheritance and escalation

---

**Document Version:** 2.0
**Last Updated:** November 16, 2025
**Swift Version Compatibility:** Swift 5.5+ (language features), Swift 6.0 (language mode)
**Target:** Swift 6 Language Mode Migration
**Compliance Goal:** 100% Structured Concurrency with Region-Based Isolation

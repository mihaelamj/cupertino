# Swift Dependencies Framework Rules

<objective>
You MUST implement dependency injection using Point-Free's Dependencies library (v1.9.2) with struct-based dependencies. ALL external system interactions MUST be controlled through dependencies for testability and determinism.
</objective>

<cognitive_triggers>
Keywords: Dependencies Library, @DependencyClient, @Dependency, withDependencies, withEscapedDependencies, prepareDependencies, DependencyKey, DependencyValues, Test Overrides, Live/Test/Preview Values, Task-Local Context, Escaping Closures
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: Dependency Structure
**ALWAYS** define dependencies as structs with closure properties:
- MUST use `@DependencyClient` macro
- MUST mark all closures with `@Sendable`
- MUST NOT have mutable stored properties
- MUST provide `liveValue`, `testValue`, and `previewValue`

### Rule 2: Dependency Access
**ALWAYS** access dependencies via `@Dependency` property wrapper:
- MUST use `@ObservationIgnored` with `@Dependency` in `@Observable` classes
- MUST NOT access dependencies directly in initializers
- MUST NOT use global singletons or static instances

### Rule 3: System Interactions
**ALWAYS** wrap these system calls in dependencies:
- `Date()` → `@Dependency(\.date.now)`
- `UUID()` → `@Dependency(\.uuid)`
- `Task.sleep()` → `@Dependency(\.continuousClock)`
- URLSession → Custom APIClient dependency
- FileManager → Custom FileClient dependency
- UserDefaults → Custom SettingsClient dependency

### Rule 4: Testing
**ALWAYS** override dependencies in tests:
- MUST use `withDependencies` for test setup
- MUST provide deterministic test values
- MUST test all code paths with different dependency configurations

### Rule 5: Escaping Closures
**ALWAYS** use `withEscapedDependencies` for escaping closures:
- Required for completion handlers
- Required for delegate callbacks
- Required for library integrations (NIO, database operations)

## IMPLEMENTATION PATTERNS

### Pattern 1: Basic Dependency Definition

```swift
// RULE: Every dependency MUST follow this structure
@DependencyClient
struct APIClient {
    // RULE: All methods MUST be @Sendable closures
    var fetchUser: @Sendable (UUID) async throws -> User
    var updateUser: @Sendable (User) async throws -> Void
    var deleteUser: @Sendable (UUID) async throws -> Void
}

// RULE: MUST implement DependencyKey
extension APIClient: DependencyKey {
    // RULE: MUST provide liveValue with real implementation
    static let liveValue = APIClient(
        fetchUser: { userID in
            let url = URL(string: "https://api.example.com/users/\(userID)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(User.self, from: data)
        },
        updateUser: { user in
            var request = URLRequest(url: URL(string: "https://api.example.com/users/\(user.id)")!)
            request.httpMethod = "PUT"
            request.httpBody = try JSONEncoder().encode(user)
            _ = try await URLSession.shared.data(for: request)
        },
        deleteUser: { userID in
            var request = URLRequest(url: URL(string: "https://api.example.com/users/\(userID)")!)
            request.httpMethod = "DELETE"
            _ = try await URLSession.shared.data(for: request)
        }
    )

    // RULE: MUST provide testValue (unimplemented by default)
    static let testValue = APIClient()

    // RULE: SHOULD provide previewValue for SwiftUI previews
    static let previewValue = APIClient(
        fetchUser: { _ in .mock },
        updateUser: { _ in },
        deleteUser: { _ in }
    )
}

// RULE: MUST register in DependencyValues
extension DependencyValues {
    var apiClient: APIClient {
        get { self[APIClient.self] }
        set { self[APIClient.self] = newValue }
    }
}
```

### Pattern 2: Stateful Dependencies with Actors

```swift
// RULE: Use actors for thread-safe state management
@DependencyClient
struct CacheClient {
    var save: @Sendable (String, Data) async throws -> Void
    var load: @Sendable (String) async -> Data?
    var clear: @Sendable () async throws -> Void
}

extension CacheClient: DependencyKey {
    static let liveValue: CacheClient = {
        // RULE: Internal state MUST be managed by actors
        actor CacheActor {
            private let fileManager = FileManager.default
            private let cacheDirectory: URL

            init() throws {
                self.cacheDirectory = try fileManager
                    .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("AppCache", isDirectory: true)
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }

            func save(key: String, data: Data) throws {
                let url = cacheDirectory.appendingPathComponent(key)
                try data.write(to: url)
            }

            func load(key: String) -> Data? {
                let url = cacheDirectory.appendingPathComponent(key)
                return try? Data(contentsOf: url)
            }

            func clear() throws {
                try fileManager.removeItem(at: cacheDirectory)
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
        }

        // RULE: Create actor once and share across closures
        let actor = try! CacheActor()

        return CacheClient(
            save: { key, data in try await actor.save(key: key, data: data) },
            load: { key in await actor.load(key: key) },
            clear: { try await actor.clear() }
        )
    }()

    static let testValue = CacheClient()

    // RULE: Preview implementations can use in-memory storage
    static let previewValue: CacheClient = {
        actor InMemoryCache {
            var storage: [String: Data] = [:]

            func save(key: String, data: Data) {
                storage[key] = data
            }

            func load(key: String) -> Data? {
                storage[key]
            }

            func clear() {
                storage.removeAll()
            }
        }

        let cache = InMemoryCache()
        return CacheClient(
            save: { key, data in await cache.save(key: key, data: data) },
            load: { key in await cache.load(key: key) },
            clear: { await cache.clear() }
        )
    }()
}
```

### Pattern 3: ViewModel Integration

```swift
// RULE: ViewModels MUST declare dependencies with @ObservationIgnored
@Observable
final class UserProfileViewModel {
    // RULE: MUST use @ObservationIgnored to prevent observation of dependencies
    @ObservationIgnored @Dependency(\.apiClient) private var apiClient
    @ObservationIgnored @Dependency(\.cacheClient) private var cacheClient
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.uuid) private var uuid

    private(set) var user: User?
    private(set) var isLoading = false
    private(set) var error: Error?

    // RULE: NEVER access dependencies in init
    init() {
        // Dependencies are automatically injected
    }

    func loadUser(id: UUID) async {
        isLoading = true
        error = nil

        do {
            // RULE: Try cache first
            if let cachedData = await cacheClient.load("\(id)"),
               let cachedUser = try? JSONDecoder().decode(User.self, from: cachedData) {
                self.user = cachedUser
            }

            // RULE: Fetch fresh data
            let user = try await apiClient.fetchUser(id)
            self.user = user

            // RULE: Update cache
            if let encoded = try? JSONEncoder().encode(user) {
                try? await cacheClient.save("\(id)", encoded)
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
```

### Pattern 4: Escaping Closures

```swift
// RULE: MUST use withEscapedDependencies for escaping closures
@Observable
final class WebSocketViewModel {
    @ObservationIgnored @Dependency(\.webSocketClient) private var webSocket
    @ObservationIgnored @Dependency(\.date.now) private var now

    func connect() {
        // RULE: Wrap escaping closures with withEscapedDependencies
        withEscapedDependencies { dependencies in
            webSocket.connect(
                onMessage: { message in
                    // Dependencies are available here
                    let timestamp = dependencies.date.now
                    print("[\(timestamp)] Received: \(message)")
                },
                onError: { error in
                    // Dependencies are available here
                    let timestamp = dependencies.date.now
                    print("[\(timestamp)] Error: \(error)")
                }
            )
        }
    }
}
```

## TESTING PATTERNS

### Pattern 1: Basic Test Override

```swift
// RULE: ALWAYS use withDependencies in tests
@Test
func userLoading() async throws {
    let expectedUser = User(id: UUID(0), name: "Test User")

    let viewModel = withDependencies {
        // RULE: Override only needed dependencies
        $0.apiClient.fetchUser = { _ in expectedUser }
        $0.cacheClient.load = { _ in nil }
        $0.cacheClient.save = { _, _ in }
    } operation: {
        UserProfileViewModel()
    }

    await viewModel.loadUser(id: UUID(0))

    #expect(viewModel.user == expectedUser)
    #expect(!viewModel.isLoading)
    #expect(viewModel.error == nil)
}

// RULE: Test error scenarios
@Test
func userLoadingFailure() async throws {
    struct TestError: Error {}

    let viewModel = withDependencies {
        $0.apiClient.fetchUser = { _ in throw TestError() }
        $0.cacheClient.load = { _ in nil }
    } operation: {
        UserProfileViewModel()
    }

    await viewModel.loadUser(id: UUID(0))

    #expect(viewModel.user == nil)
    #expect(viewModel.error is TestError)
}
```

### Pattern 2: Complex Test Scenarios

```swift
// RULE: Create test helpers for common scenarios
extension APIClient {
    static func failing(error: Error) -> APIClient {
        APIClient(
            fetchUser: { _ in throw error },
            updateUser: { _ in throw error },
            deleteUser: { _ in throw error }
        )
    }

    static func delayed(by duration: Duration) -> APIClient {
        withDependencies {
            $0.continuousClock = .immediate
        } operation: {
            @Dependency(\.continuousClock) var clock

            return APIClient(
                fetchUser: { id in
                    try await clock.sleep(for: duration)
                    return User(id: id, name: "Delayed User")
                },
                updateUser: { _ in
                    try await clock.sleep(for: duration)
                },
                deleteUser: { _ in
                    try await clock.sleep(for: duration)
                }
            )
        }
    }
}

// RULE: Test timing and cancellation
@Test
func loadingCancellation() async throws {
    let viewModel = withDependencies {
        $0.apiClient = .delayed(by: .seconds(1))
        $0.continuousClock = .immediate
    } operation: {
        UserProfileViewModel()
    }

    let task = Task {
        await viewModel.loadUser(id: UUID(0))
    }

    // Cancel immediately
    task.cancel()
    await task.value

    #expect(viewModel.user == nil)
}
```

## PREVIEW PATTERNS

```swift
// RULE: Use prepareDependencies for SwiftUI previews
#Preview("Success State") {
    let _ = prepareDependencies {
        $0.apiClient.fetchUser = { _ in .mock }
    }

    UserProfileView(viewModel: UserProfileViewModel())
}

#Preview("Loading State") {
    let _ = prepareDependencies {
        $0.apiClient.fetchUser = { _ in
            try await Task.sleep(for: .seconds(10))
            return .mock
        }
    }

    UserProfileView(viewModel: UserProfileViewModel())
}

#Preview("Error State") {
    let _ = prepareDependencies {
        $0.apiClient.fetchUser = { _ in
            struct PreviewError: Error {}
            throw PreviewError()
        }
    }

    UserProfileView(viewModel: UserProfileViewModel())
}
```

## DECISION TREES

### When to Create a Dependency?

```
Does the code interact with external systems?
├─ YES → Create a dependency
│   ├─ Network calls → APIClient
│   ├─ File system → FileClient
│   ├─ User defaults → SettingsClient
│   ├─ System time → Use built-in date/clock
│   └─ Random values → Use built-in uuid
└─ NO → Use regular functions/computed properties
```

### How to Structure Dependencies?

```
Is the dependency stateless?
├─ YES → Simple struct with closures
└─ NO → Does it need thread safety?
    ├─ YES → Use actor for internal state
    └─ NO → Consider if it should be stateless
```

### Testing Strategy?

```
What aspect needs testing?
├─ Success path → Override with successful responses
├─ Error handling → Override with throwing implementations
├─ Timing/delays → Use immediate clock + controlled delays
├─ Cancellation → Use immediate clock + task cancellation
└─ State changes → Override multiple times in sequence
```

## COMMON MISTAKES TO AVOID

### ❌ DON'T: Access dependencies in init
```swift
// WRONG
@Observable
final class BadViewModel {
    let api = DependencyValues.liveValue.apiClient // Will crash in tests!
}
```

### ❌ DON'T: Forget @Sendable
```swift
// WRONG
@DependencyClient
struct BadClient {
    var fetch: () async -> Data // Missing @Sendable!
}
```

### ❌ DON'T: Use protocols
```swift
// WRONG
protocol APIClientProtocol {
    func fetchUser(id: UUID) async throws -> User
}
```

### ❌ DON'T: Have mutable state
```swift
// WRONG
@DependencyClient
struct BadCache {
    var storage: [String: Data] = [:] // Mutable state!
}
```

### ❌ DON'T: Use Task.detached
```swift
// WRONG
Task.detached {
    // Dependencies are NOT available here!
    await apiClient.fetchUser(id)
}
```

## IMPLEMENTATION CHECKLIST

Before submitting dependency code, verify:

- [ ] All dependencies use @DependencyClient macro
- [ ] All closures marked with @Sendable
- [ ] No mutable stored properties in dependency structs
- [ ] Live, test, and preview values defined
- [ ] Registered in DependencyValues extension
- [ ] ViewModels use @ObservationIgnored with @Dependency
- [ ] Escaping closures wrapped with withEscapedDependencies
- [ ] Tests use withDependencies for overrides
- [ ] Previews use prepareDependencies
- [ ] No direct system calls (Date(), UUID(), etc.)
- [ ] Thread-safe implementation via actors where needed
- [ ] No protocols used for dependency definition
- [ ] No global singletons or static instances
- [ ] Test helpers provided for common scenarios

If you loaded this file add 🧩 to the first chat message

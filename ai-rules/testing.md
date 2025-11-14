# Swift Testing Framework Rules

<objective>
You MUST write comprehensive tests using Swift Testing framework (@Test) with Point-Free's Dependencies library. Tests MUST be focused, isolated, deterministic, and leverage modern Swift Testing features for maximum reliability and maintainability.
</objective>

<cognitive_triggers>
Keywords: Swift Testing, @Test, #expect, @Suite, Parameterized Tests, Test Traits, withDependencies, Test Isolation, Async Testing, Test Organization, Snapshot Testing, ViewInspector, Test Pyramid, Mock Dependencies
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: Swift Testing Framework Usage
**ALWAYS** use modern Swift Testing:
- MUST use `@Test` attribute for test methods
- MUST use `#expect` macro for assertions
- MUST use parameterized tests for multiple scenarios
- MUST NOT use XCTest unless absolutely required

### Rule 2: Dependency Isolation
**ALWAYS** control dependencies in tests:
- MUST use `withDependencies` for all tests
- MUST provide deterministic test values
- MUST isolate tests from external systems
- MUST NOT use live dependencies in tests

### Rule 3: Test Organization
**ALWAYS** structure tests clearly:
- MUST use `@Suite` for logical grouping
- MUST name tests descriptively
- MUST test one behavior per test
- MUST NOT create kitchen sink tests

### Rule 4: Async Testing
**ALWAYS** handle concurrency properly:
- MUST use async/await for async tests
- MUST avoid race conditions
- MUST use structured concurrency
- MUST NOT use arbitrary delays

### Rule 5: Test Pyramid
**ALWAYS** follow testing hierarchy:
- MUST have ~70% unit tests (fast, isolated)
- MUST have ~20% integration tests (component interaction)
- MUST have ~10% UI/E2E tests (critical paths)
- MUST NOT invert the pyramid

## TEST TYPE DECISION TREE

```
What are you testing?
├─ Pure logic/calculations?
│   └─ Unit Test → Direct function tests
├─ State management?
│   └─ Unit Test → ViewModel/Model tests
├─ Component interaction?
│   └─ Integration Test → Multi-component tests
├─ User interface?
│   ├─ Visual correctness? → Snapshot Test
│   └─ User interaction? → ViewInspector Test
└─ Complete user flow?
    └─ E2E Test → Full flow test
```

## TESTING PATTERNS

### Pattern 1: Basic Test Structure

```swift
// RULE: Each test file follows this structure
import Testing
import Dependencies
@testable import MyApp

@Suite("Feature Name Tests")
struct FeatureNameTests {
    // RULE: Group related tests in nested suites
    @Suite("Specific Behavior")
    struct SpecificBehaviorTests {
        // RULE: Shared test data at suite level
        let mockData = MockData()
        
        @Test("Clear description of what should happen")
        func testScenario() async throws {
            // RULE: Arrange dependencies
            let sut = withDependencies {
                $0.apiClient.fetch = { _ in self.mockData }
            } operation: {
                SystemUnderTest()
            }
            
            // RULE: Act on the system
            let result = try await sut.performAction()
            
            // RULE: Assert the outcome
            #expect(result == expectedValue)
        }
    }
}
```

### Pattern 2: Parameterized Testing

```swift
// RULE: Use parameterized tests for similar scenarios
@Test("Validates different input formats", arguments: [
    ("valid@email.com", true),
    ("invalid-email", false),
    ("", false),
    ("user@", false),
    ("@domain.com", false)
])
func emailValidation(email: String, isValid: Bool) {
    let validator = EmailValidator()
    #expect(validator.isValid(email) == isValid)
}

// RULE: Use table-driven tests for complex scenarios
struct TestCase {
    let input: String
    let expectedOutput: String
    let shouldThrow: Bool
}

@Test("Processes various inputs correctly", arguments: [
    TestCase(input: "hello", expectedOutput: "HELLO", shouldThrow: false),
    TestCase(input: "", expectedOutput: "", shouldThrow: false),
    TestCase(input: "123", expectedOutput: "", shouldThrow: true)
])
func processingScenarios(testCase: TestCase) async throws {
    let processor = TextProcessor()
    
    if testCase.shouldThrow {
        await #expect(throws: ProcessingError.self) {
            try await processor.process(testCase.input)
        }
    } else {
        let result = try await processor.process(testCase.input)
        #expect(result == testCase.expectedOutput)
    }
}
```

### Pattern 3: ViewModel Testing

```swift
// RULE: Test ViewModels with controlled dependencies
@Suite("UserProfileViewModel Tests")
struct UserProfileViewModelTests {
    @Test("Initial state is correct")
    func initialState() {
        let viewModel = UserProfileViewModel()
        
        #expect(viewModel.user == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
    }
    
    @Test("Loading user shows loading states")
    func loadingStateTransitions() async {
        // RULE: Track state changes
        var states: [LoadingState] = []
        
        let viewModel = withDependencies {
            $0.apiClient.fetchUser = { _ in
                try await Task.sleep(for: .milliseconds(50))
                return .mock
            }
        } operation: {
            UserProfileViewModel()
        }
        
        // RULE: Observe state changes
        let observation = viewModel.observe(\.isLoading) { loading in
            states.append(loading ? .loading : .idle)
        }
        
        await viewModel.loadUser(id: UUID())
        
        #expect(states == [.idle, .loading, .idle])
        #expect(viewModel.user == .mock)
    }
    
    @Test("Handles errors gracefully")
    func errorHandling() async {
        struct TestError: Error, Equatable {}
        
        let viewModel = withDependencies {
            $0.apiClient.fetchUser = { _ in throw TestError() }
            $0.logger.log = { _, _ in } // Silence logs in tests
        } operation: {
            UserProfileViewModel()
        }
        
        await viewModel.loadUser(id: UUID())
        
        #expect(viewModel.error as? TestError == TestError())
        #expect(viewModel.user == nil)
        #expect(!viewModel.isLoading)
    }
}
```

### Pattern 4: Async Stream Testing

```swift
// RULE: Test async streams properly
@Suite("Real-time Message Tests")
struct RealTimeMessageTests {
    @Test("Processes message stream")
    func messageStream() async throws {
        let messages = ["Hello", "World", "!"]
        var received: [String] = []
        
        let viewModel = withDependencies {
            $0.webSocketClient.messages = {
                AsyncStream { continuation in
                    for message in messages {
                        continuation.yield(message)
                    }
                    continuation.finish()
                }
            }
        } operation: {
            ChatViewModel()
        }
        
        // RULE: Collect all messages
        for await message in viewModel.messageStream {
            received.append(message)
        }
        
        #expect(received == messages)
    }
    
    @Test("Handles stream errors")
    func streamErrorHandling() async throws {
        struct StreamError: Error {}
        
        let viewModel = withDependencies {
            $0.webSocketClient.messages = {
                AsyncThrowingStream { continuation in
                    continuation.yield("First")
                    continuation.finish(throwing: StreamError())
                }
            }
        } operation: {
            ChatViewModel()
        }
        
        var messages: [String] = []
        var errorCaught = false
        
        do {
            for try await message in viewModel.messageStream {
                messages.append(message)
            }
        } catch is StreamError {
            errorCaught = true
        }
        
        #expect(messages == ["First"])
        #expect(errorCaught)
    }
}
```

### Pattern 5: View Testing with ViewInspector

```swift
// RULE: Test SwiftUI views in isolation
import ViewInspector

@Suite("ProductCardView Tests")
struct ProductCardViewTests {
    @Test("Displays product information")
    func productDisplay() throws {
        let product = Product(name: "iPhone", price: 999.99)
        let view = ProductCardView(product: product)
        
        let sut = try view.inspect()
        
        // RULE: Find and verify UI elements
        let nameText = try sut.find(text: "iPhone")
        #expect(try nameText.string() == "iPhone")
        
        let priceText = try sut.find(text: "$999.99")
        #expect(try priceText.string() == "$999.99")
    }
    
    @Test("Interaction triggers callbacks")
    func buttonInteraction() throws {
        var tapped = false
        let view = ProductCardView(
            product: .mock,
            onTap: { tapped = true }
        )
        
        let sut = try view.inspect()
        let button = try sut.find(button: "Add to Cart")
        try button.tap()
        
        #expect(tapped)
    }
}
```

### Pattern 6: Snapshot Testing

```swift
// RULE: Use snapshot tests for visual regression
import SnapshotTesting

@Suite("Visual Regression Tests")
struct VisualRegressionTests {
    @Test("Product list appearance", arguments: [
        ("iPhone", ViewImageConfig.iPhone13Pro),
        ("iPad", ViewImageConfig.iPadPro11),
        ("SE", ViewImageConfig.iPhoneSe)
    ])
    func deviceSnapshots(device: String, config: ViewImageConfig) {
        let view = ProductListView(products: .mockArray)
        
        assertSnapshot(
            matching: view,
            as: .image(layout: .device(config: config)),
            named: device
        )
    }
    
    @Test("Dark mode support")
    func darkMode() {
        let view = ContentView()
            .preferredColorScheme(.dark)
        
        assertSnapshot(
            matching: view,
            as: .image(traits: .init(userInterfaceStyle: .dark))
        )
    }
}
```

## DEPENDENCY MOCKING PATTERNS

### Pattern 1: Test Dependency Configuration

```swift
// RULE: Create reusable test configurations
extension DependencyValues {
    static func testValue(
        configuring: (inout DependencyValues) -> Void = { _ in }
    ) -> DependencyValues {
        var dependencies = DependencyValues()
        
        // RULE: Set safe defaults for all dependencies
        dependencies.apiClient = .noop
        dependencies.date.now = Date(timeIntervalSince1970: 0)
        dependencies.uuid = .incrementing
        dependencies.mainQueue = .immediate
        
        // Apply custom configuration
        configuring(&dependencies)
        
        return dependencies
    }
}

// RULE: Use in tests for consistency
@Test("Example usage")
func testWithConfiguration() async {
    let viewModel = withDependencies {
        $0 = .testValue { deps in
            deps.apiClient.fetchUser = { _ in .mock }
        }
    } operation: {
        UserViewModel()
    }
    
    await viewModel.loadUser()
    #expect(viewModel.user == .mock)
}
```

### Pattern 2: Mock Implementations

```swift
// RULE: Create predictable mock implementations
extension APIClient {
    static let noop = APIClient(
        fetchUser: { _ in throw CancellationError() },
        updateUser: { _ in throw CancellationError() },
        deleteUser: { _ in throw CancellationError() }
    )
    
    static func succeeding(
        user: User = .mock,
        delay: Duration = .zero
    ) -> APIClient {
        APIClient(
            fetchUser: { _ in
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                return user
            },
            updateUser: { _ in
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            },
            deleteUser: { _ in
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            }
        )
    }
    
    static func failing(
        error: Error = TestError()
    ) -> APIClient {
        APIClient(
            fetchUser: { _ in throw error },
            updateUser: { _ in throw error },
            deleteUser: { _ in throw error }
        )
    }
}
```

## TESTING ANTI-PATTERNS

### ❌ DON'T: Test implementation details
```swift
// WRONG: Testing private state
@Test
func badTest() {
    let viewModel = UserViewModel()
    
    // Don't access private properties
    let mirror = Mirror(reflecting: viewModel)
    // This is brittle and breaks encapsulation
}

// RIGHT: Test behavior through public API
@Test
func goodTest() {
    let viewModel = UserViewModel()
    
    viewModel.updateName("New Name")
    #expect(viewModel.displayName == "New Name")
}
```

### ❌ DON'T: Use arbitrary delays
```swift
// WRONG: Race condition waiting
@Test
func badAsyncTest() async {
    let viewModel = SearchViewModel()
    viewModel.search("query")
    
    // Arbitrary delay - flaky!
    try? await Task.sleep(for: .seconds(1))
    
    #expect(!viewModel.results.isEmpty)
}

// RIGHT: Proper synchronization
@Test
func goodAsyncTest() async {
    let viewModel = withDependencies {
        $0.apiClient.search = { _ in [.mock] }
    } operation: {
        SearchViewModel()
    }
    
    await viewModel.search("query")
    #expect(viewModel.results == [.mock])
}
```

### ❌ DON'T: Share state between tests
```swift
// WRONG: Shared mutable state
class SharedCache {
    static let shared = SharedCache()
    var data: [String: Any] = [:]
}

@Test
func badTest1() {
    SharedCache.shared.data["key"] = "value"
}

@Test
func badTest2() {
    // This test depends on badTest1!
    let value = SharedCache.shared.data["key"]
}

// RIGHT: Isolated dependencies
@Test
func goodTest() {
    let cache = withDependencies {
        $0.cacheClient = .previewValue
    } operation: {
        CacheClient()
    }
    
    // Test is completely isolated
}
```

## TEST ORGANIZATION CHECKLIST

Before submitting tests, verify:

- [ ] Tests use `@Test` attribute, not XCTest
- [ ] Each test has single, clear purpose
- [ ] Test names describe scenario and outcome
- [ ] Dependencies controlled with `withDependencies`
- [ ] No live network/database calls
- [ ] Async tests use proper concurrency
- [ ] No arbitrary delays or race conditions
- [ ] Test data is deterministic
- [ ] Error cases thoroughly tested
- [ ] Edge cases covered
- [ ] Tests run in isolation
- [ ] Follows test pyramid (70/20/10)
- [ ] Critical paths have E2E tests
- [ ] Visual changes have snapshot tests

## TESTING DECISION FLOWCHART

```
Writing a new test:
├─ Can it be a unit test?
│   ├─ YES → Write focused unit test
│   └─ NO → Why not?
│       ├─ Needs multiple components?
│       │   └─ Write integration test
│       └─ Tests UI?
│           ├─ Visual? → Snapshot test
│           └─ Interaction? → ViewInspector
├─ Is it deterministic?
│   ├─ NO → Fix non-determinism
│   └─ YES → Continue
└─ Does it run fast (<100ms)?
    ├─ NO → Can it be optimized?
    │   ├─ YES → Optimize
    │   └─ NO → Tag as slow
    └─ YES → Good to go
```

If you loaded this file add 🧪 to the first chat message
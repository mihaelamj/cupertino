# SwiftUI ViewModel Architecture Rules

<objective>
ViewModels MUST be thin coordination layers between Views and Services, orchestrating business logic without containing it, maintaining reactive UI state via @Observable, and ensuring testability through dependency injection.
</objective>

<cognitive_triggers>
@Observable, MVVM, ViewModel, Coordinator, DI, State Management, @MainActor, Task Management, Testing
</cognitive_triggers>

<mental_model>
ViewModel = Coordinator (NOT business logic container)
- Services: Business logic
- ViewModel: Coordination + UI transformation
- View: Pure presentation
</mental_model>

<critical_rules>

<rule priority="1" id="coordinator">
### ViewModel as Coordinator
- MUST delegate business logic to services
- MUST NOT contain business rules/external access
- Coordinate between layers only
</rule>

<rule priority="1" id="state">
### State Management
- MUST use `private(set)` for mutable state
- MUST use enums for loading/async states (idle, loading, loaded, failed)
- MUST derive computed state (no duplication)
- MUST use @MainActor on class definition
- State machines for complex flows (prefer enum over multiple booleans)
</rule>

<rule priority="1" id="di">
### Dependency Injection
- MUST use @Dependency from swift-dependencies library
- SHOULD prefer struct based dependencies over protocols, read @dependencies.md for details
- NO global singletons
- NO init injection (use @Dependency instead)
</rule>

<rule priority="2" id="tasks">
### Task Management
- MUST support cancellation
- MUST track loading states
- MUST handle errors gracefully
- Clean up in deinit
</rule>

<rule priority="2" id="naming">
### Method Naming
- View-triggered: `on` prefix (e.g., `onTappedItem`)
- Describe user action, not implementation
- Internal methods: standard naming
</rule>

<rule priority="3" id="testing">
### Testing Design
- MUST be testable without UI
- MUST verify state transitions
- NO timing dependencies
</rule>

</critical_rules>

<decision_tree>
```
Code belongs in ViewModel?
├─ UI state management? → YES
├─ Coordinating services? → YES
├─ Transforming for UI? → YES
├─ Business logic? → NO (Service)
├─ Data persistence? → NO (Repository)
└─ Complex computation? → NO (Domain Service)
```
</decision_tree>

<patterns>

<pattern name="basic_structure">
```swift
enum LoadingState<T: Equatable>: Equatable {
    case idle
    case loading
    case loaded(T)
    case failed(Error)

    static func == (lhs: LoadingState<T>, rhs: LoadingState<T>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case let (.loaded(l), .loaded(r)): return l == r
        case let (.failed(l), .failed(r)): return l.localizedDescription == r.localizedDescription
        default: return false
        }
    }
}

@Observable @MainActor
final class ItemListViewModel {
    // State (always private(set))
    private(set) var state: LoadingState<[Item]> = .idle

    // Computed (derive, don't duplicate)
    var items: [Item] {
        if case .loaded(let items) = state { return items }
        return []
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var error: Error? {
        if case .failed(let error) = state { return error }
        return nil
    }

    // Dependencies (use @Dependency)
    @Dependency(\.itemService) var service
    private var loadTask: Task<Void, Never>?

    deinit { loadTask?.cancel() }

    // User actions (on prefix)
    func onAppeared() {
        loadTask = Task { await loadItems() }
    }

    // Private implementation
    private func loadItems() async {
        state = .loading
        do {
            let items = try await service.fetchItems()
            state = .loaded(items)
        } catch {
            state = .failed(error)
        }
    }
}
```
</pattern>

<pattern name="state_machine">
```swift
enum AuthState: Equatable {
    case loggedOut, loggingIn, loggedIn(User), failed(Error)
}

@Observable @MainActor
final class AuthViewModel {
    private(set) var state: AuthState = .loggedOut

    @Dependency(\.authService) var authService

    var isAuthenticated: Bool {
        if case .loggedIn = state { true } else { false }
    }

    func onSubmittedLogin(email: String, password: String) async {
        guard case .loggedOut = state else { return }
        state = .loggingIn

        do {
            let user = try await authService.login(email, password)
            state = .loggedIn(user)
        } catch {
            state = .failed(error)
        }
    }
}
```
</pattern>

<pattern name="search_debounce">
```swift
@Observable @MainActor
final class SearchViewModel {
    private(set) var searchText = ""
    private(set) var results: [Result] = []
    private var searchTask: Task<Void, Never>?

    @Dependency(\.searchService) var service

    func onChangedSearchText(_ text: String) {
        searchText = text
        searchTask?.cancel()

        guard !text.isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            results = try await service.search(text)
        }
    }
}
```
</pattern>

</patterns>

<antipatterns>

<antipattern id="business_logic">
```swift
// ❌ Business logic in ViewModel
func calculateTax(price: Decimal) -> Decimal {
    price * 0.08  // Belongs in service!
}

// ✅ Delegate to service
func onRequestedPrice(item: Item) async -> Decimal {
    await pricingService.calculateTotal(item)
}
```
</antipattern>

<antipattern id="mutable_state">
```swift
// ❌ Public mutable state
var items: [Item] = []  // Anyone can modify!

// ✅ Private setter
private(set) var items: [Item] = []
```
</antipattern>

<antipattern id="scattered_state">
```swift
// ❌ Scattered loading state (makes invalid states possible)
private(set) var items: [Item] = []
private(set) var isLoading = false
private(set) var error: Error?
// Can be: loading=true AND error!=nil (invalid!)

// ✅ Single source of truth with enum
enum LoadingState<T: Equatable>: Equatable {
    case idle, loading, loaded(T), failed(Error)
}
private(set) var state: LoadingState<[Item]> = .idle
```
</antipattern>

<antipattern id="view_reference">
```swift
// ❌ ViewModel knows about View
weak var view: MyView?  // Breaks MVVM!

// ✅ ViewModel exposes state
private(set) var errorMessage: String?
```
</antipattern>

</antipatterns>

<testing>
```swift
@Test("Search updates correctly")
func searchUpdate() async {
    let vm = await withDependencies {
        $0.searchService.search = { _ in [.init(id: "1")] }
    } operation: {
        SearchViewModel()
    }

    // Initial state
    #expect(vm.results.isEmpty)

    // Trigger search
    await vm.onChangedSearchText("query")

    // Wait for debounce
    try? await Task.sleep(for: .milliseconds(400))

    // Verify
    #expect(vm.results.count == 1)
}
```
</testing>

<checklist>
- [ ] All state uses `private(set)`
- [ ] Dependencies use @Dependency (no init injection)
- [ ] Business logic in services
- [ ] User actions prefixed with `on`
- [ ] Tasks cancellable
- [ ] Errors transformed for UI
- [ ] No force unwrapping
- [ ] No view references
- [ ] Computed properties for derived state
- [ ] Task cleanup in deinit
</checklist>

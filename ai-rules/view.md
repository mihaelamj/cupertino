<primary_objective>
Create SwiftUI Views that are purely presentational, performant, accessible, and reusable. Views observe ViewModels but contain ZERO business logic.
</primary_objective>

<cognitive_triggers>SwiftUI, View, Presentation, @ViewBuilder, ViewModifier, Accessibility, Performance, State Management, Hot Reload</cognitive_triggers>

<critical_rules>
1. Views render ViewModel state ONLY - no business logic, no API calls
2. Use @State for view-local UI state, @Bindable for ViewModel bindings
3. Use Lazy containers for lists >50 items
4. Every interactive element requires accessibility label
5. Extract components used 3+ times
6. Import Inject and add @ObserveInjection for hot reload
7. Use swift-navigation with @CasePathable enums for navigation state
</critical_rules>

<decision_tree>
Code belongs in View if:
├─ Visual presentation → YES
├─ UI animation → YES
├─ Local UI state → YES (@State)
├─ Data transformation → NO (ViewModel)
├─ Business logic → NO (ViewModel/Service)
└─ Navigation → View binds to ViewModel destination (swift-navigation)
</decision_tree>

<view_patterns>

<pattern name="pure_presentation">
```swift
// CORRECT
struct ProductCardView: View {
    let product: Product
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack {
                Text(product.name)
                Text(product.price, format: .currency(code: "USD"))
            }
        }
    }
}

// INCORRECT: View with business logic
struct BadProductView: View {
    let product: Product

    var body: some View {
        Button("Add to Cart") {
            // ❌ Direct API call in view
            Task {
                try? await APIClient.shared.addToCart(product)
            }
        }
    }
}
```
</pattern>

<pattern name="viewmodel_integration">
```swift
// Container gets injected ViewModel
struct ProductListScreen: View {
    @Bindable var viewModel: ProductListViewModel

    var body: some View {
        ProductListView(viewModel: viewModel)
            .task { await viewModel.onViewAppear() }
    }
}

// Inner view receives ViewModel
struct ProductListView: View {
    let viewModel: ProductListViewModel

    var body: some View {
        List(viewModel.products) { product in
            Button { viewModel.onUserSelected(product) } label: {
                Text(product.name)
            }
        }
    }
}
```
</pattern>

<pattern name="reusable_component">
```swift
// ViewBuilder slot
struct AsyncButton<Label: View>: View {
    let action: () async -> Void
    @ViewBuilder let label: () -> Label
    @State private var isLoading = false

    var body: some View {
        Button {
            Task {
                isLoading = true
                await action()
                isLoading = false
            }
        } label: {
            isLoading ? ProgressView() : label()
        }
        .disabled(isLoading)
    }
}

// ViewModifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
    }
}
```
</pattern>

<pattern name="accessibility">
```swift
TextField("Name", text: $name)
    .accessibilityLabel("Your name")
    .accessibilityHint("Required field")

Button("Submit", action: onSubmit)
    .accessibilityHint("Double tap to save")
```
</pattern>

<pattern name="navigation">
```swift
import SwiftNavigation

// Define destinations using @CasePathable
@CasePathable
enum Destination {
    case detail(DetailFeature)
    case settings(SettingsFeature)
    case alert(AlertState<AlertAction>)
}

@Observable @MainActor
final class AppViewModel {
    var destination: Destination?

    func onTappedItem(id: String) {
        destination = .detail(DetailFeature(id: id))
    }

    func onTappedSettings() {
        destination = .settings(SettingsFeature())
    }
}

struct AppView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        List {
            Button("Show Detail") { viewModel.onTappedItem(id: "123") }
            Button("Settings") { viewModel.onTappedSettings() }
        }
        .navigationDestination(item: $viewModel.destination.detail) { feature in
            DetailView(viewModel: feature)
        }
        .navigationDestination(item: $viewModel.destination.settings) { feature in
            SettingsView(viewModel: feature)
        }
        .alert($viewModel.destination.alert) { action in
            viewModel.onAlertAction(action)
        }
    }
}
```
</pattern>

<pattern name="sheets_and_covers">
```swift
// Sheets, fullScreenCovers, and popovers using swift-navigation
@CasePathable
enum Destination {
    case editSheet(EditFeature)
    case detailCover(DetailFeature)
    case confirmationAlert(AlertState<ConfirmAction>)
}

@Observable @MainActor
final class FeatureViewModel {
    var destination: Destination?

    func onTappedEdit() {
        destination = .editSheet(EditFeature())
    }

    func onTappedDetail() {
        destination = .detailCover(DetailFeature())
    }
}

struct FeatureView: View {
    @Bindable var viewModel: FeatureViewModel

    var body: some View {
        List {
            Button("Edit") { viewModel.onTappedEdit() }
            Button("Detail") { viewModel.onTappedDetail() }
        }
        .sheet(item: $viewModel.destination.editSheet) { feature in
            EditView(viewModel: feature)
        }
        .fullScreenCover(item: $viewModel.destination.detailCover) { feature in
            DetailView(viewModel: feature)
        }
        .alert($viewModel.destination.confirmationAlert) { action in
            viewModel.onConfirmAction(action)
        }
    }
}
```
</pattern>

<pattern name="hot_reload">
```swift
import Inject

struct ExampleView: View {
    @ObserveInjection var inject

    var body: some View {
        Text("Hello")
            .enableInjection()
    }
}
```
</pattern>

</view_patterns>

<validation_checklist>
- [ ] Zero business logic
- [ ] Actions forwarded to ViewModel
- [ ] Accessibility labels provided
- [ ] Performance optimized (lazy loading)
- [ ] Components extracted for reuse
- [ ] Hot reload enabled with Inject
- [ ] Navigation uses swift-navigation with @CasePathable destinations
- [ ] Error/loading/empty states handled
</validation_checklist>

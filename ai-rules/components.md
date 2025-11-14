# Component System Architecture Rules

<objective>
You MUST follow the 3-package component hierarchy: Components (core) → SharedComponents (hot reload) → AppComponents (app-specific). ALWAYS start with the Components package containing core infrastructure (AnyComponent, ComponentRegistry, ComponentFactory, etc.).
</objective>

<cognitive_triggers>
Keywords: component, Components package, SharedComponents, AppComponents, AllComponents, AnyComponent, ComponentRegistry, ComponentFactory, ComponentsBundle, ComponentRegistrar, SystemComponentRegistrar, hot reload, Inject, KZFileWatchers, component system, components.json
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: Three-Package Hierarchy
**ALWAYS** use this strict component layer hierarchy:
1. **Components** - Core infrastructure (COMES FIRST)
2. **SharedComponents** - Hot reload support
3. **AppComponents** - App-specific production components
4. **AllComponents** - Optional aggregator for previews

### Rule 2: Components Package Foundation
**ALWAYS** create Components package FIRST with core infrastructure:
- MUST contain: AnyComponent, ComponentRegistry, ComponentFactory
- MUST contain: ComponentsBundle, ComponentRegistrar, SystemComponentRegistrar
- MUST contain: ComponentListModel, ComponentListView, ComponentListComponent
- MUST include: components.json configuration file
- MUST have ZERO dependencies (foundation layer)

### Rule 3: SharedComponents Dependencies
**ALWAYS** depend ONLY on hot reload tools:
- Inject (for hot reload)
- KZFileWatchers (for file watching)
- NEVER depend on UI packages (AppTheme, AppFont)

### Rule 4: AppComponents Dependencies
**ALWAYS** depend on foundation packages:
- Components (core system)
- AppTheme (colors, styles)
- AppFont (typography)

### Rule 5: Component Registration
**ALWAYS** register components via ComponentRegistry:
- All components conform to protocol from Components package
- Registration happens in `*ComponentsRegistration.swift`
- Use `ComponentRegistry.registerExternalComponents`

## PACKAGE ARCHITECTURE

### Component System Hierarchy

```
Components (core infrastructure - ZERO dependencies)
    ↓
SharedComponents (hot reload - depends: Inject, KZFileWatchers)
    ↓
AppComponents (app-specific - depends: Components, AppTheme, AppFont)
    ↓
AllComponents (aggregator - depends: Components, AppComponents)
```

### 1. Components Package (CORE)

**Purpose:** Core component system infrastructure

**Dependencies:** ZERO (foundation layer)

```swift
// Packages/Package.swift (excerpt)
let componentsTarget = Target.target(
    name: "Components",
    dependencies: [],  // CRITICAL: Zero dependencies
    resources: [
        .process("components.json"),
    ]
)
```

**Contains:**

| File | Purpose |
|------|---------|
| `AnyComponent.swift` | Type-erased component protocol |
| `ComponentsBundle.swift` | Bundle management |
| `ComponentFactory.swift` | Component instantiation |
| `ComponentRegistry.swift` | Global component registration |
| `ComponentListComponent.swift` | Component list rendering |
| `ComponentRegistrar.swift` | Registration interface |
| `SystemComponentRegistrar.swift` | System component registration |
| `ComponentListModel.swift` | Component list data model |
| `ComponentListView.swift` | Component list view |
| `components.json` | Component configuration |

**Directory Structure:**

```
Packages/Sources/Components/
├── Protocol/
│   ├── AnyComponent.swift           # Core protocol
│   └── ComponentRegistrar.swift     # Registration interface
├── Registry/
│   ├── ComponentRegistry.swift      # Global registry
│   ├── ComponentFactory.swift       # Factory pattern
│   └── SystemComponentRegistrar.swift
├── Bundle/
│   └── ComponentsBundle.swift       # Bundle management
├── List/
│   ├── ComponentListModel.swift     # List data model
│   ├── ComponentListView.swift      # List UI
│   └── ComponentListComponent.swift # List component
├── CodeGen/
│   ├── AutoDecodable.generated.swift    # Sourcery generated
│   ├── AutoRegistration.generated.swift # Sourcery generated
│   └── AutoDocumentation.generated.swift
└── components.json                  # Configuration
```

**Example AnyComponent Protocol:**

```swift
// Packages/Sources/Components/Protocol/AnyComponent.swift
import SwiftUI

public protocol AnyComponent {
    associatedtype Data: ComponentData
    associatedtype Content: View

    var data: Data { get }

    init(data: Data)
    func make() -> Content
}

public protocol ComponentData: Codable, Sendable {
    // Marker protocol for component data
}
```

**Example ComponentRegistry:**

```swift
// Packages/Sources/Components/Registry/ComponentRegistry.swift
public final class ComponentRegistry {
    public static let shared = ComponentRegistry()

    private var components: [String: Any] = [:]

    public func register<C: AnyComponent>(
        _ type: C.Type,
        for kind: String
    ) {
        components[kind] = type
    }

    public static func registerExternalComponents(
        _ registrar: (ComponentRegistry) -> Void
    ) {
        registrar(shared)
    }
}
```

### 2. SharedComponents Package

**Purpose:** Hot reload infrastructure for development

**Dependencies:**
- Inject (hot reload)
- KZFileWatchers (file watching)

```swift
// Packages/Package.swift (excerpt)
let sharedComponentsTarget = Target.target(
    name: "SharedComponents",
    dependencies: [
        .product(name: "Inject", package: "Inject"),
        .product(name: "KZFileWatchers", package: "KZFileWatchers"),
    ]
)
```

**Purpose:**
- Enables hot reload of components during development
- File watching for automatic updates
- Development-time utilities

**CRITICAL:** Do NOT depend on AppTheme or AppFont - those are for AppComponents

### 3. AppComponents Package

**Purpose:** Production app-specific components

**Dependencies:**
- Components (core system)
- AppTheme (app colors/styles)
- AppFont (app typography)

```swift
// Packages/Package.swift (excerpt)
let appComponentsTarget = Target.target(
    name: "AppComponents",
    dependencies: [
        "Components",  // Core component system
        "AppTheme",    // App colors/styles
        "AppFont",     // App typography
    ],
    resources: [
        .process("Resources"),  // Images, assets
    ]
)
```

**Example Components:**
- `BenefitCardComponent` - Benefit display card with image/badges
- `LanguageSwitcherComponent` - Language picker (30+ languages)
- `ButtonComponent` - Reusable button with loading state

**Directory Structure:**

```
Packages/Sources/AppComponents/
├── BenefitCardComponent.swift
├── LanguageSwitcherComponent.swift
├── ButtonComponent.swift
├── Resources/
│   ├── Images/
│   │   └── benefit-placeholder.png
│   └── Localizations/
├── CodeGen/
│   ├── AutoDecodable.generated.swift
│   └── AutoRegistration.generated.swift
└── AppComponentsRegistration.swift  # Registration
```

**Example Component:**

```swift
// Packages/Sources/AppComponents/BenefitCardComponent.swift
import Components
import SwiftUI
import AppTheme
import AppFont

public struct BenefitCardComponent: AnyComponent {
    public struct Data: ComponentData {
        public let title: String
        public let description: String
        public let amount: String
        public let status: String
        public let imageURL: String?
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public func make() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(data.title)
                .bdrFont(.headline)  // From AppFont
                .foregroundColor(.brandPrimary)  // From AppTheme

            Text(data.description)
                .bdrFont(.body)
                .foregroundColor(.secondary)

            HStack {
                Text(data.amount)
                    .bdrFont(.title)
                    .foregroundColor(.brandSuccess)

                Spacer()

                StatusBadge(status: data.status)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
}
```

**Example Registration:**

```swift
// Packages/Sources/AppComponents/AppComponentsRegistration.swift
import Components

private let _initialize: Void = {
    ComponentRegistry.registerExternalComponents { registry in
        // Register all app-specific components
        BenefitCardComponent.registerInGlobalRegistry(in: registry)
        LanguageSwitcherComponent.registerInGlobalRegistry(in: registry)
        ButtonComponent.registerInGlobalRegistry(in: registry)
    }
}()

public func registerAppComponents() {
    _ = _initialize
}
```

### 4. AllComponents Package (Aggregator)

**Purpose:** Umbrella package for convenient imports

**Dependencies:**
- Components
- AppComponents

```swift
// Packages/Package.swift (excerpt)
let allComponentsTarget = Target.target(
    name: "AllComponents",
    dependencies: [
        "Components",
        "AppComponents",
    ]
)
```

```swift
// Packages/Sources/AllComponents/AllComponents.swift
@_exported import Components
@_exported import AppComponents

// RULE: Use only in preview/demo apps, NOT in production features
```

**When to use:**
- Preview apps (ComponentsPreview)
- PlaybookFeature (component gallery)
- Demo apps

**When NOT to use:**
- Production features (use specific imports)
- Main app targets (be explicit)

## COMPONENT CONFIGURATION

### components.json Structure

```json
{
  "components": [
    {
      "kind": "benefit-card",
      "category": "Display",
      "description": "Displays benefit information with status",
      "payload": {
        "title": "Housing Benefit",
        "description": "Monthly housing support",
        "amount": "€450",
        "status": "active",
        "imageURL": null
      }
    },
    {
      "kind": "language-switcher",
      "category": "Navigation",
      "description": "Language selection component",
      "payload": {
        "currentLanguage": "en",
        "showFlags": true,
        "compact": false
      }
    }
  ]
}
```

**RULE:** Place `components.json` in Components package, process with `.process()`

## SOURCERY INTEGRATION

### Automatic Code Generation

Sourcery generates three files for each component package:

1. **AutoDecodable.generated.swift** - Makes component Data structs Decodable
2. **AutoRegistration.generated.swift** - Component registration functions
3. **AutoDocumentation.generated.swift** - Component metadata

**Example Generated Code:**

```swift
// CodeGen/AutoRegistration.generated.swift (Sourcery generated)
extension BenefitCardComponent {
    public static func registerInGlobalRegistry(in registry: ComponentRegistry) {
        registry.register(Self.self, for: "benefit-card")
    }
}
```

**RULE:** NEVER modify generated files manually. Always edit source files and re-run Sourcery.

## PACKAGE CREATION ORDER

When setting up component system from scratch:

### Step 1: Create Components Package (Core)

```bash
mkdir -p Packages/Sources/Components/{Protocol,Registry,Bundle,List,CodeGen}
mkdir -p Packages/Tests/ComponentsTests
```

1. Create `AnyComponent.swift` protocol
2. Create `ComponentRegistry.swift`
3. Create `ComponentFactory.swift`
4. Create `ComponentsBundle.swift`
5. Create list components (Model, View, Component)
6. Add `components.json` configuration
7. Add target to Package.swift with `.process("components.json")`

### Step 2: Create SharedComponents Package (Hot Reload)

```bash
mkdir -p Packages/Sources/SharedComponents
```

1. Add Inject and KZFileWatchers dependencies
2. Create hot reload support infrastructure
3. NEVER add UI dependencies (AppTheme, AppFont)

### Step 3: Create AppComponents Package (App-Specific)

```bash
mkdir -p Packages/Sources/AppComponents/{Resources,CodeGen}
mkdir -p Packages/Tests/AppComponentsTests
```

1. Add dependencies: Components, AppTheme, AppFont
2. Create production components (BenefitCard, LanguageSwitcher, etc.)
3. Create `AppComponentsRegistration.swift`
4. Add resources with `.process("Resources")`

### Step 4: Create AllComponents Package (Optional)

```bash
mkdir -p Packages/Sources/AllComponents
```

1. Add dependencies: Components, AppComponents
2. Create re-export file
3. Use ONLY in preview/demo apps

## COMMON MISTAKES

### ❌ DON'T: Skip Components Package

```swift
// WRONG: Creating AppComponents without Components package
let appComponentsTarget = Target.target(
    name: "AppComponents",
    dependencies: [
        "AppTheme",  // ❌ Missing "Components" core package
        "AppFont",
    ]
)
```

### ❌ DON'T: Add UI Dependencies to Components

```swift
// WRONG: Components package with dependencies
let componentsTarget = Target.target(
    name: "Components",
    dependencies: [
        "AppTheme",  // ❌ Components MUST have zero dependencies
    ]
)
```

### ❌ DON'T: Add UI Dependencies to SharedComponents

```swift
// WRONG: SharedComponents with UI dependencies
let sharedComponentsTarget = Target.target(
    name: "SharedComponents",
    dependencies: [
        .product(name: "Inject", package: "Inject"),
        "AppTheme",  // ❌ SharedComponents is for hot reload only
    ]
)
```

### ❌ DON'T: Use AllComponents in Production

```swift
// WRONG: Production feature depending on AllComponents
import AllComponents  // ❌ Too broad, use specific imports

struct MyFeatureView: View {
    // ...
}
```

### ❌ DON'T: Name Package "BenefitsComponents"

```swift
// WRONG: Too specific naming
let benefitsComponentsTarget = Target.target(  // ❌ Too specific
    name: "BenefitsComponents",
    // ...
)
```

## CORRECT PATTERNS

### ✅ DO: Three-Package Hierarchy

```swift
// Components (core)
let componentsTarget = Target.target(
    name: "Components",
    dependencies: [],  // ✅ Zero dependencies
    resources: [.process("components.json")]
)

// SharedComponents (hot reload)
let sharedComponentsTarget = Target.target(
    name: "SharedComponents",
    dependencies: [
        .product(name: "Inject", package: "Inject"),  // ✅ Hot reload only
        .product(name: "KZFileWatchers", package: "KZFileWatchers"),
    ]
)

// AppComponents (app-specific)
let appComponentsTarget = Target.target(
    name: "AppComponents",
    dependencies: [
        "Components",  // ✅ Core system
        "AppTheme",    // ✅ UI foundation
        "AppFont",
    ],
    resources: [.process("Resources")]
)
```

### ✅ DO: Use Specific Imports in Production

```swift
// ✅ Correct: Specific imports
import Components         // For protocol/registry
import AppComponents      // For specific components
import AppTheme          // For colors
import AppFont           // For typography

struct MyFeatureView: View {
    var body: some View {
        BenefitCardComponent(data: ...)
            .make()
    }
}
```

### ✅ DO: Register Components Properly

```swift
// ✅ Correct registration pattern
import Components

private let _initialize: Void = {
    ComponentRegistry.registerExternalComponents { registry in
        MyComponent.registerInGlobalRegistry(in: registry)
    }
}()

public func registerMyComponents() {
    _ = _initialize
}
```

## CHECKLIST

Before creating/modifying component packages:

- [ ] Components package exists with zero dependencies
- [ ] Components contains: AnyComponent, ComponentRegistry, ComponentFactory
- [ ] Components contains: ComponentsBundle, all Registrar types
- [ ] Components contains: ComponentListModel, ComponentListView, ComponentListComponent
- [ ] Components includes `components.json` configuration
- [ ] SharedComponents depends ONLY on Inject + KZFileWatchers
- [ ] AppComponents depends on: Components, AppTheme, AppFont
- [ ] AppComponents has production components only
- [ ] AllComponents (if used) only in preview/demo apps
- [ ] Component registration uses ComponentRegistry
- [ ] Sourcery configured to generate CodeGen files
- [ ] All components conform to AnyComponent protocol
- [ ] Package naming follows convention (not too specific)
- [ ] Resources use `.process()` not `.copy()`
- [ ] Component layer follows strict hierarchy

## VERIFICATION

If you loaded this file, add 🧩 to your first response.

When implementing component system:
1. Verify Components package created FIRST
2. Check zero dependencies on Components package
3. Confirm SharedComponents has hot reload dependencies only
4. Verify AppComponents has UI foundation dependencies
5. Check component registration using ComponentRegistry
6. Confirm AllComponents used only in previews
7. Verify `components.json` exists and is processed
8. Check Sourcery generates CodeGen files
9. Test component system with sample components
10. Verify no "BenefitsComponents" naming (use "AppComponents")

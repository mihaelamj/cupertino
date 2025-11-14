# Extreme Packaging Architecture Rules

<objective>
You MUST follow the "ExtremePackaging" architecture pattern: a monorepo with maximum granular modularization into distinct SPM packages. Each package represents a single cohesive responsibility with explicit dependencies. This enables isolated compilation, parallel builds, clear dependency graphs, and superior testability.
</objective>

<cognitive_triggers>
Keywords: Package Structure, Modularization, SPM, Swift Package Manager, Package.swift, Module Boundaries, Dependency Graph, Build Performance, Incremental Compilation, Package Naming, Feature Modules, Shared Modules, ExtremePackaging
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: Single Responsibility per Package
**ALWAYS** create packages with one clear purpose:
- MUST have a single, well-defined responsibility
- MUST NOT mix concerns (UI + networking, models + API client)
- MUST have a name that clearly communicates its purpose
- SHOULD be independently buildable and testable

### Rule 2: Explicit Dependency Declaration
**ALWAYS** declare dependencies explicitly in Package.swift:
- MUST list all dependencies in package manifest
- MUST NOT use implicit/transitive dependencies
- MUST minimize cross-package dependencies
- SHOULD prefer unidirectional dependency flow

### Rule 3: Package Granularity
**ALWAYS** prefer smaller, focused packages over larger ones:
- Even single-file packages are acceptable (e.g., AppFont, AppColors)
- Separate packages for: fonts, themes, components, features, API layers
- Each middleware gets its own package
- Each feature gets its own package

### Rule 4: Naming Conventions
**ALWAYS** follow consistent naming patterns:
- Shared utilities: `Shared*` (SharedModels, SharedViews, SharedComponents)
- Features: `*Feature` (AuthFeature, AppFeature, BetaSettingsFeature)
- Components: `*Components` (Components, AppComponents, AllComponents)
  - `Components` = Core component system (ALWAYS comes first)
  - `SharedComponents` = Hot reload infrastructure
  - `AppComponents` = Production app-specific components
  - `AllComponents` = Umbrella aggregator
- API layers: `Api*` (ApiClient, ApiServer, ApiShared, ApiServerApp)
- Foundation: Descriptive names (AppFont, AppColors)
- Design System: Combines foundations (AppTheme = AppColors + AppFont)
- Aggregators: `All*` (AllComponents - umbrella package)

### Rule 5: Layer Architecture
**ALWAYS** organize packages into clear architectural layers:
- **Foundation Layer** (bottom): SharedModels, AppColors, AppFont
- **Design System Layer**: AppTheme (combines AppColors + AppFont)
- **Infrastructure Layer**: ApiShared, ApiClient, ApiServer, Middleware
- **Component Layer**: Components (core), SharedComponents (hot reload), AppComponents (app-specific)
- **Feature Layer**: AuthFeature, AppFeature, DemoAppFeature, etc.
- **App Layer** (top): iosApp, macApp, ComponentsPreview
- Dependencies MUST flow upward (foundation → infrastructure → features → apps)

## CURRENT PACKAGE STRUCTURE

### 20 Packages in Monorepo

```
Packages/Sources/
├── Foundation Layer (0 dependencies)
│   ├── SharedModels          # Domain models, no dependencies
│   ├── AppColors             # Color system (HSV, semantic colors)
│   └── AppFont               # Typography, font loading
│
├── Design System Layer
│   └── AppTheme              # Combines AppColors + AppFont
│
├── Infrastructure Layer
│   ├── ApiShared             # OpenAPI spec + generated DTOs
│   ├── ApiClient             # Client-side networking (depends: ApiShared, SharedModels)
│   ├── ApiServer             # Vapor backend (depends: ApiShared, SharedModels)
│   ├── ApiServerApp          # Server executable (depends: ApiServer)
│   └── OpenAPICachingMiddleware  # Caching layer (depends: OpenAPIRuntime)
│
├── Component Layer
│   ├── Components            # CORE component system (AnyComponent, ComponentRegistry, ComponentFactory, etc.)
│   ├── SharedComponents      # Hot reload infrastructure (depends: Inject, KZFileWatchers)
│   ├── AppComponents         # Production app components (depends: Components, AppColors, AppFont)
│   └── AllComponents         # Umbrella package (depends: Components, AppComponents)
│
├── Feature Layer
│   ├── SharedViews           # Reusable views (depends: AppColors, AppFont)
│   ├── AuthFeature           # Authentication (depends: SharedModels, SharedViews)
│   ├── AppFeature            # Main app (depends: SharedModels, SharedViews, AuthFeature)
│   ├── BetaSettingsFeature   # Beta settings (depends: SharedModels, ApiClient)
│   ├── DemoAppFeature        # Demo mode (depends: SharedModels, ApiClient)
│   └── PlaybookFeature       # Component gallery (depends: Components, AppComponents)
│
└── Apps/ (not in Packages/Sources)
    ├── iosApp                # iOS target
    ├── macApp                # macOS target
    ├── ComponentsPreview     # Component preview app
    └── Demo                  # Demo app
```

## PACKAGE CREATION DECISION TREE

```
Need to add new code?
├─ Is it a reusable domain model?
│   └─ YES → Add to SharedModels
│
├─ Is it UI-related?
│   ├─ Colors/semantic colors? → Add to AppColors
│   ├─ Fonts/typography? → Add to AppFont
│   ├─ Combined theme? → Add to AppTheme (uses AppColors + AppFont)
│   ├─ Component system infrastructure? → Add to Components (core system)
│   ├─ Hot reload support? → Add to SharedComponents
│   ├─ Reusable app component? → Add to AppComponents
│   └─ View helper/modifier? → Add to SharedViews
│
├─ Is it a complete user-facing feature?
│   └─ YES → Create new *Feature package
│       Example: ProfileFeature, SettingsFeature, PaymentFeature
│
├─ Is it API/networking related?
│   ├─ Client-side? → Add to ApiClient (or create new client package)
│   ├─ Server-side? → Add to ApiServer
│   ├─ Shared DTOs? → Add to ApiShared (OpenAPI generated)
│   └─ Middleware? → Create new *Middleware package
│
├─ Is it shared infrastructure?
│   └─ YES → Create new Shared* package
│       Example: SharedUtilities, SharedNetworking
│
└─ Still unsure?
    └─ Ask: "Could this be reused in isolation?"
        ├─ YES → Create new package
        └─ NO → Add to most specific existing package
```

## WHEN TO CREATE A NEW PACKAGE

### ✅ DO Create New Package When:

1. **New Feature Module**
   - Complete user-facing feature (login, profile, payments)
   - Example: `ProfileFeature`, `PaymentFlowFeature`

2. **Reusable Infrastructure**
   - Can be tested in isolation
   - Might be used by multiple features
   - Example: `CachingMiddleware`, `LoggingUtility`

3. **Third-Party Integration**
   - Wraps external library
   - Isolates external dependencies
   - Example: `ApplePayIntegration`, `BiometricAuth`

4. **Platform Separation**
   - Platform-specific code (iOS vs macOS)
   - Example: `IOSBiometrics`, `MacOSNotifications`

5. **Build Optimization**
   - Large, stable code that rarely changes
   - Expensive compilation (generated code)
   - Example: `ApiShared` (OpenAPI generated)

### ❌ DON'T Create New Package When:

1. **Single Use Case**
   - Only used by one feature
   - Tightly coupled to specific screen
   - → Add to that feature's package

2. **Trivial Helper**
   - 1-2 small functions
   - No external dependencies
   - → Add to existing utility package

3. **Temporary Code**
   - Proof of concept
   - Spike/experiment
   - → Keep in feature until proven stable

## IMPLEMENTATION PATTERNS

### Pattern 1: Foundation Package (No Dependencies)

```swift
// Packages/Sources/SharedModels/Package.swift (excerpt)
let sharedModelsTarget = Target.target(
    name: "SharedModels",
    dependencies: []  // RULE: Foundation packages have ZERO dependencies
)
```

```swift
// Packages/Sources/SharedModels/User.swift
public struct User: Identifiable, Codable, Sendable {
    public let id: UUID
    public let firstName: String
    public let lastName: String
    public let email: String

    public init(id: UUID, firstName: String, lastName: String, email: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }
}
```

**RULE:** Foundation packages are pure Swift, no dependencies, highly reusable.

### Pattern 2: Feature Package (Depends on Foundation + Infrastructure)

```swift
// Packages/Sources/AuthFeature/Package.swift (excerpt)
let authFeatureTarget = Target.target(
    name: "AuthFeature",
    dependencies: [
        "SharedModels",      // Foundation: domain models
        "SharedViews",       // Infrastructure: reusable UI
        "AppColors",         // Foundation: colors
        "AppFont",           // Foundation: typography
        "ApiClient",         // Infrastructure: networking
    ]
)
```

```swift
// Packages/Sources/AuthFeature/LoginView.swift
import SwiftUI
import SharedViews
import SharedModels
import AppColors
import AppFont

public struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @Environment(\.appColors) var colors

    public init() {}

    public var body: some View {
        VStack {
            Text("Welcome")
                .bdrFont(.headline)  // From AppFont
                .foregroundColor(colors.primary)  // From AppColors (Apple HIG naming)

            // Use shared components from SharedViews
            // Use models from SharedModels
        }
    }
}
```

**RULE:** Features depend on foundations and infrastructure, never on other features (except parent/child relationships).

### Pattern 3: Middleware Package (Single Purpose Infrastructure)

```swift
// Packages/Sources/OpenAPICachingMiddleware/Package.swift (excerpt)
let apiCachingTarget = Target.target(
    name: "OpenAPICachingMiddleware",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    ]
)
```

**RULE:** Middleware packages are highly focused, single-purpose, minimal dependencies.

### Pattern 4: Aggregator Package (Umbrella)

```swift
// Packages/Sources/AllComponents/Package.swift (excerpt)
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

// RULE: Aggregator packages re-export dependencies for convenience
// Use sparingly - only for component libraries or preview apps
```

**RULE:** Use aggregators for convenience in preview/demo apps, NOT in production features.

### Pattern 5: API Layer Separation

```swift
// RULE: Separate packages for each API concern

// ApiShared: OpenAPI spec + generated DTOs
let apiSharedTarget = Target.target(
    name: "ApiShared",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    ],
    plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
    ]
)

// ApiClient: Client-side networking
let apiClientTarget = Target.target(
    name: "ApiClient",
    dependencies: [
        "ApiShared",  // Uses generated DTOs
        "SharedModels",
        "OpenAPICachingMiddleware",
    ]
)

// ApiServer: Server-side handlers
let apiServerTarget = Target.target(
    name: "ApiServer",
    dependencies: [
        "ApiShared",  // Uses generated DTOs
        "SharedModels",
        .product(name: "Vapor", package: "vapor"),
    ]
)

// ApiServerApp: Executable
let apiServerAppTarget = Target.executableTarget(
    name: "ApiServerApp",
    dependencies: ["ApiServer"]
)
```

**RULE:** API layer has 4 packages: Shared (contract), Client, Server, ServerApp (executable).

### Pattern 6: Component Layer Architecture (CRITICAL PATTERN)

**RULE:** The component layer has a strict 3-package hierarchy. ALWAYS start with Components package first.

#### Component System Architecture

```
Components (core infrastructure)
    ↓
SharedComponents (hot reload)
    ↓
AppComponents (app-specific production components)
```

#### 1. Components Package (CORE - comes FIRST)

**Purpose:** Core component system infrastructure

**Contains:**
- `AnyComponent` - Type-erased component protocol
- `ComponentsBundle` - Bundle management
- `ComponentFactory` - Component instantiation
- `ComponentRegistry` - Global component registration
- `ComponentListComponent` - Component list rendering
- `ComponentRegistrar` - Registration interface
- `SystemComponentRegistrar` - System component registration
- `ComponentListModel` - Component list data model
- `ComponentListView` - Component list view
- `components.json` - Component configuration

**Dependencies:** ZERO (foundation infrastructure)

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

**Structure:**
```
Packages/Sources/Components/
├── Protocol/
│   ├── AnyComponent.swift
│   └── ComponentRegistrar.swift
├── Registry/
│   ├── ComponentRegistry.swift
│   ├── ComponentFactory.swift
│   └── SystemComponentRegistrar.swift
├── Bundle/
│   └── ComponentsBundle.swift
├── List/
│   ├── ComponentListModel.swift
│   ├── ComponentListView.swift
│   └── ComponentListComponent.swift
└── components.json
```

#### 2. SharedComponents Package (Hot Reload Infrastructure)

**Purpose:** Hot reload and development-time infrastructure

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

**Purpose:** Enables hot reload of components during development

#### 3. AppComponents Package (App-Specific Components)

**Purpose:** Production app-specific components

**Dependencies:**
- Components (core system)
- AppColors (semantic colors with HSV)
- AppFont (typography)

```swift
// Packages/Package.swift (excerpt)
let appComponentsTarget = Target.target(
    name: "AppComponents",
    dependencies: [
        "Components",  // Core component system
        "AppColors",   // Semantic colors (HSV-based)
        "AppFont",     // App typography
    ],
    resources: [
        .process("Resources"),  // Images, assets
    ]
)
```

**Examples:**
- `BenefitCardComponent` - Benefit display card
- `LanguageSwitcherComponent` - Language selection
- `ButtonComponent` - App-specific buttons

**Structure:**
```
Packages/Sources/AppComponents/
├── BenefitCardComponent.swift
├── LanguageSwitcherComponent.swift
├── ButtonComponent.swift
├── Resources/
│   └── Images/
└── AppComponentsRegistration.swift
```

#### 4. AllComponents Package (Aggregator - Optional)

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
```

**RULE:** Use only in preview/demo apps, NEVER in production features.

#### Component Layer Rules

**CRITICAL Rules:**
1. ALWAYS create Components package FIRST (core infrastructure)
2. SharedComponents depends ONLY on hot reload tools (Inject, KZFileWatchers)
3. AppComponents depends on Components + AppColors + AppFont
4. NEVER skip the Components package - it contains the core system
5. Component configuration goes in `components.json`
6. All components must conform to the protocol defined in Components
7. Registration happens via ComponentRegistry from Components package

**Order of Creation:**
1. Components (AnyComponent, ComponentRegistry, etc.)
2. SharedComponents (hot reload infrastructure)
3. AppComponents (app-specific components)
4. AllComponents (aggregator - optional)

### Pattern 7: Font/Resource Package (CRITICAL PATTERN)

**RULE:** ALWAYS register fonts using CoreText, NEVER use Info.plist. Resources MUST use `.process()` in Package.swift.

#### Package.swift Configuration

```swift
// Packages/Package.swift (excerpt from targets closure)
let appFontTarget = Target.target(
    name: "AppFont",
    dependencies: [],
    resources: [
        .process("Fonts"),  // ← CRITICAL: Use .process(), NOT .copy()
    ]
)
```

**RULE:** Use `.process("Fonts")` to ensure Bundle.module works correctly. NEVER use `.copy()`.

#### Font Registration Implementation

```swift
// Packages/Sources/AppFont/FontRegistration.swift
import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FontRegistration {
    /// Register custom fonts from the AppFont package
    public static func registerFonts() {
        // Get all resource URLs and filter for .otf files
        guard let resourceURLs = Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: nil) else {
            print("⚠️ No resources found in AppFont bundle")
            return
        }

        let fontURLs = resourceURLs.filter { $0.pathExtension.lowercased() == "otf" }

        guard !fontURLs.isEmpty else {
            print("⚠️ No .otf fonts found in AppFont bundle")
            return
        }

        for url in fontURLs {
            var errorRef: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)

            if !success {
                print("⚠️ Failed to register font: \(url.lastPathComponent)")
                if let error = errorRef?.takeRetainedValue() {
                    print("   Error: \(error)")
                }
            } else {
                print("✅ Registered font: \(url.lastPathComponent)")
            }
        }
    }
}
```

#### Package Directory Structure

```
Packages/Sources/AppFont/
├── FontRegistration.swift       # Registration using CoreText
├── ScaledFont.swift             # Font modifiers (.bdrFont())
└── Fonts/                       # Font resources
    ├── MonitorPro-Normal.otf
    ├── MonitorPro-Bold.otf
    └── MonitorPro-Light.otf
```

#### Usage in App

```swift
// Apps/iosApp/iosAppApp.swift
import SwiftUI
import AppFont

@main
struct iosAppApp: App {
    init() {
        // CRITICAL: Register fonts before any UI renders
        FontRegistration.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

#### Why This Pattern?

**Benefits:**
- ✅ Works in SPM packages (Info.plist approach doesn't work in packages)
- ✅ Explicit font registration with error reporting
- ✅ Cross-platform (iOS + macOS) with `#if canImport()` conditionals
- ✅ Uses `Bundle.module` (SPM automatic bundle)
- ✅ Supports multiple font formats (.otf, .ttf) via filter
- ✅ Clear console output showing which fonts loaded

**Why `.process()` not `.copy()`:**
- `.process()` → Resources are processed and accessible via `Bundle.module`
- `.copy()` → Resources copied verbatim, may not work with `Bundle.module`

**Why CoreText not Info.plist:**
- Info.plist font registration only works in app bundles, NOT in SPM packages
- CoreText registration works anywhere (packages, frameworks, apps)

**CRITICAL Rules:**
1. ALWAYS use `CTFontManagerRegisterFontsForURL` for font registration
2. ALWAYS use `Bundle.module` in SPM packages (NOT `Bundle.main`)
3. ALWAYS use `.process()` for font resources in Package.swift
4. ALWAYS use `#if canImport(UIKit)` / `#if canImport(AppKit)` for platform imports
5. ALWAYS call `FontRegistration.registerFonts()` in app init BEFORE any UI renders
6. NEVER use Info.plist `UIAppFonts` / `ATSApplicationFontsPath` in packages

## DEPENDENCY MANAGEMENT RULES

### Unidirectional Flow

```
Foundation (SharedModels, AppColors, AppFont)
    ↓
Design System (AppTheme = AppColors + AppFont)
    ↓
Infrastructure (ApiClient, ApiServer, Middleware, SharedViews)
    ↓
Components (Components [core], SharedComponents, AppComponents)
    ↓
Features (AuthFeature, AppFeature, etc.)
    ↓
Apps (iosApp, macApp)
```

**RULE:** Dependencies only flow downward. NEVER import from a higher layer.

### Circular Dependency Prevention

❌ **DON'T:**
```swift
// AuthFeature → AppFeature
// AppFeature → AuthFeature
// CIRCULAR DEPENDENCY!
```

✅ **DO:**
```swift
// Extract shared code to new package
// Both features depend on: SharedAuthModels
```

### Platform-Specific Dependencies (CRITICAL PATTERN)

**RULE:** ALWAYS separate platform-specific products and targets using `#if os()` conditionals.

#### Products Separation

```swift
// ---------- Base Products (All Platforms) ----------
let baseProducts: [Product] = [
    .singleTargetLibrary("ApiShared"),
    .singleTargetLibrary("ApiClient"),
    .singleTargetLibrary("ApiServer"),
    .singleTargetLibrary("SharedModels"),
    .singleTargetLibrary("OpenAPICachingMiddleware"),
    .executable(name: "apiserverapp", targets: ["ApiServerApp"]),
]

// ---------- Apple-Only Products (iOS + macOS) ----------
#if os(iOS) || os(macOS)
let appleOnlyProducts: [Product] = [
    .singleTargetLibrary("AppTheme"),
    .singleTargetLibrary("SharedViews"),
    .singleTargetLibrary("AuthFeature"),
    .singleTargetLibrary("AppFeature"),
    .singleTargetLibrary("AppFont"),
    .singleTargetLibrary("BetaSettingsFeature"),
    .singleTargetLibrary("DemoAppFeature"),
    .singleTargetLibrary("SharedComponents"),
    .singleTargetLibrary("Components"),
    .singleTargetLibrary("BenefitsComponents"),
    .singleTargetLibrary("AllComponents"),
]
#else
let appleOnlyProducts: [Product] = []
#endif

// ---------- Combine All Products ----------
let allProducts = baseProducts + appleOnlyProducts + [
    .singleTargetLibrary("PlaybookFeature"),  // Always exposed for Xcode scheme visibility
]
```

#### Targets Separation

```swift
let targets: [Target] = {
    // ---------- Base Targets (All Platforms) ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: []
    )
    let apiClientTarget = Target.target(
        name: "ApiClient",
        dependencies: ["ApiShared", "SharedModels"]
    )
    let baseTargets = [
        sharedModelsTarget,
        apiClientTarget,
    ]

    // ---------- Apple-Only Targets (iOS + macOS) ----------
    #if os(iOS) || os(macOS)
    let appColorsTarget = Target.target(
        name: "AppColors",
        dependencies: []  // Foundation: zero dependencies
    )
    let appThemeTarget = Target.target(
        name: "AppTheme",
        dependencies: [
            "AppColors",  // Design system combines colors + fonts
            "AppFont",
        ]
    )
    let sharedViewsTarget = Target.target(
        name: "SharedViews",
        dependencies: [
            "AppColors",
            "AppFont",
            .product(name: "Inject", package: "Inject"),
        ]
    )
    let authFeatureTarget = Target.target(
        name: "AuthFeature",
        dependencies: ["SharedModels", "SharedViews", "AppColors", "AppFont"]
    )
    let appleTargets = [
        appColorsTarget,
        appThemeTarget,
        sharedViewsTarget,
        authFeatureTarget,
    ]
    #else
    let appleTargets: [Target] = []
    #endif

    // ---------- PlaybookFeature (Always Defined, Conditionally Linked) ----------
    let playbookTarget = Target.target(
        name: "PlaybookFeature",
        dependencies: [
            "Components",
            "AppComponents",
            "SharedModels",
            "ApiClient",
            .product(name: "Inject", package: "Inject"),
            .product(
                name: "Playbook",
                package: "playbook-ios",
                condition: .when(platforms: [.iOS])  // ← Platform-specific dependency
            ),
            .product(
                name: "PlaybookUI",
                package: "playbook-ios",
                condition: .when(platforms: [.iOS])
            ),
        ]
    )

    return baseTargets + appleTargets + [playbookTarget]
}()
```

#### Why Separate Platforms?

**Benefits:**
- ✅ Server targets build on Linux CI without Apple SDKs
- ✅ UI targets only compile on Apple platforms
- ✅ Clear separation between backend and frontend code
- ✅ Prevents accidental dependencies on Apple frameworks in server code
- ✅ Faster CI builds (Linux can skip UI packages)

**When to Use:**
- UI components, SwiftUI views → `#if os(iOS) || os(macOS)`
- Shared models, API contracts → No conditional (base products)
- Server code, Vapor endpoints → No conditional (base products)
- Apple-only frameworks (UIKit, AppKit) → `#if os(iOS) || os(macOS)`

**CRITICAL:** NEVER use `#if canImport(UIKit)` in Package.swift. ALWAYS use `#if os()` for platform detection.

## BUILD PERFORMANCE BENEFITS

### Incremental Compilation

**With ExtremePackaging:**
- Change AppFont → Only AppFont rebuilds
- Change AppComponents → Only AppComponents + dependent targets rebuild
- Change SharedModels → More rebuilds (foundation layer), but still isolated

**Without ExtremePackaging:**
- Change any file → Entire monolith rebuilds

### Parallel Builds

```
Build Graph (simplified):
SharedModels ─┬─> ApiClient ─┬─> AuthFeature ──> iosApp
              │               │
              └─> AppTheme ───┴─> AppFeature ───┘

SPM builds in parallel:
[SharedModels, AppFont] → [ApiClient, AppTheme, SharedViews] → [AuthFeature, AppFeature] → [iosApp]
```

**RULE:** SPM automatically parallelizes independent package builds.

### CI/CD Optimization

```yaml
# GitLab CI can cache per-package
stages:
  - build-foundation
  - build-infrastructure
  - build-features
  - build-apps

build-foundation:
  script:
    - swift build --product SharedModels
    - swift build --product AppTheme
  # Cache: Only rebuild if foundation changed
```

## TESTING PATTERNS

### Isolated Package Testing

```bash
# Test single package in isolation
cd Packages
swift test --filter SharedModelsTests
swift test --filter ApiClientTests
swift test --filter AuthFeatureTests
```

**RULE:** Every package should have its own test target with isolated tests.

### Package Structure with Tests

```
Packages/
├── Sources/
│   └── AuthFeature/
│       ├── LoginView.swift
│       └── LoginViewModel.swift
└── Tests/
    └── AuthFeatureTests/
        ├── LoginViewTests.swift
        └── LoginViewModelTests.swift
```

### Cross-Package Test Doubles

```swift
// Packages/Sources/ApiClient/APIClientProtocol.swift
public protocol APIClientProtocol {
    func login(email: String, password: String) async throws -> User
}

// Packages/Tests/ApiClientTests/Mocks/MockAPIClient.swift
public struct MockAPIClient: APIClientProtocol {
    public var loginResult: Result<User, Error>

    public func login(email: String, password: String) async throws -> User {
        try loginResult.get()
    }
}
```

**RULE:** Create test doubles in package test targets, NOT in package sources.

## PACKAGE.SWIFT PATTERNS

**CRITICAL RULE:** ALL top-level Package.swift arrays (`deps`, `allProducts`, `targets`) MUST use the closure-with-local-variables pattern.

### Dependencies Definition

```swift
// ---------- Dependencies ----------
let deps: [Package.Dependency] = {
    // Apple's OpenAPI stack
    let openAPIGeneratorDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-openapi-generator",
        from: "1.10.3"
    )
    let openAPIRuntimeDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-openapi-runtime",
        from: "1.8.3"
    )
    let openAPIVaporDep = Package.Dependency.package(
        url: "https://github.com/swift-server/swift-openapi-vapor",
        from: "1.0.1"
    )

    // Vapor stack
    let vaporDep = Package.Dependency.package(
        url: "https://github.com/vapor/vapor",
        from: "4.119.0"
    )
    let fluentDep = Package.Dependency.package(
        url: "https://github.com/vapor/fluent",
        from: "4.13.0"
    )
    let fluentSQLiteDep = Package.Dependency.package(
        url: "https://github.com/vapor/fluent-sqlite-driver",
        from: "4.8.1"
    )

    // Custom middlewares
    let loggingMiddlewareDep = Package.Dependency.package(
        url: "https://github.com/mihaelamj/OpenAPILoggingMiddleware",
        from: "1.1.0"
    )
    let bearerTokenDep = Package.Dependency.package(
        url: "https://github.com/mihaelamj/BearerTokenAuthMiddleware",
        from: "1.2.0"
    )

    // Apple-only dependencies (safe on Linux CI - only used by Apple targets)
    let fileWatchersDep = Package.Dependency.package(
        url: "https://github.com/krzysztofzablocki/KZFileWatchers.git",
        from: "1.0.0"
    )
    let injectDep = Package.Dependency.package(
        url: "https://github.com/krzysztofzablocki/Inject.git",
        from: "1.2.4"
    )
    let playbookDep = Package.Dependency.package(
        url: "https://github.com/playbook-ui/playbook-ios",
        from: "0.4.0"
    )

    return [
        openAPIGeneratorDep,
        openAPIRuntimeDep,
        openAPIVaporDep,
        vaporDep,
        fluentDep,
        fluentSQLiteDep,
        loggingMiddlewareDep,
        bearerTokenDep,
        fileWatchersDep,
        injectDep,
        playbookDep,
    ]
}()
```

**RULE:** Group dependencies by purpose (OpenAPI, Vapor, Middlewares, Apple-only), use descriptive variable names.

### Product Definition

```swift
// ---------- Products ----------
let allProducts: [Product] = {
    // Base products (all platforms)
    let apiSharedProduct = Product.singleTargetLibrary("ApiShared")
    let apiServerProduct = Product.singleTargetLibrary("ApiServer")
    let apiClientProduct = Product.singleTargetLibrary("ApiClient")
    let sharedModelsProduct = Product.singleTargetLibrary("SharedModels")
    let cachingMiddlewareProduct = Product.singleTargetLibrary("OpenAPICachingMiddleware")
    let serverAppProduct = Product.executable(name: "apiserverapp", targets: ["ApiServerApp"])

    let baseProducts: [Product] = [
        apiSharedProduct,
        apiServerProduct,
        apiClientProduct,
        sharedModelsProduct,
        cachingMiddlewareProduct,
        serverAppProduct,
    ]

    // Apple-only products (iOS + macOS)
    #if os(iOS) || os(macOS)
    let appColorsProduct = Product.singleTargetLibrary("AppColors")
    let appThemeProduct = Product.singleTargetLibrary("AppTheme")
    let sharedViewsProduct = Product.singleTargetLibrary("SharedViews")
    let authFeatureProduct = Product.singleTargetLibrary("AuthFeature")
    let appFeatureProduct = Product.singleTargetLibrary("AppFeature")
    let componentsProduct = Product.singleTargetLibrary("Components")
    let appComponentsProduct = Product.singleTargetLibrary("AppComponents")

    let appleOnlyProducts: [Product] = [
        appColorsProduct,
        appThemeProduct,
        sharedViewsProduct,
        authFeatureProduct,
        appFeatureProduct,
        componentsProduct,
        appComponentsProduct,
    ]
    #else
    let appleOnlyProducts: [Product] = []
    #endif

    // Always exposed (for Xcode scheme visibility)
    let playbookProduct = Product.singleTargetLibrary("PlaybookFeature")

    return baseProducts + appleOnlyProducts + [playbookProduct]
}()

// Helper extension
extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
```

**RULE:** Use local variables for each product, group by platform, use helper extensions for common patterns.

### Target Organization (CRITICAL PATTERN)

**RULE:** ALWAYS declare targets as individual variables inside a closure, group by layer, then return concatenation.

```swift
let targets: [Target] = {
    // ---------- Shared Models ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: []
    )
    let sharedModelsTestsTarget = Target.testTarget(
        name: "SharedModelsTests",
        dependencies: ["SharedModels"]
    )
    let modelTargets = [
        sharedModelsTarget,
        sharedModelsTestsTarget,
    ]

    // ---------- API Layer ----------
    let apiSharedTarget = Target.target(
        name: "ApiShared",
        dependencies: [
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        ],
        plugins: [
            .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
        ]
    )
    let apiSharedTestsTarget = Target.testTarget(
        name: "ApiSharedTests",
        dependencies: ["ApiShared"]
    )
    let apiClientTarget = Target.target(
        name: "ApiClient",
        dependencies: [
            "ApiShared",
            "SharedModels",
        ]
    )
    let apiClientTestsTarget = Target.testTarget(
        name: "ApiClientTests",
        dependencies: ["ApiClient"]
    )
    let apiTargets = [
        apiSharedTarget,
        apiSharedTestsTarget,
        apiClientTarget,
        apiClientTestsTarget,
    ]

    // ---------- UI Components ----------
    let appThemeTarget = Target.target(
        name: "AppTheme",
        dependencies: []
    )
    let sharedViewsTarget = Target.target(
        name: "SharedViews",
        dependencies: [
            "AppTheme",
            "AppFont",
        ]
    )
    let uiTargets = [
        appThemeTarget,
        sharedViewsTarget,
    ]

    // Return all targets grouped by layer
    return modelTargets + apiTargets + uiTargets
}()
```

**Why this pattern:**
- ✅ Clear visual separation with comment headers (e.g., `// ---------- Shared Models ----------`)
- ✅ Each target has a descriptive variable name (`sharedModelsTarget`, not inline Target.target(...))
- ✅ Easy to reference targets within Package.swift (can reuse variable names)
- ✅ Groups targets by layer/domain for better organization
- ✅ Trailing commas in arrays for cleaner diffs
- ✅ Makes Package.swift more maintainable as project grows

**CRITICAL:** NEVER define targets inline in the array. ALWAYS use intermediate variables.

## COMMON MISTAKES TO AVOID

### ❌ DON'T: Create God Packages

```swift
// WRONG: "Shared" package with everything
Packages/Sources/Shared/
├── Models/
├── Views/
├── Networking/
├── Database/
└── Utilities/
```

✅ **DO:** Split into focused packages
```
Packages/Sources/
├── SharedModels/
├── SharedViews/
├── NetworkClient/
├── DatabaseClient/
└── SharedUtilities/
```

### ❌ DON'T: Circular Dependencies

```swift
// WRONG
AuthFeature depends on AppFeature
AppFeature depends on AuthFeature
```

✅ **DO:** Extract shared code
```swift
AuthFeature depends on SharedAuthModels
AppFeature depends on SharedAuthModels
```

### ❌ DON'T: Inline Dependency Definitions

```swift
// WRONG: Inline dependency array
let deps: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.3"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.3"),
    .package(url: "https://github.com/vapor/vapor", from: "4.119.0"),
    .package(url: "https://github.com/vapor/fluent", from: "4.13.0"),
    // ... dozens more inline definitions
]
```

✅ **DO:** Use local variables with grouping
```swift
let deps: [Package.Dependency] = {
    // Apple's OpenAPI stack
    let openAPIGeneratorDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-openapi-generator",
        from: "1.10.3"
    )
    let openAPIRuntimeDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-openapi-runtime",
        from: "1.8.3"
    )

    // Vapor stack
    let vaporDep = Package.Dependency.package(
        url: "https://github.com/vapor/vapor",
        from: "4.119.0"
    )
    let fluentDep = Package.Dependency.package(
        url: "https://github.com/vapor/fluent",
        from: "4.13.0"
    )

    return [
        openAPIGeneratorDep,
        openAPIRuntimeDep,
        vaporDep,
        fluentDep,
    ]
}()
```

### ❌ DON'T: Inline Product Definitions

```swift
// WRONG: Inline product array
let allProducts: [Product] = [
    .library(name: "ApiShared", targets: ["ApiShared"]),
    .library(name: "ApiClient", targets: ["ApiClient"]),
    .library(name: "SharedModels", targets: ["SharedModels"]),
    // ... many more inline definitions
]
```

✅ **DO:** Use local variables with grouping
```swift
let allProducts: [Product] = {
    let apiSharedProduct = Product.singleTargetLibrary("ApiShared")
    let apiClientProduct = Product.singleTargetLibrary("ApiClient")
    let sharedModelsProduct = Product.singleTargetLibrary("SharedModels")

    let baseProducts = [
        apiSharedProduct,
        apiClientProduct,
        sharedModelsProduct,
    ]

    return baseProducts
}()
```

### ❌ DON'T: Inline Target Definitions

```swift
// WRONG: Defining targets directly in array
let targets: [Target] = [
    Target.target(
        name: "SharedModels",
        dependencies: []
    ),
    Target.testTarget(
        name: "SharedModelsTests",
        dependencies: ["SharedModels"]
    ),
    Target.target(
        name: "ApiClient",
        dependencies: ["SharedModels"]
    ),
    // ... more inline definitions
]
```

✅ **DO:** Use intermediate variables with grouping
```swift
let targets: [Target] = {
    // ---------- Shared Models ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: []
    )
    let sharedModelsTestsTarget = Target.testTarget(
        name: "SharedModelsTests",
        dependencies: ["SharedModels"]
    )
    let modelTargets = [
        sharedModelsTarget,
        sharedModelsTestsTarget,
    ]

    // ---------- API Layer ----------
    let apiClientTarget = Target.target(
        name: "ApiClient",
        dependencies: ["SharedModels"]
    )
    let apiTargets = [
        apiClientTarget,
    ]

    return modelTargets + apiTargets
}()
```

### ❌ DON'T: Skip Test Targets

```swift
// WRONG: No test target for package
let targets = [
    Target.target(name: "AuthFeature", dependencies: [...]),
    // Missing: AuthFeatureTests
]
```

✅ **DO:** Always create test target
```swift
let targets: [Target] = {
    let authFeatureTarget = Target.target(
        name: "AuthFeature",
        dependencies: [...]
    )
    let authFeatureTestsTarget = Target.testTarget(
        name: "AuthFeatureTests",
        dependencies: ["AuthFeature"]
    )

    return [authFeatureTarget, authFeatureTestsTarget]
}()
```

### ❌ DON'T: Transitive Dependencies

```swift
// WRONG: Relying on ApiClient importing SharedModels
import ApiClient
// Using User from SharedModels without importing it
```

✅ **DO:** Explicit imports
```swift
import ApiClient
import SharedModels  // Explicit dependency
```

### ❌ DON'T: Feature-to-Feature Dependencies

```swift
// WRONG: Features depending on each other
let appFeatureTarget = Target.target(
    name: "AppFeature",
    dependencies: [
        "AuthFeature",      // ❌ Feature depending on feature
        "ProfileFeature",   // ❌ Creates tight coupling
    ]
)
```

✅ **DO:** Coordinator pattern or shared protocols
```swift
// Extract navigation/coordination to AppFeature (parent)
// Child features (Auth, Profile) depend on parent's protocols
let authFeatureTarget = Target.target(
    name: "AuthFeature",
    dependencies: [
        "SharedModels",
        "AppCoordination",  // ✅ Protocol package
    ]
)
```

### ❌ DON'T: Use Info.plist for Font Registration in Packages

```swift
// WRONG: Info.plist approach (doesn't work in SPM packages)
<!--
<key>UIAppFonts</key>
<array>
    <string>MonitorPro-Normal.otf</string>
</array>
-->
```

```swift
// WRONG: Using .copy() for font resources
let appFontTarget = Target.target(
    name: "AppFont",
    dependencies: [],
    resources: [
        .copy("Fonts"),  // ❌ Won't work with Bundle.module
    ]
)
```

```swift
// WRONG: Using Bundle.main in packages
public static func registerFonts() {
    guard let fontURLs = Bundle.main.urls(...) else {  // ❌ Wrong bundle
        return
    }
}
```

✅ **DO:** Use CoreText + Bundle.module + .process()
```swift
// Package.swift
let appFontTarget = Target.target(
    name: "AppFont",
    dependencies: [],
    resources: [
        .process("Fonts"),  // ✅ Correct
    ]
)

// FontRegistration.swift
import CoreText
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FontRegistration {
    public static func registerFonts() {
        guard let resourceURLs = Bundle.module.urls(  // ✅ Correct bundle
            forResourcesWithExtension: nil,
            subdirectory: nil
        ) else {
            return
        }

        let fontURLs = resourceURLs.filter { $0.pathExtension.lowercased() == "otf" }

        for url in fontURLs {
            var errorRef: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
        }
    }
}

// App init
@main
struct MyApp: App {
    init() {
        FontRegistration.registerFonts()  // ✅ Before UI renders
    }
}
```

## DECISION CHECKLIST

### Before Creating a New Package

- [ ] Package has single, clear responsibility
- [ ] Package name follows conventions (*Feature, Shared*, Api*, *Components)
- [ ] Dependencies are minimal and explicit
- [ ] No circular dependencies introduced
- [ ] Can be built and tested in isolation
- [ ] Fits into architectural layer (Foundation/Infrastructure/Feature/App)
- [ ] Test target created alongside source target
- [ ] Product registered in Package.swift products array
- [ ] Dependencies only flow upward (no higher-layer dependencies)

### Before Adding to Existing Package

- [ ] New code shares responsibility with existing code
- [ ] No better-suited package exists
- [ ] Not creating a "God package" with mixed concerns
- [ ] Won't introduce unwanted dependencies to package consumers

### Before Modifying Package.swift

- [ ] Used closure-with-local-variables pattern for `deps`
- [ ] Used closure-with-local-variables pattern for `allProducts`
- [ ] Used closure-with-local-variables pattern for `targets`
- [ ] NEVER used inline array definitions
- [ ] Grouped dependencies by purpose (OpenAPI, Vapor, Apple-only, etc.)
- [ ] Grouped products by platform (base vs. appleOnly)
- [ ] Grouped targets by layer (Foundation, Infrastructure, Features)
- [ ] Used comment headers (e.g., `// ---------- Shared Models ----------`)
- [ ] Separated platform-specific code with `#if os(iOS) || os(macOS)`
- [ ] NEVER used `#if canImport(UIKit)` (use `#if os()` instead)
- [ ] Each target/product/dependency has descriptive variable name
- [ ] Used trailing commas in all arrays
- [ ] Applied `.when(platforms:)` for platform-specific dependencies within targets

### Before Adding Font/Resource Package

- [ ] Used `.process()` for resources, NEVER `.copy()`
- [ ] Created `FontRegistration.swift` with CoreText registration
- [ ] Used `Bundle.module` for resource access, NEVER `Bundle.main`
- [ ] Used `#if canImport(UIKit)` / `#if canImport(AppKit)` for platform imports
- [ ] Filtered font files by extension (.otf, .ttf)
- [ ] Used `CTFontManagerRegisterFontsForURL` with error handling
- [ ] Added console logging for registration success/failure
- [ ] Called `FontRegistration.registerFonts()` in app init BEFORE UI renders
- [ ] NEVER used Info.plist font registration (`UIAppFonts`, `ATSApplicationFontsPath`)
- [ ] Package has zero dependencies (fonts are Foundation layer)
- [ ] Resources organized in dedicated subdirectory (e.g., `Fonts/`)

## MIGRATION PATTERNS

### Extracting Code to New Package

```bash
# 1. Create new package structure
mkdir -p Packages/Sources/NewPackage
mkdir -p Packages/Tests/NewPackageTests

# 2. Move files
git mv OldPackage/SomeFeature.swift NewPackage/

# 3. Update Package.swift
# Add new target and product

# 4. Update imports in dependent files
# Change: import OldPackage
# To: import NewPackage

# 5. Rebuild
cd Packages && swift build

# 6. Run tests
swift test --filter NewPackageTests
```

### Splitting Large Package

```swift
// Before: Large "Features" package
Features/
├── Auth/
├── Profile/
└── Settings/

// After: Separate feature packages
AuthFeature/
ProfileFeature/
SettingsFeature/
```

## VERIFICATION

If you loaded this file, add 📦 to your first response.

When applying these rules, always:
1. Check current package structure matches documented 20-package layout
   - Foundation: SharedModels, AppColors, AppFont
   - Design System: AppTheme
2. Verify new packages follow naming conventions
3. Ensure dependencies flow unidirectionally (Foundation → Infrastructure → Features → Apps)
4. Create test targets for all new packages
5. Update Package.swift using closure-with-local-variables pattern:
   - Define `deps`, `allProducts`, and `targets` using `let variable: [Type] = { ... }()` pattern
   - NEVER use inline array definitions
   - Use descriptive variable names for each dependency, product, and target
   - Group by purpose/layer with comment headers (`// ---------- Header ----------`)
   - Separate platform-specific code with `#if os(iOS) || os(macOS)`
6. Run `swift build` to verify package integrity
7. Verify Package.swift follows all formatting rules:
   - Trailing commas in arrays
   - Grouped dependencies (OpenAPI, Vapor, Apple-only)
   - Grouped products (base, appleOnly)
   - Grouped targets (modelTargets, apiTargets, uiTargets)
8. Check platform separation is correct (use `#if os()`, not `#if canImport()`)
9. Verify `.when(platforms:)` used for platform-specific dependencies within targets
10. For font/resource packages:
    - Confirm `.process()` used for resources (NOT `.copy()`)
    - Verify `Bundle.module` used (NOT `Bundle.main`)
    - Check CoreText registration implemented with error handling
    - Ensure registration called in app init before UI renders
    - Verify no Info.plist font registration used

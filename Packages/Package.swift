// swift-tools-version: 6.0

import PackageDescription

// -------------------------------------------------------------

// MARK: Products

// -------------------------------------------------------------

let baseProducts: [Product] = [
    .singleTargetLibrary("SharedModels"),
    // MCP Framework (cross-platform)
    .singleTargetLibrary("MCPShared"),
    .singleTargetLibrary("MCPTransport"),
    .singleTargetLibrary("MCPServer"),
]

#if os(iOS) || os(macOS)
let appleOnlyProducts: [Product] = [
    .singleTargetLibrary("AppColors"),
    .singleTargetLibrary("AppTheme"),
    .singleTargetLibrary("SharedViews"),
    .singleTargetLibrary("AuthFeature"),
    .singleTargetLibrary("AppFeature"),
    .singleTargetLibrary("AppFont"),
    .singleTargetLibrary("BetaSettingsFeature"),
    .singleTargetLibrary("DemoAppFeature"),
    .singleTargetLibrary("SharedComponents"),
    .singleTargetLibrary("Components"),
    .singleTargetLibrary("AppComponents"),
    .singleTargetLibrary("AllComponents"),
]
#else
let appleOnlyProducts: [Product] = []
#endif

// Docsucker products (macOS only - uses FileManager.homeDirectoryForCurrentUser)
#if os(macOS)
let macOSOnlyProducts: [Product] = [
    .singleTargetLibrary("DocsuckerShared"),
    .singleTargetLibrary("DocsuckerCore"),
    .singleTargetLibrary("DocsuckerMCPSupport"),
    .executable(name: "docsucker", targets: ["DocsuckerCLI"]),
    .executable(name: "docsucker-mcp", targets: ["DocsuckerMCP"]),
]
#else
let macOSOnlyProducts: [Product] = []
#endif

// Always expose PlaybookFeature so Xcode shows the scheme
let allProducts = baseProducts + appleOnlyProducts + macOSOnlyProducts + [
    .singleTargetLibrary("PlaybookFeature"),
]

// -------------------------------------------------------------

// MARK: Dependencies (updated versions)

// -------------------------------------------------------------

let deps: [Package.Dependency] = [
    // Swift Argument Parser (cross-platform CLI tool)
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    // apple-only deps (only referenced by apple-only targets, safe on Linux CI)
    .package(url: "https://github.com/krzysztofzablocki/KZFileWatchers.git", from: "1.0.0"),
    .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.2.4"),
    .package(url: "https://github.com/AvdLee/Roadmap.git", branch: "main"),
    .package(url: "https://github.com/playbook-ui/playbook-ios", from: "0.4.0"),
]

// -------------------------------------------------------------

// MARK: Targets

// -------------------------------------------------------------

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

    // ---------- MCP Framework (Foundation → Infrastructure) ----------
    let mcpSharedTarget = Target.target(
        name: "MCPShared",
        dependencies: []
    )
    let mcpSharedTestsTarget = Target.testTarget(
        name: "MCPSharedTests",
        dependencies: ["MCPShared"]
    )

    let mcpTransportTarget = Target.target(
        name: "MCPTransport",
        dependencies: ["MCPShared"]
    )
    let mcpTransportTestsTarget = Target.testTarget(
        name: "MCPTransportTests",
        dependencies: ["MCPTransport"]
    )

    let mcpServerTarget = Target.target(
        name: "MCPServer",
        dependencies: ["MCPShared", "MCPTransport"]
    )
    let mcpServerTestsTarget = Target.testTarget(
        name: "MCPServerTests",
        dependencies: ["MCPServer"]
    )

    let mcpTargets = [
        mcpSharedTarget,
        mcpSharedTestsTarget,
        mcpTransportTarget,
        mcpTransportTestsTarget,
        mcpServerTarget,
        mcpServerTestsTarget,
    ]

    let apiTargets: [Target] = []

    // ---------- Apple-only UI / Components ----------
    #if os(iOS) || os(macOS)
    // ---------- Foundation: AppColors (zero dependencies) ----------
    let appColorsTarget = Target.target(
        name: "AppColors",
        dependencies: []
    )

    let sharedComponentsTarget = Target.target(
        name: "SharedComponents",
        dependencies: [
            .product(name: "Inject", package: "Inject"),
            .product(name: "KZFileWatchers", package: "KZFileWatchers"),
        ]
    )

    let componentsTarget = Target.target(
        name: "Components",
        dependencies: ["SharedComponents"],
        resources: [.process("components.json")]
    )

    let appComponentsTarget = Target.target(
        name: "AppComponents",
        dependencies: ["Components", "AppTheme", "AppFont"],
        resources: [.process("Resources")]
    )

    let allComponentsTarget = Target.target(
        name: "AllComponents",
        dependencies: ["Components", "AppComponents"]
    )

    let appThemeTarget = Target.target(
        name: "AppTheme",
        dependencies: ["AppColors", "AppFont"]
    )

    let sharedViewsTarget = Target.target(
        name: "SharedViews",
        dependencies: [
            "AppTheme",
            "AppFont",
            .product(name: "Inject", package: "Inject"),
        ]
    )

    let authFeatureTarget = Target.target(
        name: "AuthFeature",
        dependencies: ["SharedModels", "SharedViews", "AppTheme", "AppFont"]
    )

    let appFeatureTarget = Target.target(
        name: "AppFeature",
        dependencies: ["SharedModels", "SharedViews", "AuthFeature", "AppFont"]
    )

    let appFontTarget = Target.target(
        name: "AppFont",
        dependencies: [],
        resources: [.process("Fonts")]
    )

    let betaSettingsFeatureTarget = Target.target(
        name: "BetaSettingsFeature",
        dependencies: [
            "SharedModels",
        ]
    )

    let demoAppFeatureTarget = Target.target(
        name: "DemoAppFeature",
        dependencies: [
            "SharedModels",
            "BetaSettingsFeature",
        ]
    )
    #endif

    // ---------- Docsucker (Apple Docs Crawler → MCP Server - macOS only) ----------
    #if os(macOS)
    let docsuckerSharedTarget = Target.target(
        name: "DocsuckerShared",
        dependencies: ["MCPShared"]
    )
    let docsuckerSharedTestsTarget = Target.testTarget(
        name: "DocsuckerSharedTests",
        dependencies: ["DocsuckerShared"]
    )

    let docsuckerCoreTarget = Target.target(
        name: "DocsuckerCore",
        dependencies: ["DocsuckerShared"]
    )
    let docsuckerCoreTestsTarget = Target.testTarget(
        name: "DocsuckerCoreTests",
        dependencies: ["DocsuckerCore"]
    )

    let docsuckerMCPSupportTarget = Target.target(
        name: "DocsuckerMCPSupport",
        dependencies: ["MCPServer", "MCPShared", "DocsuckerShared"]
    )
    let docsuckerMCPSupportTestsTarget = Target.testTarget(
        name: "DocsuckerMCPSupportTests",
        dependencies: ["DocsuckerMCPSupport"]
    )

    let docsuckerCLITarget = Target.executableTarget(
        name: "DocsuckerCLI",
        dependencies: [
            "DocsuckerShared",
            "DocsuckerCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let docsuckerMCPTarget = Target.executableTarget(
        name: "DocsuckerMCP",
        dependencies: [
            "MCPServer",
            "MCPTransport",
            "DocsuckerShared",
            "DocsuckerCore",
            "DocsuckerMCPSupport",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let docsuckerTargets: [Target] = [
        docsuckerSharedTarget,
        docsuckerSharedTestsTarget,
        docsuckerCoreTarget,
        docsuckerCoreTestsTarget,
        docsuckerMCPSupportTarget,
        docsuckerMCPSupportTestsTarget,
        docsuckerCLITarget,
        docsuckerMCPTarget,
    ]
    #else
    let docsuckerTargets: [Target] = []
    #endif

    // ---------- PlaybookFeature (scheme visible everywhere; links Playbook only on iOS) ----------
    let playbookTarget = Target.target(
        name: "PlaybookFeature",
        dependencies: [
            "Components",
            "AppComponents",
            "SharedModels",
            .product(name: "Inject", package: "Inject"),
            .product(
                name: "Playbook",
                package: "playbook-ios",
                condition: .when(platforms: [.iOS])
            ),
            .product(
                name: "PlaybookUI",
                package: "playbook-ios",
                condition: .when(platforms: [.iOS])
            ),
        ]
    )

    // Collect UI/component targets
    #if os(iOS) || os(macOS)
    let componentTargets: [Target] = [
        sharedComponentsTarget,
        componentsTarget,
        appComponentsTarget,
        allComponentsTarget,
    ]

    let uiTargets: [Target] = [
        appColorsTarget,
        appThemeTarget,
        sharedViewsTarget,
        authFeatureTarget,
        appFeatureTarget,
        appFontTarget,
        betaSettingsFeatureTarget,
        demoAppFeatureTarget,
        playbookTarget, // in uiTargets as requested
    ]
    #else
    let componentTargets: [Target] = []
    let uiTargets: [Target] = [playbookTarget]
    let docsuckerTargets: [Target] = []
    #endif

    return modelTargets + mcpTargets + apiTargets + componentTargets + uiTargets + docsuckerTargets
}()

// -------------------------------------------------------------

// MARK: Package

// -------------------------------------------------------------

let package = Package(
    name: "Main",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: allProducts,
    dependencies: deps,
    targets: targets
)

// -------------------------------------------------------------

// MARK: Helper

// -------------------------------------------------------------

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}

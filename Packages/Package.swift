// swift-tools-version: 6.2

import PackageDescription

// -------------------------------------------------------------

// MARK: Products

// -------------------------------------------------------------

let baseProducts: [Product] = [
    // MCP Framework (cross-platform)
    .singleTargetLibrary("MCPShared"),
    .singleTargetLibrary("MCPTransport"),
    .singleTargetLibrary("MCPServer"),
]

// Docsucker products (macOS only - uses FileManager.homeDirectoryForCurrentUser)
#if os(macOS)
let macOSOnlyProducts: [Product] = [
    .singleTargetLibrary("DocsuckerLogging"),
    .singleTargetLibrary("DocsuckerShared"),
    .singleTargetLibrary("DocsuckerCore"),
    .singleTargetLibrary("DocsuckerSearch"),
    .singleTargetLibrary("DocsuckerMCPSupport"),
    .singleTargetLibrary("DocsSearchToolProvider"),
    .executable(name: "appledocsucker", targets: ["DocsuckerCLI"]),
    .executable(name: "appledocsucker-mcp", targets: ["DocsuckerMCP"]),
]
#else
let macOSOnlyProducts: [Product] = []
#endif

let allProducts = baseProducts + macOSOnlyProducts

// -------------------------------------------------------------

// MARK: Dependencies

// -------------------------------------------------------------

let deps: [Package.Dependency] = [
    // Swift Argument Parser (cross-platform CLI tool)
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
]

// -------------------------------------------------------------

// MARK: Targets

// -------------------------------------------------------------

let targets: [Target] = {
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

    // ---------- Docsucker (Apple Docs Crawler → MCP Server - macOS only) ----------
    #if os(macOS)
    let docsuckerLoggingTarget = Target.target(
        name: "DocsuckerLogging",
        dependencies: []
    )
    let docsuckerLoggingTestsTarget = Target.testTarget(
        name: "DocsuckerLoggingTests",
        dependencies: ["DocsuckerLogging"]
    )

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
        dependencies: ["DocsuckerShared", "DocsuckerLogging"]
    )
    let docsuckerCoreTestsTarget = Target.testTarget(
        name: "DocsuckerCoreTests",
        dependencies: ["DocsuckerCore"]
    )

    let docsuckerSearchTarget = Target.target(
        name: "DocsuckerSearch",
        dependencies: ["DocsuckerShared", "DocsuckerLogging"]
    )
    let docsuckerSearchTestsTarget = Target.testTarget(
        name: "DocsuckerSearchTests",
        dependencies: ["DocsuckerSearch"]
    )

    let docsuckerMCPSupportTarget = Target.target(
        name: "DocsuckerMCPSupport",
        dependencies: ["MCPServer", "MCPShared", "DocsuckerShared", "DocsuckerLogging"]
    )
    let docsuckerMCPSupportTestsTarget = Target.testTarget(
        name: "DocsuckerMCPSupportTests",
        dependencies: ["DocsuckerMCPSupport"]
    )

    let docsSearchToolProviderTarget = Target.target(
        name: "DocsSearchToolProvider",
        dependencies: ["MCPServer", "MCPShared", "DocsuckerSearch"]
    )
    let docsSearchToolProviderTestsTarget = Target.testTarget(
        name: "DocsSearchToolProviderTests",
        dependencies: ["DocsSearchToolProvider"]
    )

    let docsuckerCLITarget = Target.executableTarget(
        name: "DocsuckerCLI",
        dependencies: [
            "DocsuckerShared",
            "DocsuckerCore",
            "DocsuckerSearch",
            "DocsuckerLogging",
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
            "DocsuckerSearch",
            "DocsuckerMCPSupport",
            "DocsSearchToolProvider",
            "DocsuckerLogging",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let docsuckerTargets: [Target] = [
        docsuckerLoggingTarget,
        docsuckerLoggingTestsTarget,
        docsuckerSharedTarget,
        docsuckerSharedTestsTarget,
        docsuckerCoreTarget,
        docsuckerCoreTestsTarget,
        docsuckerSearchTarget,
        docsuckerSearchTestsTarget,
        docsuckerMCPSupportTarget,
        docsuckerMCPSupportTestsTarget,
        docsSearchToolProviderTarget,
        docsSearchToolProviderTestsTarget,
        docsuckerCLITarget,
        docsuckerMCPTarget,
    ]
    #else
    let docsuckerTargets: [Target] = []
    #endif

    return mcpTargets + docsuckerTargets
}()

// -------------------------------------------------------------

// MARK: Package

// -------------------------------------------------------------

let package = Package(
    name: "Docsucker",
    platforms: [
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

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

// Cupertino products (macOS only - uses FileManager.homeDirectoryForCurrentUser)
#if os(macOS)
let macOSOnlyProducts: [Product] = [
    .singleTargetLibrary("CupertinoLogging"),
    .singleTargetLibrary("CupertinoShared"),
    .singleTargetLibrary("CupertinoCore"),
    .singleTargetLibrary("CupertinoSearch"),
    .singleTargetLibrary("CupertinoMCPSupport"),
    .singleTargetLibrary("CupertinoSearchToolProvider"),
    .executable(name: "cupertino", targets: ["CupertinoCLI"]),
    .executable(name: "cupertino-mcp", targets: ["CupertinoMCP"]),
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
        dependencies: ["CupertinoShared", "MCPShared"]
    )
    let mcpTransportTestsTarget = Target.testTarget(
        name: "MCPTransportTests",
        dependencies: ["MCPTransport"]
    )

    let mcpServerTarget = Target.target(
        name: "MCPServer",
        dependencies: ["MCPShared", "MCPTransport", "CupertinoShared"]
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

    // ---------- Cupertino (Apple Docs Crawler → MCP Server - macOS only) ----------
    #if os(macOS)
    let cupertinoLoggingTarget = Target.target(
        name: "CupertinoLogging",
        dependencies: ["CupertinoShared"]
    )
    let cupertinoLoggingTestsTarget = Target.testTarget(
        name: "CupertinoLoggingTests",
        dependencies: ["CupertinoLogging"]
    )

    let cupertinoSharedTarget = Target.target(
        name: "CupertinoShared",
        dependencies: ["MCPShared"]
    )
    let cupertinoSharedTestsTarget = Target.testTarget(
        name: "CupertinoSharedTests",
        dependencies: ["CupertinoShared"]
    )

    let cupertinoCoreTarget = Target.target(
        name: "CupertinoCore",
        dependencies: ["CupertinoShared", "CupertinoLogging"]
    )
    let cupertinoCoreTestsTarget = Target.testTarget(
        name: "CupertinoCoreTests",
        dependencies: ["CupertinoCore", "CupertinoSearch"]
    )

    let cupertinoSearchTarget = Target.target(
        name: "CupertinoSearch",
        dependencies: ["CupertinoShared", "CupertinoLogging"]
    )
    let cupertinoSearchTestsTarget = Target.testTarget(
        name: "CupertinoSearchTests",
        dependencies: ["CupertinoSearch"]
    )

    let cupertinoMCPSupportTarget = Target.target(
        name: "CupertinoMCPSupport",
        dependencies: ["MCPServer", "MCPShared", "CupertinoShared", "CupertinoLogging"]
    )
    let cupertinoMCPSupportTestsTarget = Target.testTarget(
        name: "CupertinoMCPSupportTests",
        dependencies: ["CupertinoMCPSupport"]
    )

    let cupertinoSearchToolProviderTarget = Target.target(
        name: "CupertinoSearchToolProvider",
        dependencies: ["MCPServer", "MCPShared", "CupertinoSearch"]
    )
    let cupertinoSearchToolProviderTestsTarget = Target.testTarget(
        name: "CupertinoSearchToolProviderTests",
        dependencies: ["CupertinoSearchToolProvider"]
    )

    let cupertinoCLITarget = Target.executableTarget(
        name: "CupertinoCLI",
        dependencies: [
            "CupertinoShared",
            "CupertinoCore",
            "CupertinoSearch",
            "CupertinoLogging",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let cupertinoMCPTarget = Target.executableTarget(
        name: "CupertinoMCP",
        dependencies: [
            "MCPServer",
            "MCPTransport",
            "CupertinoShared",
            "CupertinoCore",
            "CupertinoSearch",
            "CupertinoMCPSupport",
            "CupertinoSearchToolProvider",
            "CupertinoLogging",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let cupertinoTargets: [Target] = [
        cupertinoLoggingTarget,
        cupertinoLoggingTestsTarget,
        cupertinoSharedTarget,
        cupertinoSharedTestsTarget,
        cupertinoCoreTarget,
        cupertinoCoreTestsTarget,
        cupertinoSearchTarget,
        cupertinoSearchTestsTarget,
        cupertinoMCPSupportTarget,
        cupertinoMCPSupportTestsTarget,
        cupertinoSearchToolProviderTarget,
        cupertinoSearchToolProviderTestsTarget,
        cupertinoCLITarget,
        cupertinoMCPTarget,
    ]
    #else
    let cupertinoTargets: [Target] = []
    #endif

    return mcpTargets + cupertinoTargets
}()

// -------------------------------------------------------------

// MARK: Package

// -------------------------------------------------------------

let package = Package(
    name: "Cupertino",
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

// swift-tools-version: 6.2

import PackageDescription

// -------------------------------------------------------------

// MARK: Products

// -------------------------------------------------------------

let baseProducts: [Product] = [
    // MCP Framework (cross-platform, consolidated from MCPShared + MCPTransport + MCPServer)
    .singleTargetLibrary("MCP"),
]

// Cupertino products (macOS only - uses FileManager.homeDirectoryForCurrentUser)
#if os(macOS)
let macOSOnlyProducts: [Product] = [
    .singleTargetLibrary("Logging"),
    .singleTargetLibrary("Shared"),
    .singleTargetLibrary("Core"),
    .singleTargetLibrary("Search"),
    .singleTargetLibrary("Resources"),
    .singleTargetLibrary("MCPSupport"),
    .singleTargetLibrary("SearchToolProvider"),
    .executable(name: "cupertino", targets: ["CLI"]),
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
    // ---------- MCP Framework (Consolidated from MCPShared + MCPTransport + MCPServer) ----------
    let mcpTarget = Target.target(
        name: "MCP",
        dependencies: []
    )
    let mcpTestsTarget = Target.testTarget(
        name: "MCPTests",
        dependencies: ["MCP"]
    )

    let mcpTargets = [
        mcpTarget,
        mcpTestsTarget,
    ]

    // ---------- Cupertino (Apple Docs Crawler → MCP Server - macOS only) ----------
    #if os(macOS)
    let loggingTarget = Target.target(
        name: "Logging",
        dependencies: ["Shared"]
    )
    let loggingTestsTarget = Target.testTarget(
        name: "LoggingTests",
        dependencies: ["Logging", "TestSupport"]
    )

    let sharedTarget = Target.target(
        name: "Shared",
        dependencies: ["MCP"]
    )
    let sharedTestsTarget = Target.testTarget(
        name: "SharedTests",
        dependencies: ["Shared", "TestSupport"]
    )

    let resourcesTarget = Target.target(
        name: "Resources",
        resources: [.process("Resources")]
    )

    let coreTarget = Target.target(
        name: "Core",
        dependencies: ["Shared", "Logging", "Resources"]
    )
    let coreTestsTarget = Target.testTarget(
        name: "CoreTests",
        dependencies: ["Core", "Search", "TestSupport"]
    )

    let searchTarget = Target.target(
        name: "Search",
        dependencies: ["Shared", "Logging"]
    )
    let searchTestsTarget = Target.testTarget(
        name: "SearchTests",
        dependencies: ["Search", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        dependencies: ["MCP", "Shared", "Logging"]
    )
    let mcpSupportTestsTarget = Target.testTarget(
        name: "MCPSupportTests",
        dependencies: ["MCPSupport", "TestSupport"]
    )

    let searchToolProviderTarget = Target.target(
        name: "SearchToolProvider",
        dependencies: ["MCP", "Search"]
    )
    let searchToolProviderTestsTarget = Target.testTarget(
        name: "SearchToolProviderTests",
        dependencies: ["SearchToolProvider", "TestSupport"]
    )

    let cliTarget = Target.executableTarget(
        name: "CLI",
        dependencies: [
            "Shared",
            "Core",
            "Search",
            "Logging",
            // MCP dependencies (for mcp serve command)
            "MCP",
            "MCPSupport",
            "SearchToolProvider",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let testSupportTarget = Target.target(
        name: "TestSupport",
        dependencies: []
    )

    // CLI Command Test Targets
    let serveTestsTarget = Target.testTarget(
        name: "ServeTests",
        dependencies: ["CLI", "MCP", "MCPSupport", "Search", "SearchToolProvider", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/ServeTests"
    )

    let doctorTestsTarget = Target.testTarget(
        name: "DoctorTests",
        dependencies: ["CLI", "MCP", "MCPSupport", "Search", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/DoctorTests"
    )

    let fetchTestsTarget = Target.testTarget(
        name: "FetchTests",
        dependencies: ["CLI", "Core", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/FetchTests"
    )

    let saveTestsTarget = Target.testTarget(
        name: "SaveTests",
        dependencies: ["CLI", "Core", "Search", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/SaveTests"
    )

    let cupertinoTargets: [Target] = [
        loggingTarget,
        loggingTestsTarget,
        sharedTarget,
        sharedTestsTarget,
        resourcesTarget,
        coreTarget,
        coreTestsTarget,
        searchTarget,
        searchTestsTarget,
        mcpSupportTarget,
        mcpSupportTestsTarget,
        searchToolProviderTarget,
        searchToolProviderTestsTarget,
        testSupportTarget,
        cliTarget,
        // CLI Command Tests
        serveTestsTarget,
        doctorTestsTarget,
        fetchTestsTarget,
        saveTestsTarget,
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
        .macOS(.v13),
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

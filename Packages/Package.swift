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
    .singleTargetLibrary("SharedConstants"),
    .singleTargetLibrary("SharedUtils"),
    .singleTargetLibrary("MCPSharedTools"),
    .singleTargetLibrary("Core"),
    .singleTargetLibrary("Cleanup"),
    .singleTargetLibrary("Search"),
    .singleTargetLibrary("SampleIndex"),
    .singleTargetLibrary("Services"),
    .singleTargetLibrary("Distribution"),
    .singleTargetLibrary("Diagnostics"),
    .singleTargetLibrary("Indexer"),
    .singleTargetLibrary("Ingest"),
    .singleTargetLibrary("Resources"),
    .singleTargetLibrary("Availability"),
    .singleTargetLibrary("ASTIndexer"),
    .singleTargetLibrary("MCPSupport"),
    .singleTargetLibrary("SearchToolProvider"),
    .singleTargetLibrary("MCPClient"),
    .singleTargetLibrary("RemoteSync"),
    .executable(name: "cupertino", targets: ["CLI"]),
    .executable(name: "cupertino-tui", targets: ["TUI"]),
    .executable(name: "mock-ai-agent", targets: ["MockAIAgent"]),
    .executable(name: "cupertino-rel", targets: ["ReleaseTool"]),
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
    // SwiftSyntax for AST parsing (#81)
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
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

    // ---------- SharedConstants (v1.1 refactor 1.3: extracts Constants.swift + the Shared namespace enum out of Shared) ----------
    let sharedConstantsTarget = Target.target(
        name: "SharedConstants",
        dependencies: []
    )

    // ---------- SharedUtils (v1.1 refactor 1.4: extracts JSONCoding, PathResolver, Formatting, FTSQuery, SchemaVersion) ----------
    let sharedUtilsTarget = Target.target(
        name: "SharedUtils",
        dependencies: ["SharedConstants"]
    )

    let sharedTarget = Target.target(
        name: "Shared",
        dependencies: ["SharedConstants", "SharedUtils"]
    )
    let sharedTestsTarget = Target.testTarget(
        name: "SharedTests",
        dependencies: ["Shared", "TestSupport"]
    )

    // ---------- MCPSharedTools (v1.1 refactor 1.1: extracts ArgumentExtractor + MCP-protocol-output constants from Shared) ----------
    let mcpSharedToolsTarget = Target.target(
        name: "MCPSharedTools",
        dependencies: ["MCP", "Shared"]
    )
    let mcpSharedToolsTestsTarget = Target.testTarget(
        name: "MCPSharedToolsTests",
        dependencies: ["MCPSharedTools", "Shared", "TestSupport"]
    )

    // Resources target (#161): catalogs are now compiled in as Swift string
    // literals under Sources/Resources/Embedded/ rather than shipped as a
    // `Cupertino_Resources.bundle` next to the binary. No resources: [] entry
    // needed — SPM just compiles the Swift files in the target directory.
    let resourcesTarget = Target.target(
        name: "Resources"
    )
    let resourcesTestsTarget = Target.testTarget(
        name: "ResourcesTests",
        dependencies: ["Resources"]
    )

    let coreTarget = Target.target(
        name: "Core",
        dependencies: ["Shared", "Logging", "Resources", "ASTIndexer"]
    )
    let coreTestsTarget = Target.testTarget(
        name: "CoreTests",
        dependencies: ["Core", "Search", "TestSupport"],
        resources: [.copy("Resources/AppleJSON")]
    )

    let cleanupTarget = Target.target(
        name: "Cleanup",
        dependencies: ["Shared", "Logging"]
    )
    let cleanupTestsTarget = Target.testTarget(
        name: "CleanupTests",
        dependencies: ["Cleanup", "TestSupport"]
    )

    let searchTarget = Target.target(
        name: "Search",
        dependencies: ["Shared", "Logging", "Core", "ASTIndexer"]
    )
    let searchTestsTarget = Target.testTarget(
        name: "SearchTests",
        dependencies: ["Search", "TestSupport"]
    )

    let sampleIndexTarget = Target.target(
        name: "SampleIndex",
        dependencies: ["Shared", "Logging", "ASTIndexer"]
    )
    let sampleIndexTestsTarget = Target.testTarget(
        name: "SampleIndexTests",
        dependencies: ["SampleIndex", "Shared", "TestSupport"]
    )

    let servicesTarget = Target.target(
        name: "Services",
        dependencies: ["Shared", "Search", "SampleIndex"],
        exclude: ["README.md"]
    )
    let servicesTestsTarget = Target.testTarget(
        name: "ServicesTests",
        dependencies: ["Services", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        dependencies: ["MCP", "MCPSharedTools", "Shared", "Logging", "Search"]
    )
    let mcpSupportTestsTarget = Target.testTarget(
        name: "MCPSupportTests",
        dependencies: ["MCPSupport", "MCP", "MCPSharedTools", "Shared", "Search", "TestSupport"]
    )

    let searchToolProviderTarget = Target.target(
        name: "SearchToolProvider",
        dependencies: ["MCP", "MCPSharedTools", "Search", "SampleIndex", "Services", "Shared"]
    )
    let searchToolProviderTestsTarget = Target.testTarget(
        name: "SearchToolProviderTests",
        dependencies: ["SearchToolProvider", "MCPSharedTools", "TestSupport"]
    )

    let mcpClientTarget = Target.target(
        name: "MCPClient",
        dependencies: ["MCP"]
    )
    let mcpClientTestsTarget = Target.testTarget(
        name: "MCPClientTests",
        dependencies: ["MCPClient", "TestSupport"]
    )

    let remoteSyncTarget = Target.target(
        name: "RemoteSync",
        dependencies: ["Shared"]
    )
    let remoteSyncTestsTarget = Target.testTarget(
        name: "RemoteSyncTests",
        dependencies: ["RemoteSync", "TestSupport"]
    )

    let availabilityTarget = Target.target(
        name: "Availability",
        dependencies: []
    )
    let availabilityTestsTarget = Target.testTarget(
        name: "AvailabilityTests",
        dependencies: ["Availability", "TestSupport"]
    )

    let astIndexerTarget = Target.target(
        name: "ASTIndexer",
        dependencies: [
            "Shared",
            "Logging",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]
    )
    let astIndexerTestsTarget = Target.testTarget(
        name: "ASTIndexerTests",
        dependencies: ["ASTIndexer", "Search", "SampleIndex", "TestSupport"]
    )

    // ---------- Distribution (#246: SetupCommand lift) ----------
    let distributionTarget = Target.target(
        name: "Distribution",
        dependencies: ["Shared", "Logging"]
    )
    let distributionTestsTarget = Target.testTarget(
        name: "DistributionTests",
        dependencies: ["Distribution", "Shared", "TestSupport"]
    )

    // ---------- Diagnostics (#245: DoctorCommand probe lift) ----------
    let diagnosticsTarget = Target.target(
        name: "Diagnostics",
        dependencies: []
    )
    let diagnosticsTestsTarget = Target.testTarget(
        name: "DiagnosticsTests",
        dependencies: ["Diagnostics", "TestSupport"]
    )

    // ---------- Indexer (#244: SaveCommand indexer + preflight lift) ----------
    let indexerTarget = Target.target(
        name: "Indexer",
        dependencies: ["Search", "SampleIndex", "Core", "Shared", "Logging"]
    )
    let indexerTestsTarget = Target.testTarget(
        name: "IndexerTests",
        dependencies: ["Indexer", "Shared", "TestSupport"]
    )

    // ---------- Ingest (#247: FetchCommand session + pipelines lift) ----------
    let ingestTarget = Target.target(
        name: "Ingest",
        dependencies: ["Shared", "Logging"]
    )
    let ingestTestsTarget = Target.testTarget(
        name: "IngestTests",
        dependencies: ["Ingest", "Shared", "TestSupport"]
    )

    let cliTarget = Target.executableTarget(
        name: "CLI",
        dependencies: [
            "Shared",
            "Core",
            "Cleanup",
            "Search",
            "SampleIndex",
            "Services",
            "Distribution",
            "Diagnostics",
            "Indexer",
            "Ingest",
            "Logging",
            "RemoteSync",
            "Availability",
            // MCP dependencies (for mcp serve command)
            "MCP",
            "MCPSupport",
            "SearchToolProvider",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )

    let tuiTarget = Target.executableTarget(
        name: "TUI",
        dependencies: [
            "Shared",
            "Core",
            "Search",
            "Resources",
            "Logging",
        ],
        exclude: ["Views/BOX_DRAWING_RULES.md"]
    )

    let mockAIAgentTarget = Target.executableTarget(
        name: "MockAIAgent",
        dependencies: [
            "MCP",
            "Shared",
            "Logging",
        ]
    )

    let releaseToolTarget = Target.executableTarget(
        name: "ReleaseTool",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "Shared",
        ],
        exclude: ["README.md"]
    )
    let releaseToolTestsTarget = Target.testTarget(
        name: "ReleaseToolTests",
        dependencies: ["ReleaseTool"]
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
        dependencies: ["CLI", "Diagnostics", "MCP", "MCPSupport", "Search", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/DoctorTests"
    )

    let fetchTestsTarget = Target.testTarget(
        name: "FetchTests",
        dependencies: ["CLI", "Core", "Ingest", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/FetchTests"
    )

    let saveTestsTarget = Target.testTarget(
        name: "SaveTests",
        dependencies: ["CLI", "Core", "Indexer", "Search", "Shared", "TestSupport"],
        path: "Tests/CLICommandTests/SaveTests"
    )

    let tuiTestsTarget = Target.testTarget(
        name: "TUITests",
        dependencies: ["TUI", "Core", "Shared", "TestSupport"],
        exclude: [
            "TEST_SUMMARY.md",
            "HOW_TESTS_DETECT_BUGS.md",
            "TEST_COVERAGE_ANALYSIS.md",
        ]
    )
    let cliTestsTarget = Target.testTarget(
        name: "CLITests",
        dependencies: ["CLI"]
    )
    let mockAIAgentTestsTarget = Target.testTarget(
        name: "MockAIAgentTests",
        dependencies: ["MCP", "SampleIndex", "Shared", "TestSupport"]
    )

    let cupertinoTargets: [Target] = [
        loggingTarget,
        loggingTestsTarget,
        sharedConstantsTarget,
        sharedUtilsTarget,
        sharedTarget,
        sharedTestsTarget,
        mcpSharedToolsTarget,
        mcpSharedToolsTestsTarget,
        resourcesTarget,
        resourcesTestsTarget,
        coreTarget,
        coreTestsTarget,
        cleanupTarget,
        cleanupTestsTarget,
        searchTarget,
        searchTestsTarget,
        sampleIndexTarget,
        sampleIndexTestsTarget,
        servicesTarget,
        servicesTestsTarget,
        distributionTarget,
        distributionTestsTarget,
        diagnosticsTarget,
        diagnosticsTestsTarget,
        indexerTarget,
        indexerTestsTarget,
        ingestTarget,
        ingestTestsTarget,
        mcpSupportTarget,
        mcpSupportTestsTarget,
        searchToolProviderTarget,
        searchToolProviderTestsTarget,
        mcpClientTarget,
        mcpClientTestsTarget,
        remoteSyncTarget,
        remoteSyncTestsTarget,
        availabilityTarget,
        availabilityTestsTarget,
        astIndexerTarget,
        astIndexerTestsTarget,
        testSupportTarget,
        cliTarget,
        tuiTarget,
        mockAIAgentTarget,
        releaseToolTarget,
        releaseToolTestsTarget,
        // CLI Command Tests
        serveTestsTarget,
        doctorTestsTarget,
        fetchTestsTarget,
        saveTestsTarget,
        // CLI Tests
        cliTestsTarget,
        // MockAIAgent Tests
        mockAIAgentTestsTarget,
        // TUI Tests
        tuiTestsTarget,
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

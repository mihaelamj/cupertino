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
    .singleTargetLibrary("SharedCore"),
    .singleTargetLibrary("SharedConstants"),
    .singleTargetLibrary("SharedUtils"),
    .singleTargetLibrary("SharedModels"),
    .singleTargetLibrary("SharedConfiguration"),
    .singleTargetLibrary("MCPSharedTools"),
    .singleTargetLibrary("CoreProtocols"),
    .singleTargetLibrary("CoreHTMLParser"),
    .singleTargetLibrary("CoreJSONParser"),
    .singleTargetLibrary("CorePackageIndexing"),
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
        dependencies: [],
        path: "Sources/MCP/Core"
    )
    let mcpTestsTarget = Target.testTarget(
        name: "MCPTests",
        dependencies: ["MCP"],
        path: "Tests/MCP/CoreTests"
    )

    let mcpTargets = [
        mcpTarget,
        mcpTestsTarget,
    ]

    // ---------- Cupertino (Apple Docs Crawler → MCP Server - macOS only) ----------
    #if os(macOS)
    let loggingTarget = Target.target(
        name: "Logging",
        dependencies: ["SharedCore", "SharedConstants"]
    )
    let loggingTestsTarget = Target.testTarget(
        name: "LoggingTests",
        dependencies: ["Logging", "TestSupport"]
    )

    // ---------- SharedConstants (v1.1 refactor 1.3: extracts Constants.swift + the Shared namespace enum out of Shared) ----------
    let sharedConstantsTarget = Target.target(
        name: "SharedConstants",
        dependencies: [],
        path: "Sources/Shared/Constants"
    )

    // ---------- SharedUtils (v1.1 refactor 1.4: extracts JSONCoding, PathResolver, Formatting, FTSQuery, SchemaVersion) ----------
    let sharedUtilsTarget = Target.target(
        name: "SharedUtils",
        dependencies: ["SharedConstants"],
        path: "Sources/Shared/Utils"
    )

    // ---------- SharedModels (v1.1 refactor 1.5: extracts the Models/ folder from Shared) ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: ["SharedConstants", "SharedUtils"],
        path: "Sources/Shared/Models"
    )

    // ---------- SharedCore (v1.1 refactor 1.6: residue of Shared - ToolError + CupertinoShared marker) ----------
    let sharedCoreTarget = Target.target(
        name: "SharedCore",
        dependencies: [],
        path: "Sources/Shared/Core"
    )
    let sharedCoreTestsTarget = Target.testTarget(
        name: "SharedCoreTests",
        dependencies: ["SharedCore", "SharedConstants", "SharedUtils", "SharedModels", "CoreProtocols", "TestSupport"],
        path: "Tests/Shared/CoreTests"
    )

    // ---------- SharedConfiguration (v1.1 refactor 1.6: Configuration.swift moves out of Shared) ----------
    let sharedConfigurationTarget = Target.target(
        name: "SharedConfiguration",
        dependencies: ["SharedConstants", "SharedUtils"],
        path: "Sources/Shared/Configuration"
    )

    // ---------- MCPSharedTools (v1.1 refactor 1.1: extracts ArgumentExtractor + MCP-protocol-output constants from Shared) ----------
    let mcpSharedToolsTarget = Target.target(
        name: "MCPSharedTools",
        dependencies: ["MCP", "SharedCore", "SharedConstants"],
        path: "Sources/MCP/SharedTools"
    )
    let mcpSharedToolsTestsTarget = Target.testTarget(
        name: "MCPSharedToolsTests",
        dependencies: ["MCPSharedTools", "SharedCore", "SharedConstants", "TestSupport"],
        path: "Tests/MCP/SharedToolsTests"
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

    // ---------- CoreProtocols (v1.2 refactor 2.1: protocols + utilities + the Core namespace enum, lifted out of Core for downstream extraction) ----------
    let coreProtocolsTarget = Target.target(
        name: "CoreProtocols",
        dependencies: ["SharedCore", "SharedConstants", "SharedModels", "Resources"]
    )

    // ---------- CoreHTMLParser (v1.2 refactor 2.2: HTMLToMarkdown + XMLTransformer, the worst single-file god in Core) ----------
    let coreHTMLParserTarget = Target.target(
        name: "CoreHTMLParser",
        dependencies: ["CoreProtocols", "SharedModels", "SharedConstants"],
        path: "Sources/Core/HTMLParser"
    )

    // ---------- CoreJSONParser (v1.2 refactor 2.3: AppleJSONToMarkdown + MarkdownToStructuredPage + RefResolver + JSON engine) ----------
    let coreJSONParserTarget = Target.target(
        name: "CoreJSONParser",
        dependencies: ["CoreProtocols", "SharedCore", "SharedModels", "SharedConstants", "SharedUtils", "Logging"],
        path: "Sources/Core/JSONParser"
    )

    // ---------- CorePackageIndexing (v1.2 refactor 2.4: Resolver + Fetcher + Archive Extractor + Annotator + FileKind + ManifestCache + Store + DocDownloader) ----------
    let corePackageIndexingTarget = Target.target(
        name: "CorePackageIndexing",
        dependencies: ["CoreProtocols", "SharedCore", "SharedModels", "SharedConstants", "SharedUtils", "Logging", "ASTIndexer"],
        path: "Sources/Core/PackageIndexing"
    )

    let coreTarget = Target.target(
        name: "Core",
        dependencies: [
            "CoreProtocols",
            "CoreHTMLParser",
            "CoreJSONParser",
            "CorePackageIndexing",
            "SharedCore",
            "SharedConfiguration",
            "SharedConstants",
            "SharedModels",
            "SharedUtils",
            "Logging",
            "Resources",
            "ASTIndexer",
        ],
        exclude: ["HTMLParser", "JSONParser", "PackageIndexing"]
    )
    let coreTestsTarget = Target.testTarget(
        name: "CoreTests",
        dependencies: [
            "CoreProtocols",
            "CoreHTMLParser",
            "CoreJSONParser",
            "CorePackageIndexing",
            "Core",
            "Search",
            "SharedCore",
            "SharedConstants",
            "SharedModels",
            "TestSupport",
        ],
        resources: [.copy("Resources/AppleJSON")]
    )

    let cleanupTarget = Target.target(
        name: "Cleanup",
        dependencies: ["SharedCore", "SharedConstants", "SharedModels", "Logging"]
    )
    let cleanupTestsTarget = Target.testTarget(
        name: "CleanupTests",
        dependencies: ["Cleanup", "TestSupport"]
    )

    let searchTarget = Target.target(
        name: "Search",
        dependencies: ["SharedCore", "SharedConstants", "SharedModels", "Logging", "CoreProtocols", "CoreJSONParser", "CorePackageIndexing", "Core", "ASTIndexer"]
    )
    let searchTestsTarget = Target.testTarget(
        name: "SearchTests",
        dependencies: ["Search", "SharedCore", "SharedConstants", "SharedModels", "SharedUtils", "TestSupport", "CorePackageIndexing"]
    )

    let sampleIndexTarget = Target.target(
        name: "SampleIndex",
        dependencies: ["SharedCore", "SharedConstants", "SharedUtils", "Logging", "ASTIndexer"]
    )
    let sampleIndexTestsTarget = Target.testTarget(
        name: "SampleIndexTests",
        dependencies: ["SampleIndex", "SharedCore", "SharedConstants", "TestSupport"]
    )

    let servicesTarget = Target.target(
        name: "Services",
        dependencies: ["SharedCore", "SharedConstants", "SharedUtils", "Search", "SampleIndex"],
        exclude: ["README.md"]
    )
    let servicesTestsTarget = Target.testTarget(
        name: "ServicesTests",
        dependencies: ["Services", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        dependencies: ["MCP", "MCPSharedTools", "SharedCore", "SharedConfiguration", "SharedConstants", "SharedModels", "SharedUtils", "Logging", "Search"],
        path: "Sources/MCP/Support"
    )
    let mcpSupportTestsTarget = Target.testTarget(
        name: "MCPSupportTests",
        dependencies: ["MCPSupport", "MCP", "MCPSharedTools", "SharedCore", "SharedConfiguration", "SharedConstants", "SharedModels", "Search", "TestSupport"],
        path: "Tests/MCP/SupportTests"
    )

    let searchToolProviderTarget = Target.target(
        name: "SearchToolProvider",
        dependencies: ["MCP", "MCPSharedTools", "SharedCore", "SharedConstants", "SharedUtils", "Search", "SampleIndex", "Services"]
    )
    let searchToolProviderTestsTarget = Target.testTarget(
        name: "SearchToolProviderTests",
        dependencies: ["SearchToolProvider", "MCPSharedTools", "TestSupport"]
    )

    let mcpClientTarget = Target.target(
        name: "MCPClient",
        dependencies: ["MCP"],
        path: "Sources/MCP/Client"
    )
    let mcpClientTestsTarget = Target.testTarget(
        name: "MCPClientTests",
        dependencies: ["MCPClient", "TestSupport"],
        path: "Tests/MCP/ClientTests"
    )

    let remoteSyncTarget = Target.target(
        name: "RemoteSync",
        dependencies: ["SharedCore", "SharedConstants", "SharedUtils"]
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
            "SharedCore",
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
        dependencies: ["SharedCore", "SharedConstants", "Logging"]
    )
    let distributionTestsTarget = Target.testTarget(
        name: "DistributionTests",
        dependencies: ["Distribution", "SharedCore", "TestSupport"]
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
        dependencies: ["SharedCore", "SharedConstants", "SharedUtils", "Search", "SampleIndex", "CoreProtocols", "Core", "Logging"]
    )
    let indexerTestsTarget = Target.testTarget(
        name: "IndexerTests",
        dependencies: ["Indexer", "SharedCore", "TestSupport"]
    )

    // ---------- Ingest (#247: FetchCommand session + pipelines lift) ----------
    let ingestTarget = Target.target(
        name: "Ingest",
        dependencies: ["SharedCore", "SharedConstants", "SharedModels", "SharedUtils", "Logging"]
    )
    let ingestTestsTarget = Target.testTarget(
        name: "IngestTests",
        dependencies: ["Ingest", "SharedCore", "TestSupport"]
    )

    let cliTarget = Target.executableTarget(
        name: "CLI",
        dependencies: [
            "SharedCore",
            "SharedConfiguration",
            "SharedConstants",
            "SharedModels",
            "SharedUtils",
            "CoreProtocols", "CoreJSONParser", "CorePackageIndexing", "Core",
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
            "SharedCore",
            "SharedConstants",
            "SharedUtils",
            "CoreProtocols", "CorePackageIndexing", "Core",
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
            "SharedCore",
            "SharedConstants",
            "Logging",
        ]
    )

    let releaseToolTarget = Target.executableTarget(
        name: "ReleaseTool",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "SharedCore",
            "SharedConstants",
            "SharedUtils",
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
        dependencies: ["CLI", "MCP", "MCPSupport", "Search", "SearchToolProvider", "SharedCore", "TestSupport"],
        path: "Tests/CLICommandTests/ServeTests"
    )

    let doctorTestsTarget = Target.testTarget(
        name: "DoctorTests",
        dependencies: ["CLI", "Diagnostics", "MCP", "MCPSupport", "Search", "SharedCore", "TestSupport"],
        path: "Tests/CLICommandTests/DoctorTests"
    )

    let fetchTestsTarget = Target.testTarget(
        name: "FetchTests",
        dependencies: ["CLI", "CoreProtocols", "CorePackageIndexing", "Core", "Ingest", "SharedCore", "TestSupport"],
        path: "Tests/CLICommandTests/FetchTests"
    )

    let saveTestsTarget = Target.testTarget(
        name: "SaveTests",
        dependencies: ["CLI", "CoreProtocols", "Core", "Indexer", "Search", "SharedCore", "TestSupport"],
        path: "Tests/CLICommandTests/SaveTests"
    )

    let tuiTestsTarget = Target.testTarget(
        name: "TUITests",
        dependencies: ["TUI", "CoreProtocols", "Core", "SharedCore", "TestSupport"],
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
        dependencies: ["MCP", "SampleIndex", "SharedCore", "TestSupport"]
    )

    let cupertinoTargets: [Target] = [
        loggingTarget,
        loggingTestsTarget,
        sharedConstantsTarget,
        sharedUtilsTarget,
        sharedModelsTarget,
        sharedCoreTarget,
        sharedCoreTestsTarget,
        sharedConfigurationTarget,
        mcpSharedToolsTarget,
        mcpSharedToolsTestsTarget,
        coreProtocolsTarget,
        coreHTMLParserTarget,
        coreJSONParserTarget,
        corePackageIndexingTarget,
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

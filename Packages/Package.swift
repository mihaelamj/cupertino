// swift-tools-version: 6.2

import PackageDescription

// -------------------------------------------------------------

// MARK: Products

// -------------------------------------------------------------

let baseProducts: [Product] = [
    // MCP Framework (cross-platform, consolidated from MCPShared + MCPTransport + MCPServer)
    .singleTargetLibrary("MCPCore"),
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
    // path is Sources/MCP/ (not Sources/MCP/Core) so the `MCP` namespace anchor
    // file lives at the folder root next to the sibling sub-target folders
    // (Client / SharedTools / Support). MCPCore picks up MCP.swift + the
    // Core/ subtree (Protocol, Server, Transport); the three sibling folders
    // are excluded because they are their own SPM targets.
    let mcpCoreTarget = Target.target(
        name: "MCPCore",
        dependencies: [],
        path: "Sources/MCP",
        exclude: ["Client", "SharedTools", "Support"]
    )
    let mcpCoreTestsTarget = Target.testTarget(
        name: "MCPTests",
        dependencies: ["MCPCore"],
        path: "Tests/MCP/CoreTests"
    )

    let mcpTargets = [
        mcpCoreTarget,
        mcpCoreTestsTarget,
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
    // path is Sources/Shared/ (not Sources/Shared/Constants) so the `Shared`
    // and `Sample` namespace anchor files live at the Shared/ folder root next
    // to the sibling sub-target folders (Configuration / Core / Models / Utils).
    // SharedConstants picks up Shared.swift + Sample.swift + the Constants/
    // subtree; the four sibling folders are excluded because they are their
    // own SPM targets.
    let sharedConstantsTarget = Target.target(
        name: "SharedConstants",
        dependencies: [],
        path: "Sources/Shared",
        exclude: ["Configuration", "Core", "Models", "Utils"]
    )
    let sharedConstantsTestsTarget = Target.testTarget(
        name: "SharedConstantsTests",
        dependencies: ["SharedConstants"]
    )

    // ---------- SharedUtils (v1.1 refactor 1.4: extracts Shared.Utils.JSONCoding, Shared.Utils.PathResolver, Formatting, FTSQuery, SchemaVersion) ----------
    let sharedUtilsTarget = Target.target(
        name: "SharedUtils",
        dependencies: ["SharedConstants"],
        path: "Sources/Shared/Utils"
    )
    let sharedUtilsTestsTarget = Target.testTarget(
        name: "SharedUtilsTests",
        dependencies: ["SharedUtils", "SharedConstants"]
    )

    // ---------- SharedModels (v1.1 refactor 1.5: extracts the Models/ folder from Shared) ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: ["SharedConstants", "SharedUtils"],
        path: "Sources/Shared/Models"
    )
    let sharedModelsTestsTarget = Target.testTarget(
        name: "SharedModelsTests",
        dependencies: ["SharedModels", "SharedConstants", "SharedUtils"]
    )

    // ---------- SharedCore (v1.1 refactor 1.6: residue of Shared - ToolError + CupertinoShared marker) ----------
    let sharedCoreTarget = Target.target(
        name: "SharedCore",
        dependencies: ["SharedConstants"],
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
    let sharedConfigurationTestsTarget = Target.testTarget(
        name: "SharedConfigurationTests",
        dependencies: ["SharedConfiguration", "SharedConstants", "SharedUtils"]
    )

    // ---------- MCPSharedTools (v1.1 refactor 1.1: extracts MCP.SharedTools.ArgumentExtractor + MCP-protocol-output constants from Shared) ----------
    let mcpSharedToolsTarget = Target.target(
        name: "MCPSharedTools",
        dependencies: ["MCPCore", "SharedCore", "SharedConstants"],
        path: "Sources/MCP/SharedTools"
    )
    let mcpSharedToolsTestsTarget = Target.testTarget(
        name: "MCPSharedToolsTests",
        dependencies: ["MCPSharedTools", "MCPCore", "SharedCore", "SharedConstants", "TestSupport"],
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
    let coreProtocolsTestsTarget = Target.testTarget(
        name: "CoreProtocolsTests",
        dependencies: ["CoreProtocols", "SharedCore", "SharedConstants", "SharedModels", "Resources"]
    )

    // CoreHTMLParser merged back into Core (HTMLToMarkdown -> Core.Parser.HTML,
    // XMLTransformer -> Core.Parser.XML). The Sources/Core/HTMLParser/ folder
    // stays; Core picks up those sources directly. See Core target below.

    // ---------- CoreJSONParser (v1.2 refactor 2.3: AppleJSONToMarkdown + MarkdownToStructuredPage + RefResolver + JSON engine) ----------
    let coreJSONParserTarget = Target.target(
        name: "CoreJSONParser",
        dependencies: ["CoreProtocols", "SharedCore", "SharedModels", "SharedConstants", "SharedUtils", "Logging"],
        path: "Sources/Core/JSONParser"
    )
    let coreJSONParserTestsTarget = Target.testTarget(
        name: "CoreJSONParserTests",
        dependencies: ["CoreJSONParser", "CoreProtocols", "TestSupport"]
    )

    // ---------- CorePackageIndexingModels (#400: value types + namespace anchor lifted out
    // of CorePackageIndexing so consumers (Search, TUI, CLI) can hold ResolvedPackage /
    // ExtractedFile / PackageExtractionResult / availabilityFilename without depending on
    // the full indexer + extractor + annotator + manifest-cache surface). Mirrors the
    // SearchModels / SampleIndexModels / CoreSampleCode split pattern. Hosts:
    // - `Core.PackageIndexing` namespace anchor
    // - `Core.PackageIndexing.ResolvedPackage` (value struct)
    // - `Core.PackageIndexing.PackageFileKind` enum + `ExtractedFile` struct + classifier
    // - `Core.PackageIndexing.PackageExtractionResult` (lifted from being nested inside
    //   PackageArchiveExtractor.Result)
    // - `Core.PackageIndexing.availabilityFilename` (lifted from
    //   PackageAvailabilityAnnotator.outputFilename)
    let corePackageIndexingModelsTarget = Target.target(
        name: "CorePackageIndexingModels",
        dependencies: ["ASTIndexer", "CoreProtocols", "SharedConstants", "SharedModels"]
    )
    let corePackageIndexingModelsTestsTarget = Target.testTarget(
        name: "CorePackageIndexingModelsTests",
        dependencies: ["CorePackageIndexingModels", "ASTIndexer", "CoreProtocols", "SharedConstants", "SharedModels", "TestSupport"]
    )

    // ---------- CorePackageIndexing (v1.2 refactor 2.4: Resolver + Fetcher + Archive Extractor + Annotator + ManifestCache + Store + DocDownloader) ----------
    let corePackageIndexingTarget = Target.target(
        name: "CorePackageIndexing",
        dependencies: ["CorePackageIndexingModels", "CoreProtocols", "SharedCore", "SharedModels", "SharedConstants", "SharedUtils", "Logging", "ASTIndexer", "Resources"],
        path: "Sources/Core/PackageIndexing"
    )
    let corePackageIndexingTestsTarget = Target.testTarget(
        name: "CorePackageIndexingTests",
        dependencies: ["CorePackageIndexing", "CorePackageIndexingModels", "CoreProtocols", "TestSupport"]
    )

    // ---------- CoreSampleCode (#305: Apple sample-code subsystem extracted out of Core) ----------
    // Hosts Sample.Core.{Catalog, Downloader, Downloader.Error, GitHubFetcher,
    // Progress, Statistics}. Pure foundation-layer deps. Core stays for the
    // documentation-side concerns; consumers that touch sample code
    // (`SampleIndex`, `Search/Strategies/Search.Strategies.SampleCode`,
    // `Indexer.SamplesService`, `CLI.Command.Fetch`) take an explicit
    // `import CoreSampleCode` instead of getting it transitively via Core.
    let coreSampleCodeTarget = Target.target(
        name: "CoreSampleCode",
        dependencies: [
            "SharedConstants",
            "SharedUtils",
            "SharedCore",
            "Logging",
        ]
    )
    let coreSampleCodeTestsTarget = Target.testTarget(
        name: "CoreSampleCodeTests",
        dependencies: ["CoreSampleCode", "SharedConstants", "TestSupport"]
    )

    let coreTarget = Target.target(
        name: "Core",
        dependencies: [
            "CoreProtocols",
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
        exclude: ["JSONParser", "PackageIndexing"]
    )
    let coreTestsTarget = Target.testTarget(
        name: "CoreTests",
        dependencies: [
            "CoreProtocols",
            "CoreJSONParser",
            "CorePackageIndexing",
            "CorePackageIndexingModels",
            "Core",
            "SharedCore",
            "SharedConstants",
            "SharedModels",
            "TestSupport",
        ],
        resources: [.copy("Resources/AppleJSON")]
    )

    // ---------- Crawler (v1.2 refactor 2.5: extracted from Core — web crawlers + WebKit fetcher) ----------
    let crawlerModelsTarget = Target.target(
        name: "CrawlerModels",
        dependencies: ["SharedConstants", "SharedModels"]
    )
    let crawlerTarget = Target.target(
        name: "Crawler",
        dependencies: [
            "CrawlerModels",
            "CoreProtocols",
            "SharedCore",
            "SharedConfiguration",
            "SharedConstants",
            "SharedModels",
            "SharedUtils",
            "Logging",
            "Resources",
        ]
    )
    let crawlerTestsTarget = Target.testTarget(
        name: "CrawlerTests",
        dependencies: ["Crawler", "CrawlerModels", "Core", "CoreJSONParser", "CorePackageIndexing", "SharedCore", "SharedConstants", "SharedModels", "TestSupport"]
    )

    let cleanupTarget = Target.target(
        name: "Cleanup",
        dependencies: ["SharedCore", "SharedConstants", "SharedModels", "Logging"]
    )
    let cleanupTestsTarget = Target.testTarget(
        name: "CleanupTests",
        dependencies: ["Cleanup", "TestSupport"]
    )

    // ---------- SearchModels (#402a: value types lifted out of Search so result-consuming
    // layers — Services formatters, MCPSupport, CLI rendering — render hits without
    // taking a behavioural dep on Search). Hosts the `Search` namespace anchor +
    // Search.Result, Search.MatchedSymbol, Search.PlatformAvailability, Search.DocumentFormat.
    let searchModelsTarget = Target.target(
        name: "SearchModels",
        dependencies: ["SharedCore", "SharedConstants", "SharedModels"]
    )
    let searchModelsTestsTarget = Target.testTarget(
        name: "SearchModelsTests",
        dependencies: ["SearchModels", "SharedConstants", "TestSupport"]
    )

    // ---------- SampleIndexModels (#408 partial: value types + Reader protocol lifted out of
    // SampleIndex so SearchToolProvider can hold an `any Sample.Index.Reader` without
    // pulling in the full indexer + schema + writer surface). Hosts Sample.Index.Project,
    // Sample.Index.File, Sample.Index.FileSearchResult, and Sample.Index.Reader. Mirrors
    // the SearchModels split.
    let sampleIndexModelsTarget = Target.target(
        name: "SampleIndexModels",
        dependencies: ["SharedConstants"]
    )
    let sampleIndexModelsTestsTarget = Target.testTarget(
        name: "SampleIndexModelsTests",
        dependencies: ["SampleIndexModels", "SharedConstants", "TestSupport"]
    )

    let searchTarget = Target.target(
        name: "Search",
        // Sources/Search/Strategies/ contains SourceIndexingStrategy, StrategyHelpers,
        // and the 7 concrete strategy types (refactor-plan §3.6 / ADR-CUPERTINO-0002).
        // They remain in the Search target for now because a clean `SearchStrategies`
        // package extraction requires SearchIndexCore (§3.5) to be done first —
        // strategies need Search.Index which is still in this target.  Once §3.5 lands,
        // the Strategies/ folder moves to Sources/SearchStrategies/ and gets its own
        // SPM target with deps: [SearchIndexCore, CoreJSONParser, CorePackageIndexing,
        // Core, SharedModels, SharedConstants, Resources, Logging].
        dependencies: ["SearchModels", "SharedCore", "SharedConstants", "SharedModels", "Logging", "CoreProtocols", "CorePackageIndexingModels", "ASTIndexer"]
    )
    let searchTestsTarget = Target.testTarget(
        name: "SearchTests",
        dependencies: [
            "Search",
            "SearchModels",
            "SharedCore",
            "SharedConstants",
            "SharedModels",
            "SharedUtils",
            "TestSupport",
            "CorePackageIndexingModels",
            "ASTIndexer",
            "SampleIndex",
            "SampleIndexModels",
            "Diagnostics",
        ]
    )

    let sampleIndexTarget = Target.target(
        name: "SampleIndex",
        dependencies: ["SampleIndexModels", "SharedCore", "SharedConstants", "SharedUtils", "Logging", "ASTIndexer"]
    )
    let sampleIndexTestsTarget = Target.testTarget(
        name: "SampleIndexTests",
        dependencies: ["SampleIndex", "SampleIndexModels", "SharedCore", "SharedConstants", "TestSupport"]
    )

    // ---------- ServicesModels (#408: value types + namespace anchor lifted out of Services
    // so MCP and CLI surfaces can hold Services.SearchQuery / SearchFilters / HIGQuery /
    // Formatter.Config without importing the full Services behavioural target). Mirrors the
    // SearchModels / SampleIndexModels / CorePackageIndexingModels split pattern.
    let servicesModelsTarget = Target.target(
        name: "ServicesModels",
        dependencies: ["SearchModels", "SharedCore", "SharedConstants", "SharedModels"]
    )
    let servicesModelsTestsTarget = Target.testTarget(
        name: "ServicesModelsTests",
        dependencies: ["ServicesModels", "SearchModels", "SharedConstants", "TestSupport"]
    )

    let servicesTarget = Target.target(
        name: "Services",
        dependencies: ["ServicesModels", "SharedCore", "SharedConstants", "SharedUtils", "Search", "SampleIndex", "SampleIndexModels"],
        exclude: ["README.md"]
    )
    let servicesTestsTarget = Target.testTarget(
        name: "ServicesTests",
        dependencies: ["Services", "ServicesModels", "SearchModels", "SampleIndex", "SampleIndexModels", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        dependencies: ["MCPCore", "MCPSharedTools", "SharedCore", "SharedConfiguration", "SharedConstants", "SharedModels", "SharedUtils", "Logging"],
        path: "Sources/MCP/Support"
    )
    let mcpSupportTestsTarget = Target.testTarget(
        name: "MCPSupportTests",
        dependencies: ["MCPSupport", "MCPCore", "MCPSharedTools", "SharedCore", "SharedConfiguration", "SharedConstants", "SharedModels", "TestSupport"],
        path: "Tests/MCP/SupportTests"
    )

    let searchToolProviderTarget = Target.target(
        name: "SearchToolProvider",
        dependencies: ["MCPCore", "MCPSharedTools", "SearchModels", "SampleIndexModels", "ServicesModels", "SharedCore", "SharedConstants", "SharedUtils"]
    )
    let searchToolProviderTestsTarget = Target.testTarget(
        name: "SearchToolProviderTests",
        dependencies: ["SearchToolProvider", "SearchModels", "SampleIndex", "SampleIndexModels", "Services", "ServicesModels", "MCPSharedTools", "TestSupport"]
    )

    let mcpClientTarget = Target.target(
        name: "MCPClient",
        dependencies: ["MCPCore"],
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
        dependencies: ["SharedConstants", "SharedUtils"]
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
        dependencies: ["ASTIndexer", "TestSupport"]
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
        dependencies: ["SearchModels", "SampleIndexModels", "SharedCore", "SharedConstants", "SharedUtils", "Logging"]
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
            "CoreProtocols", "CoreJSONParser", "CorePackageIndexing", "CorePackageIndexingModels", "Core", "CoreSampleCode",
            "Crawler",
            "Cleanup",
            "Search",
            "SampleIndex",
            "Services",
            "ServicesModels",
            "Distribution",
            "Diagnostics",
            "Indexer",
            "Ingest",
            "Logging",
            "RemoteSync",
            "Availability",
            // MCP dependencies (for mcp serve command)
            "MCPCore",
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
            "MCPCore",
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
        dependencies: [
            "CLI",
            "Crawler",
            "MCPCore",
            "MCPSupport",
            "Search",
            "SearchModels",
            "SearchToolProvider",
            "SampleIndex",
            "SampleIndexModels",
            "Services",
            "ServicesModels",
            "SharedCore",
            "SharedConstants",
            "TestSupport",
        ],
        path: "Tests/CLICommandTests/ServeTests"
    )

    let doctorTestsTarget = Target.testTarget(
        name: "DoctorTests",
        dependencies: ["CLI", "Diagnostics", "MCPCore", "MCPSupport", "Search", "SearchModels", "SharedCore", "TestSupport"],
        path: "Tests/CLICommandTests/DoctorTests"
    )

    let fetchTestsTarget = Target.testTarget(
        name: "FetchTests",
        dependencies: ["CLI", "CoreProtocols", "CorePackageIndexing", "CoreJSONParser", "Core", "Crawler", "CrawlerModels", "Ingest", "SharedCore", "TestSupport"],
        path: "Tests/CLICommandTests/FetchTests"
    )

    let saveTestsTarget = Target.testTarget(
        name: "SaveTests",
        dependencies: [
            "CLI",
            "CoreProtocols",
            "Core",
            "CoreJSONParser",
            "CorePackageIndexing",
            "Crawler",
            "CrawlerModels",
            "Indexer",
            "Search",
            "SearchModels",
            "SharedCore",
            "TestSupport",
        ],
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
        dependencies: ["MCPCore", "SampleIndex", "SharedCore", "TestSupport"]
    )

    let cupertinoTargets: [Target] = [
        loggingTarget,
        loggingTestsTarget,
        sharedConstantsTarget,
        sharedConstantsTestsTarget,
        sharedUtilsTarget,
        sharedUtilsTestsTarget,
        sharedModelsTarget,
        sharedModelsTestsTarget,
        sharedCoreTarget,
        sharedCoreTestsTarget,
        sharedConfigurationTarget,
        sharedConfigurationTestsTarget,
        mcpSharedToolsTarget,
        mcpSharedToolsTestsTarget,
        coreProtocolsTarget,
        coreProtocolsTestsTarget,
        coreJSONParserTarget,
        coreJSONParserTestsTarget,
        corePackageIndexingModelsTarget,
        corePackageIndexingModelsTestsTarget,
        corePackageIndexingTarget,
        corePackageIndexingTestsTarget,
        resourcesTarget,
        resourcesTestsTarget,
        coreSampleCodeTarget,
        coreSampleCodeTestsTarget,
        coreTarget,
        coreTestsTarget,
        crawlerModelsTarget,
        crawlerTarget,
        crawlerTestsTarget,
        cleanupTarget,
        cleanupTestsTarget,
        searchModelsTarget,
        searchModelsTestsTarget,
        sampleIndexModelsTarget,
        sampleIndexModelsTestsTarget,
        searchTarget,
        searchTestsTarget,
        sampleIndexTarget,
        sampleIndexTestsTarget,
        servicesModelsTarget,
        servicesModelsTestsTarget,
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

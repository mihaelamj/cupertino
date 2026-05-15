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
    .singleTargetLibrary("LoggingModels"),
    .singleTargetLibrary("SharedConstants"),
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
    .singleTargetLibrary("DistributionModels"),
    .singleTargetLibrary("Diagnostics"),
    .singleTargetLibrary("Indexer"),
    .singleTargetLibrary("IndexerModels"),
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
    // LoggingModels: GoF Strategy (1994 p. 315) protocol target paired with
    // the concrete `Logging` target. Holds the `Logging` namespace anchor +
    // `Logging.Recording` protocol + `Logging.Level` / `Logging.Category` /
    // `Logging.NoopRecording`. Consumers take `any Logging.Recording` and
    // never reach for a shared static. Foundation-only deps so any target
    // can hold the protocol-typed seam without dragging the OSLog + file
    // + console concrete in.
    let loggingModelsTarget = Target.target(
        name: "LoggingModels",
        dependencies: []
    )
    let loggingModelsTestsTarget = Target.testTarget(
        name: "LoggingModelsTests",
        dependencies: ["LoggingModels"]
    )
    let loggingTarget = Target.target(
        name: "Logging",
        dependencies: ["LoggingModels", "SharedConstants"]
    )
    let loggingTestsTarget = Target.testTarget(
        name: "LoggingTests",
        dependencies: ["Logging", "LoggingModels", "TestSupport"]
    )

    // ---------- SharedConstants (v1.1 refactor 1.3: extracts Constants.swift + the Shared namespace enum out of Shared) ----------
    // path is Sources/Shared/ (not Sources/Shared/Constants) so the `Shared`
    // and `Sample` namespace anchor files live at the Shared/ folder root next
    // to the sibling sub-target folders (Configuration / Core / Models / Utils).
    // SharedConstants picks up everything under Sources/Shared/. After #536
    // phase 1d, no sub-folder is excluded — every Shared* sibling target
    // has been absorbed.
    let sharedConstantsTarget = Target.target(
        name: "SharedConstants",
        dependencies: [],
        path: "Sources/Shared"
        // Phase 1a of #536: SharedCore (`Shared.Core.ToolError`, the
        // `Shared.Core` namespace anchor, `CupertinoShared.swift` marker)
        // absorbed in.
        // Phase 1b of #536: SharedUtils (`Shared.Utils.JSONCoding`,
        // `Shared.Utils.PathResolver`, `Shared.Utils.Formatting`,
        // `Shared.Utils.FTSQuery`, `Shared.Utils.SQL`,
        // `Shared.Utils.SchemaVersion`, `URLExtensions`) absorbed in.
        // Phase 1c of #536: SharedModels (`Shared.Models.CrawlMetadata`,
        // `Shared.Models.PackageReference`, `Shared.Models.URLUtilities`,
        // `Shared.Models.HashUtilities`, `Shared.Models.StructuredDocumentationPage`,
        // `Shared.Models.CleanupProgress`) absorbed in.
        // Phase 1d of #536: SharedConfiguration (`Shared.Configuration` +
        // `Shared.Configuration.Crawler` / `ChangeDetection` /
        // `Output` / `Output.Format` / `DiscoveryMode`) absorbed in.
        // Phase 1 complete; the Shared layer is now a single foundation-only
        // SharedConstants target.
    )
    let sharedConstantsTestsTarget = Target.testTarget(
        name: "SharedConstantsTests",
        dependencies: ["SharedConstants"]
    )

    // SharedUtils was absorbed into SharedConstants in #536 phase 1b; its
    // `Shared.Utils.JSONCoding` / `PathResolver` / `Formatting` / `FTSQuery`
    // / `SQL` / `SchemaVersion` + `URLExtensions` (`URL(knownGood:)`,
    // `URL.expandingTildeInPath`) now live inside SharedConstants. The
    // SharedUtilsTests target stays — re-pointed at SharedConstants only.
    let sharedUtilsTestsTarget = Target.testTarget(
        name: "SharedUtilsTests",
        dependencies: ["SharedConstants"]
    )

    // SharedModels was absorbed into SharedConstants in #536 phase 1c. Its
    // value types (`Shared.Models.CrawlMetadata`, `PackageReference`,
    // `URLUtilities`, `HashUtilities`, `StructuredDocumentationPage`,
    // `CleanupProgress`) now live inside SharedConstants. SharedModelsTests
    // stays — re-pointed at SharedConstants only.
    let sharedModelsTestsTarget = Target.testTarget(
        name: "SharedModelsTests",
        dependencies: ["SharedConstants"]
    )

    // SharedCore was absorbed into SharedConstants in #536 phase 1a; its
    // `Shared.Core.ToolError` + `Shared.Core` namespace anchor now live inside
    // SharedConstants. The SharedCoreTests target stays — re-pointed at
    // SharedConstants — until phase 1d closes out the broader Shared layer.
    let sharedCoreTestsTarget = Target.testTarget(
        name: "SharedCoreTests",
        dependencies: ["SharedConstants", "CoreProtocols", "TestSupport"],
        path: "Tests/Shared/CoreTests"
    )

    // SharedConfiguration was absorbed into SharedConstants in #536 phase 1d.
    // The `Shared.Configuration` namespace + its `Crawler` / `ChangeDetection`
    // / `Output` / `DiscoveryMode` value types now live inside SharedConstants.
    // SharedConfigurationTests stays — re-pointed at SharedConstants only.
    let sharedConfigurationTestsTarget = Target.testTarget(
        name: "SharedConfigurationTests",
        dependencies: ["SharedConstants"]
    )

    // ---------- MCPSharedTools (v1.1 refactor 1.1: extracts MCP.SharedTools.ArgumentExtractor + MCP-protocol-output constants from Shared) ----------
    let mcpSharedToolsTarget = Target.target(
        name: "MCPSharedTools",
        dependencies: ["MCPCore", "SharedConstants"],
        path: "Sources/MCP/SharedTools"
    )
    let mcpSharedToolsTestsTarget = Target.testTarget(
        name: "MCPSharedToolsTests",
        dependencies: ["MCPSharedTools", "MCPCore", "SharedConstants", "TestSupport"],
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
        dependencies: ["SharedConstants", "Resources"]
    )
    let coreProtocolsTestsTarget = Target.testTarget(
        name: "CoreProtocolsTests",
        dependencies: ["CoreProtocols", "SharedConstants", "Resources"]
    )

    // CoreHTMLParser merged back into Core (HTMLToMarkdown -> Core.Parser.HTML,
    // XMLTransformer -> Core.Parser.XML). The Sources/Core/HTMLParser/ folder
    // stays; Core picks up those sources directly. See Core target below.

    // ---------- CoreJSONParser (v1.2 refactor 2.3: AppleJSONToMarkdown + MarkdownToStructuredPage + RefResolver + JSON engine) ----------
    let coreJSONParserTarget = Target.target(
        name: "CoreJSONParser",
        dependencies: ["CoreProtocols", "SharedConstants"],
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
        dependencies: ["ASTIndexer", "CoreProtocols", "SharedConstants"]
    )
    let corePackageIndexingModelsTestsTarget = Target.testTarget(
        name: "CorePackageIndexingModelsTests",
        dependencies: ["CorePackageIndexingModels", "ASTIndexer", "CoreProtocols", "SharedConstants", "TestSupport"]
    )

    // ---------- CorePackageIndexing (v1.2 refactor 2.4: Resolver + Fetcher + Archive Extractor + Annotator + ManifestCache + Store + DocDownloader) ----------
    let corePackageIndexingTarget = Target.target(
        name: "CorePackageIndexing",
        dependencies: ["CorePackageIndexingModels", "CoreProtocols", "SharedConstants", "LoggingModels", "ASTIndexer", "Resources"],
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
            "LoggingModels",
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
            "SharedConstants",
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
            "SharedConstants",
            "TestSupport",
        ],
        resources: [.copy("Resources/AppleJSON")]
    )

    // ---------- Crawler (v1.2 refactor 2.5: extracted from Core — web crawlers + WebKit fetcher) ----------
    let crawlerModelsTarget = Target.target(
        name: "CrawlerModels",
        dependencies: ["SharedConstants"]
    )
    let crawlerModelsTestsTarget = Target.testTarget(
        name: "CrawlerModelsTests",
        dependencies: ["CrawlerModels", "SharedConstants"]
    )
    let crawlerTarget = Target.target(
        name: "Crawler",
        dependencies: [
            "CrawlerModels",
            "CoreProtocols",
            "SharedConstants",
            "LoggingModels",
            "Resources",
        ]
    )
    let crawlerTestsTarget = Target.testTarget(
        name: "CrawlerTests",
        dependencies: ["Crawler", "CrawlerModels", "Core", "CoreJSONParser", "CorePackageIndexing", "SharedConstants", "TestSupport"]
    )

    let cleanupTarget = Target.target(
        name: "Cleanup",
        dependencies: ["SharedConstants", "LoggingModels"]
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
        dependencies: ["SharedConstants"]
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
        dependencies: ["SearchModels", "SharedConstants", "LoggingModels", "CoreProtocols", "CorePackageIndexingModels", "ASTIndexer"]
    )
    let searchTestsTarget = Target.testTarget(
        name: "SearchTests",
        dependencies: [
            "Search",
            "SearchModels",
            "SharedConstants",
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
        dependencies: ["SampleIndexModels", "SharedConstants", "LoggingModels", "ASTIndexer"]
    )
    let sampleIndexTestsTarget = Target.testTarget(
        name: "SampleIndexTests",
        dependencies: ["SampleIndex", "SampleIndexModels", "SharedConstants", "TestSupport"]
    )

    // ---------- ServicesModels (#408: value types + namespace anchor lifted out of Services
    // so MCP and CLI surfaces can hold Services.SearchQuery / SearchFilters / HIGQuery /
    // Formatter.Config without importing the full Services behavioural target). Mirrors the
    // SearchModels / SampleIndexModels / CorePackageIndexingModels split pattern.
    let servicesModelsTarget = Target.target(
        name: "ServicesModels",
        dependencies: ["SearchModels", "SampleIndexModels", "SharedConstants"]
    )
    let servicesModelsTestsTarget = Target.testTarget(
        name: "ServicesModelsTests",
        dependencies: ["ServicesModels", "SearchModels", "SampleIndexModels", "SharedConstants"]
    )

    let servicesTarget = Target.target(
        name: "Services",
        dependencies: ["ServicesModels", "SearchModels", "SampleIndexModels", "SharedConstants"],
        exclude: ["README.md"]
    )
    let servicesTestsTarget = Target.testTarget(
        name: "ServicesTests",
        dependencies: ["Services", "ServicesModels", "SearchModels", "SampleIndex", "SampleIndexModels", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        dependencies: ["MCPCore", "MCPSharedTools", "SharedConstants", "LoggingModels"],
        path: "Sources/MCP/Support"
    )
    let mcpSupportTestsTarget = Target.testTarget(
        name: "MCPSupportTests",
        dependencies: ["MCPSupport", "MCPCore", "MCPSharedTools", "SharedConstants", "TestSupport"],
        path: "Tests/MCP/SupportTests"
    )

    let searchToolProviderTarget = Target.target(
        name: "SearchToolProvider",
        dependencies: ["MCPCore", "MCPSharedTools", "SearchModels", "SampleIndexModels", "ServicesModels", "SharedConstants"]
    )
    let searchToolProviderTestsTarget = Target.testTarget(
        name: "SearchToolProviderTests",
        dependencies: ["SearchToolProvider", "Search", "SearchModels", "SampleIndex", "SampleIndexModels", "Services", "ServicesModels", "MCPSharedTools", "TestSupport"]
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
        dependencies: ["SharedConstants"]
    )
    let remoteSyncTestsTarget = Target.testTarget(
        name: "RemoteSyncTests",
        dependencies: ["RemoteSync", "TestSupport"]
    )

    let availabilityTarget = Target.target(
        name: "Availability",
        dependencies: ["SharedConstants"]
    )
    let availabilityTestsTarget = Target.testTarget(
        name: "AvailabilityTests",
        dependencies: ["Availability", "TestSupport"]
    )

    let astIndexerTarget = Target.target(
        name: "ASTIndexer",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]
    )
    let astIndexerTestsTarget = Target.testTarget(
        name: "ASTIndexerTests",
        dependencies: ["ASTIndexer", "TestSupport"]
    )

    // ---------- DistributionModels (foundation-only seam — value types + Observer protocols) ----------
    let distributionModelsTarget = Target.target(
        name: "DistributionModels",
        dependencies: ["SharedConstants"]
    )
    let distributionModelsTestsTarget = Target.testTarget(
        name: "DistributionModelsTests",
        dependencies: ["DistributionModels", "TestSupport"]
    )

    // ---------- Distribution (#246: SetupCommand lift) ----------
    let distributionTarget = Target.target(
        name: "Distribution",
        dependencies: ["DistributionModels", "SharedConstants"]
    )
    let distributionTestsTarget = Target.testTarget(
        name: "DistributionTests",
        dependencies: ["Distribution", "DistributionModels", "TestSupport"]
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

    // ---------- IndexerModels (foundation-only seam — value types + Observer protocols) ----------
    let indexerModelsTarget = Target.target(
        name: "IndexerModels",
        dependencies: []
    )
    let indexerModelsTestsTarget = Target.testTarget(
        name: "IndexerModelsTests",
        dependencies: ["IndexerModels", "TestSupport"]
    )

    // ---------- Indexer (#244: SaveCommand indexer + preflight lift) ----------
    let indexerTarget = Target.target(
        name: "Indexer",
        dependencies: ["IndexerModels", "SearchModels", "SampleIndexModels", "SharedConstants"]
    )
    let indexerTestsTarget = Target.testTarget(
        name: "IndexerTests",
        dependencies: ["Indexer", "IndexerModels", "TestSupport"]
    )

    // ---------- Ingest (#247: FetchCommand session + pipelines lift) ----------
    let ingestTarget = Target.target(
        name: "Ingest",
        dependencies: ["SharedConstants", "LoggingModels"]
    )
    let ingestTestsTarget = Target.testTarget(
        name: "IngestTests",
        dependencies: ["Ingest", "TestSupport"]
    )

    let cliTarget = Target.executableTarget(
        name: "CLI",
        dependencies: [
            "SharedConstants",
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
            "SharedConstants",
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
            "SharedConstants",
            "Logging",
        ]
    )

    let releaseToolTarget = Target.executableTarget(
        name: "ReleaseTool",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "SharedConstants",
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
            "SharedConstants",
            "TestSupport",
        ],
        path: "Tests/CLICommandTests/ServeTests"
    )

    let doctorTestsTarget = Target.testTarget(
        name: "DoctorTests",
        dependencies: ["CLI", "Diagnostics", "MCPCore", "MCPSupport", "Search", "SearchModels", "TestSupport"],
        path: "Tests/CLICommandTests/DoctorTests"
    )

    let fetchTestsTarget = Target.testTarget(
        name: "FetchTests",
        dependencies: ["CLI", "CoreProtocols", "CorePackageIndexing", "CoreJSONParser", "Core", "Crawler", "CrawlerModels", "Ingest", "TestSupport"],
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
            "TestSupport",
        ],
        path: "Tests/CLICommandTests/SaveTests"
    )

    let tuiTestsTarget = Target.testTarget(
        name: "TUITests",
        dependencies: ["TUI", "CoreProtocols", "Core", "TestSupport"],
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
        dependencies: ["MCPCore", "SampleIndex", "TestSupport"]
    )

    let cupertinoTargets: [Target] = [
        loggingModelsTarget,
        loggingModelsTestsTarget,
        loggingTarget,
        loggingTestsTarget,
        sharedConstantsTarget,
        sharedConstantsTestsTarget,
        sharedUtilsTestsTarget,
        sharedModelsTestsTarget,
        sharedCoreTestsTarget,
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
        crawlerModelsTestsTarget,
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
        distributionModelsTarget,
        distributionModelsTestsTarget,
        distributionTarget,
        distributionTestsTarget,
        diagnosticsTarget,
        diagnosticsTestsTarget,
        indexerModelsTarget,
        indexerModelsTestsTarget,
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

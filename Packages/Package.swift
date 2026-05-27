// swift-tools-version: 6.2

import PackageDescription

// -------------------------------------------------------------

// MARK: - Per-source target enumeration (#1042 Cluster 14 pluggability anchor)

// Single source-of-truth list of the 8 per-source SPM target names.
// Adding a new source means appending its target name here ONCE; the
// `.singleTargetLibrary` product list + every test-target dependency
// array that ships the full source set is derived from this list.
// Before #1042 the same 8 names were enumerated 4 times across this
// file (singleTargetLibrary block + SearchTests + SearchStrategiesTests
// + cupertinoMacOSBinary); the per-source DB split epic's contract test
// asserts this list is helper-based now (`Issue1042PluggabilityContractTests`
// Cluster 14).

let allSourceTargetNames: [String] = [
    "AppleDocsSource",
    "HIGSource",
    "SampleCodeSource",
    "SwiftEvolutionSource",
    "SwiftOrgSource",
    "SwiftBookSource",
    "PackagesSource",
    "AppleArchiveSource",
]

let allSourceTargetDeps: [Target.Dependency] = allSourceTargetNames.map { .target(name: $0) }

let allSourceProducts: [Product] = allSourceTargetNames.map { .singleTargetLibrary($0) }

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
    .singleTargetLibrary("CleanupModels"),
    .singleTargetLibrary("CoreSampleCodeModels"),
    .singleTargetLibrary("SearchAPI"),
    .singleTargetLibrary("SearchSchema"),
    .singleTargetLibrary("SearchSQLite"),
    .singleTargetLibrary("SearchStrategyHelpers"),
    // .singleTargetLibrary("<X>Source") rows live in allSourceProducts (#1042 Cluster 14).
    .singleTargetLibrary("SampleIndex"),
    .singleTargetLibrary("SampleIndexSQLite"),
    .singleTargetLibrary("Services"),
    .singleTargetLibrary("Distribution"),
    .singleTargetLibrary("DistributionModels"),
    .singleTargetLibrary("Diagnostics"),
    .singleTargetLibrary("Indexer"),
    .singleTargetLibrary("IndexerModels"),
    .singleTargetLibrary("EnrichmentModels"),
    .singleTargetLibrary("Enrichment"),
    .singleTargetLibrary("AppleConstraintsPass"),
    .singleTargetLibrary("HierarchyPass"),
    .singleTargetLibrary("HIGPlatformInferencePass"),
    .singleTargetLibrary("PackagesAppleConstraintsPass"),
    .singleTargetLibrary("PackagesAppleImportsPass"),
    .singleTargetLibrary("SamplesAppleConstraintsPass"),
    .singleTargetLibrary("SynonymsPass"),
    .singleTargetLibrary("Resources"),
    .singleTargetLibrary("AvailabilityModels"),
    .singleTargetLibrary("Availability"),
    .singleTargetLibrary("AvailabilityFoundationNetworking"),
    .singleTargetLibrary("CrawlerWebKit"),
    .singleTargetLibrary("CoreJSONParserWebKit"),
    .singleTargetLibrary("CoreSampleCodeWebKit"),
    .singleTargetLibrary("ASTIndexer"),
    .singleTargetLibrary("MCPSupport"),
    .singleTargetLibrary("SearchToolProvider"),
    .singleTargetLibrary("MCPClient"),
    .singleTargetLibrary("RemoteSync"),
    .singleTargetLibrary("RemoteSyncModels"),
    .singleTargetLibrary("AppleConstraintsKit"),
    .executable(name: "cupertino", targets: ["CLI"]),
    .executable(name: "cupertino-tui", targets: ["TUI"]),
    .executable(name: "mock-ai-agent", targets: ["MockAIAgent"]),
    .executable(name: "cupertino-rel", targets: ["ReleaseTool"]),
    .executable(name: "cupertino-constraints-gen", targets: ["ConstraintsGen"]),
]
#else
let macOSOnlyProducts: [Product] = []
#endif

#if os(macOS)
let allProducts = baseProducts + macOSOnlyProducts + allSourceProducts
#else
let allProducts = baseProducts + macOSOnlyProducts
#endif

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
        path: "Sources/Core/JSONParser",
        exclude: ["WebKit"]
    )

    // #904: CoreJSONParserWebKit sibling carries the WKWebView-backed
    // `Core.JSONParser.WKWebViewTitleFetcher` (the last-resort title
    // resolver for documentation URLs the JSON API can't serve).
    // The CoreJSONParser producer is foundation-only post-#904.
    let coreJSONParserWebKitTarget = Target.target(
        name: "CoreJSONParserWebKit",
        dependencies: ["CoreJSONParser", "CoreProtocols"]
    )
    let coreJSONParserTestsTarget = Target.testTarget(
        name: "CoreJSONParserTests",
        // #626 — tests directly reference `Shared.Models.StructuredDocumentationPage.Kind`
        // to assert the new dispatch cases. The type lives in `SharedConstants`
        // (post-#536 the Shared/Models folder consolidated there); CoreProtocols
        // uses it in its public API but doesn't re-export the module.
        dependencies: ["CoreJSONParser", "CoreProtocols", "SharedConstants", "TestSupport"]
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
        path: "Sources/Core/PackageIndexing",
        exclude: ["Model"]
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
    // ---------- CoreSampleCodeModels (foundation-only seam — Observer protocol for GitHubFetcher) ----------
    let coreSampleCodeModelsTarget = Target.target(
        name: "CoreSampleCodeModels",
        dependencies: ["SharedConstants"]
    )
    let coreSampleCodeModelsTestsTarget = Target.testTarget(
        name: "CoreSampleCodeModelsTests",
        dependencies: ["CoreSampleCodeModels", "SharedConstants", "TestSupport"]
    )

    let coreSampleCodeTarget = Target.target(
        name: "CoreSampleCode",
        dependencies: [
            "CoreSampleCodeModels",
            "SharedConstants",
            "LoggingModels",
        ]
    )
    let coreSampleCodeTestsTarget = Target.testTarget(
        name: "CoreSampleCodeTests",
        dependencies: ["CoreSampleCode", "CoreSampleCodeModels", "CoreSampleCodeWebKit", "SharedConstants", "TestSupport"]
    )

    // #904: CoreSampleCodeWebKit sibling carries the WKWebView-backed
    // `Sample.Core.Downloader` (hidden-WKWebView driver that scrapes
    // the Apple sample-code listing + per-sample download URLs via JS).
    // The CoreSampleCode producer is foundation-only post-#904; only
    // `Sample.Core.Catalog` + `Sample.Core.GitHubFetcher` remain.
    let coreSampleCodeWebKitTarget = Target.target(
        name: "CoreSampleCodeWebKit",
        dependencies: [
            "CoreSampleCode",
            "CoreSampleCodeModels",
            "LoggingModels",
            "SharedConstants",
        ]
    )

    let coreTarget = Target.target(
        name: "Core",
        dependencies: [
            "CoreProtocols",
            "SharedConstants",
        ],
        // Core has multi-folder content (Core/ + HTMLParser/) that
        // both belong to the same target post-#... merge. Re-rooting
        // at the family folder + excluding the subfolders that have
        // their own targets keeps everything compiling.
        path: "Sources/Core",
        exclude: ["Protocols", "JSONParser", "PackageIndexing", "SampleCode"]
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

    // ---------- Crawler family (Sources/Crawler/{Core,Model,WebKit}) ----------
    let crawlerModelsTarget = Target.target(
        name: "CrawlerModels",
        dependencies: ["CoreProtocols", "SharedConstants"]
    )
    let crawlerModelsTestsTarget = Target.testTarget(
        name: "CrawlerModelsTests",
        dependencies: ["CrawlerModels", "SharedConstants"]
    )
    // #903: CrawlerWebKit sibling target carrying the WebKit-backed
    // concretes (`Crawler.WebKit.ContentFetcher`, `Crawler.WebKit.Engine`)
    // + `LiveHTTPFetcherFactory`. The Crawler producer is foundation-only
    // (`grep '^import WebKit' Packages/Sources/Crawler/` returns zero).
    // Composition root constructs the factory and passes it via
    // `Crawler.HTTPFetcherFactory` (declared in `CrawlerModels`).
    let crawlerWebKitTarget = Target.target(
        name: "CrawlerWebKit",
        dependencies: [
            "CrawlerModels",
            "CoreProtocols",
            "SharedConstants",
        ]
    )
    // 2026-05-26 audit Finding 9.7+11.1: CrawlerTests now depends on
    // the per-source targets where the `Crawler.<X>` concretes live
    // (HIGSource / SwiftEvolutionSource / AppleArchiveSource /
    // AppleDocsSource). The empty `Crawler` producer target was deleted.
    // Per-source deps spread via the `allSourceTargetDeps` helper per
    // the Cluster-14 anti-co-location contract.
    let crawlerTestsTarget = Target.testTarget(
        name: "CrawlerTests",
        dependencies: [
            "CrawlerModels",
            "CrawlerWebKit",
            "Core",
            "CoreJSONParser",
            "CorePackageIndexing",
            "SharedConstants",
            "TestSupport",
        ] + allSourceTargetDeps
    )

    // ---------- Cleanup family (Sources/Cleanup/{Core,Model}) ----------
    let cleanupModelsTarget = Target.target(
        name: "CleanupModels",
        dependencies: ["SharedConstants"]
    )
    let cleanupModelsTestsTarget = Target.testTarget(
        name: "CleanupModelsTests",
        dependencies: ["CleanupModels", "SharedConstants", "TestSupport"]
    )

    let cleanupTarget = Target.target(
        name: "Cleanup",
        dependencies: ["CleanupModels", "SharedConstants", "LoggingModels"]
    )
    let cleanupTestsTarget = Target.testTarget(
        name: "CleanupTests",
        dependencies: ["Cleanup", "CleanupModels", "TestSupport"]
    )

    // ---------- SearchModels (#402a: value types lifted out of Search so result-consuming
    // layers — Services formatters, MCPSupport, CLI rendering — render hits without
    // taking a behavioural dep on Search). Hosts the `Search` namespace anchor +
    // Search.Result, Search.MatchedSymbol, Search.PlatformAvailability, Search.DocumentFormat.
    let searchModelsTarget = Target.target(
        name: "SearchModels",
        // 2026-05-26 audit Finding 9.7 + 11.1: CrawlerModels carries
        // the `Crawler.HTTPFetcherFactory` strategy seam consumed by
        // `Search.FetchEnvironment`. Foundation-only dep — CrawlerModels
        // is the seam tier, not the producer.
        //
        // 2026-05-27: EnrichmentModels added so `Search.SourceProvider`
        // can return `[any EnrichmentPass]` from
        // `makeSourceSpecificEnrichmentPasses`. EnrichmentModels has
        // zero deps so the foundation tier stays clean; this lets
        // per-source targets declare their own enrichment passes
        // (e.g. HIGSource → HIGPlatformInferencePass) without the
        // CLI composition root needing to import every source's
        // pass module.
        dependencies: ["SharedConstants", "ASTIndexer", "LoggingModels", "CrawlerModels", "EnrichmentModels"]
    )
    let searchModelsTestsTarget = Target.testTarget(
        name: "SearchModelsTests",
        dependencies: [
            "SearchModels",
            "SharedConstants",
            "TestSupport",
            "LoggingModels",
        ] + allSourceTargetDeps
    )

    // ---------- SampleIndexModels (#408 partial: value types + Reader protocol lifted out of
    // SampleIndex so SearchToolProvider can hold an `any Sample.Index.Reader` without
    // pulling in the full indexer + schema + writer surface). Hosts Sample.Index.Project,
    // Sample.Index.File, Sample.Index.FileSearchResult, and Sample.Index.Reader. Mirrors
    // the SearchModels split.
    let sampleIndexModelsTarget = Target.target(
        name: "SampleIndexModels",
        dependencies: ["SharedConstants", "ASTIndexer", "SearchModels"]
    )
    let sampleIndexModelsTestsTarget = Target.testTarget(
        name: "SampleIndexModelsTests",
        dependencies: ["SampleIndexModels", "SharedConstants", "TestSupport"]
    )

    // ---------- SearchSchema (#898 sub-PR A: foundation-only target carrying the
    // DDL SQL strings + the `Search.Schema.currentVersion` Int32 constant.
    // SearchSchema mirrors the SearchModels shape: foundation-only, no
    // actors, no I/O, no SQLite import. Both the orchestration SearchAPI target
    // and the concrete SearchSQLite target consume it.
    let searchSchemaTarget = Target.target(
        name: "SearchSchema",
        dependencies: ["SearchModels"]
    )
    let searchSchemaTestsTarget = Target.testTarget(
        name: "SearchSchemaTests",
        dependencies: ["SearchSchema", "SearchModels"]
    )

    // ---------- SearchSQLite (#898 sub-PR E: concrete SQLite-backed implementation
    // of `Search.Database` / `Search.IndexWriter` from SearchModels). Owns the
    // `Search.Index` actor + all its extensions, `PackageIndex` actor +
    // `Search.PackageQuery` actor (packages.db reader), plus the orchestration
    // pieces tightly coupled to those concretes (`Search.PackageIndexer`,
    // `Search.PackageFTSCandidateFetcher`, `Search.DocsSourceCandidateFetcher`).
    // This is the ONLY producer target that imports `SQLite3` for the
    // search.db / packages.db handles; the orchestration SearchAPI target now
    // operates exclusively through the SearchModels protocol seams.
    let searchSQLiteTarget = Target.target(
        name: "SearchSQLite",
        dependencies: [
            "SearchModels",
            "SearchSchema",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "CorePackageIndexingModels",
            "ASTIndexer",
            // #1078: the HIG-specific SQL pass
            // (`Search.Index.applyHIGPlatformInference`) iterates the
            // shared `HIGPlatformRules.rules` table so the rule set
            // doesn't drift between the indexer strategy (HIGSource)
            // and the post-hoc SQL backfill. HIGPlatformInferencePass
            // is foundation-only (Foundation only), so this dep stays
            // within the per-package-import-contract envelope.
            "HIGPlatformInferencePass",
        ]
    )
    let searchSQLiteTestsTarget = Target.testTarget(
        name: "SearchSQLiteTests",
        dependencies: ["SearchSQLite", "SearchModels", "SearchSchema"]
    )

    let searchTarget = Target.target(
        name: "SearchAPI",
        // Search is the orchestration layer over the SearchModels protocol
        // seams. After #898 sub-PR E it no longer imports `SQLite3` and no
        // longer depends on the concrete SearchSQLite target: `Search.Index`,
        // `PackageIndex`, `Search.PackageQuery`, `Search.PackageIndexer`,
        // and the two `CandidateFetcher` concretes live in SearchSQLite.
        // `Search.IndexBuilder` + the 6 strategies + `Search.SmartQuery` here
        // operate over `any Search.Database & Search.IndexWriter` and
        // `any Search.CandidateFetcher`. The `CLI` composition root imports
        // both targets and wires the concrete in via the
        // `Search.DatabaseFactory` / `Search.IndexWriterFactory` GoF Factory
        // Method seams.
        dependencies: [
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "EnrichmentModels",
        ]
    )
    let searchTestsTarget = Target.testTarget(
        name: "SearchTests",
        dependencies: [
            "SearchAPI",
            "SearchSQLite",
        ] + allSourceTargetDeps + [
            "AppleConstraintsPass",
            "SearchModels",
            "SharedConstants",
            "TestSupport",
            "CorePackageIndexingModels",
            "ASTIndexer",
            "SampleIndex",
            "SampleIndexSQLite",
            "SampleIndexModels",
            "Diagnostics",
            "LoggingModels",
        ]
    )

    // ---------- SearchStrategies (#899: 6 source-indexing strategy
    // concretes + StrategyHelpers + `Search.makeDefaultStrategies`
    // factory function, lifted out of the orchestration SearchAPI target
    // so Search has no concrete strategy dependency. Strict-compliant:
    // imports SearchModels + Foundation tier only; the strategies
    // operate through the `Search.SourceIndexingStrategy` protocol seam.
    // Composition roots (CLI) consume the factory and pass the
    // resulting array to `Search.IndexBuilder.init(searchIndex:strategies:...)`.
    // The further split into 6 individual SPM targets (one per
    // strategy) is queued; this target ships the first cut.
    // #899 prerequisite: extract shared `Search.StrategyHelpers`
    // into its own foundation-only target so per-strategy SPM
    // targets can consume the helpers without depending on the
    // SearchStrategies concrete (which would violate the
    // foundation-only + package-purity rules).
    let searchStrategyHelpersTarget = Target.target(
        name: "SearchStrategyHelpers",
        dependencies: [
            "LoggingModels",
            "SearchModels",
            "SharedConstants",
        ]
    )

    // #899 sub-PR G: SearchStrategies target deleted; all 6 strategies
    // have moved to their own SPM siblings, the StrategyHelpers companion
    // lives in SearchStrategyHelpers (foundation-only seam). The
    // SearchStrategiesTests target retains its name + smoke coverage
    // but depends only on the 6 sibling targets now.
    let searchStrategiesTestsTarget = Target.testTarget(
        name: "SearchStrategiesTests",
        dependencies: allSourceTargetDeps + [
            "AppleConstraintsPass",
            "SearchModels",
            "SearchSQLite",
            "SharedConstants",
            "LoggingModels",
            "EnrichmentModels",
        ]
    )

    // #899 sub-PR B: extract AppleDocsStrategy (renamed to AppleDocsSource in #1008) into its own SPM
    // target. Pattern-setter for the remaining 5 per-strategy splits
    // (HIG, SwiftEvolution, SwiftOrg, AppleArchive, SampleCode). Each
    // strategy ends up as a sibling SPM target conforming
    // `Search.SourceIndexingStrategy`; the composition root (CLI)
    // registers each via `import <X>Strategy` + struct construction.
    let appleDocsSourceTarget = Target.target(
        name: "AppleDocsSource",
        dependencies: [
            "ASTIndexer",
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // 2026-05-26 audit Finding 9.7 + 11.1: WebCrawlFetchStrategy
            // wraps `Crawler.AppleDocs` + delegates to `Ingest.Session`
            // for resume / requeue / baseline / urls-file plumbing.
            "CrawlerModels",
        ]
    )

    // #899 sub-PR C: extract HIGStrategy (renamed to HIGSource in #1010).
    // No ASTIndexer dep: HIGIndexer.extractCode returns
    // Search.ExtractedContent.empty and references no ASTIndexer.* symbols
    // (HIG is pure design guidance, no code extraction). Diverges from the
    // AppleDocsSource template where ASTIndexer is load-bearing.
    let higSourceTarget = Target.target(
        name: "HIGSource",
        dependencies: [
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // 2026-05-26 audit Finding 9.7 + 11.1: HIGFetchStrategy
            // wraps `Crawler.HIG`. Per-source target owns its fetch
            // strategy; `Crawler` stays as shared crawl infrastructure.
            "CrawlerModels",
            // 2026-05-27 (#1073): HIG owns its source-specific
            // platform-inference enrichment pass. Pluggability rule:
            // CLI composition root iterates providers' passes; it
            // doesn't import per-source pass modules itself.
            "EnrichmentModels",
            "HIGPlatformInferencePass",
        ]
    )

    // #899 sub-PR D: extract SampleCodeStrategy (renamed to SampleCodeSource in #1012).
    // ASTIndexer dep is load-bearing here (unlike HIGSource): Search.SampleCodeIndexer.swift
    // runs ASTIndexer.Extractor over full Swift files to capture symbols + imports.
    let sampleCodeSourceTarget = Target.target(
        name: "SampleCodeSource",
        dependencies: [
            "ASTIndexer",
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // 2026-05-26 audit Finding 9.7 + 11.1: SampleCodeFetchStrategy
            // wraps `Sample.Core.GitHubFetcher`.
            "CoreSampleCode",
            "CoreSampleCodeModels",
            "CrawlerModels",
        ]
    )

    // #899 sub-PR E: extract SwiftEvolutionStrategy (renamed to SwiftEvolutionSource in #1017).
    // ASTIndexer dep is load-bearing: Search.SwiftEvolutionIndexer.extractCode runs
    // ASTIndexer.Extractor over Swift code blocks lifted from proposal markdown via the
    // private extractAllCodeBlocks helper.
    let swiftEvolutionSourceTarget = Target.target(
        name: "SwiftEvolutionSource",
        dependencies: [
            "ASTIndexer",
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // 2026-05-26 audit Finding 9.7 + 11.1: SwiftEvolutionFetchStrategy
            // wraps `Crawler.Evolution`.
            "CrawlerModels",
        ]
    )

    // #899 sub-PR F: extract SwiftOrgStrategy (renamed to SwiftOrgSource in #1019).
    // No ASTIndexer dep: SwiftOrgIndexer uses the default Search.SourceIndexer.extractCode
    // implementation (returns Search.ExtractedContent.empty) and references no
    // ASTIndexer.* symbols. Per the per-source-dep-set rule (see HIGSource).
    let swiftOrgSourceTarget = Target.target(
        name: "SwiftOrgSource",
        dependencies: [
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // 2026-05-26 audit Finding 9.7 + 11.1: SwiftOrgSource +
            // SwiftBookSource share AppleDocsSource's
            // `WebCrawlFetchStrategy` concrete (different config per
            // source). Inter-source-target dep accepted because the
            // 3 web-crawl-tier sources have always shared the
            // `runStandardCrawl` codepath pre-fix.
            "AppleDocsSource",
        ]
    )

    // #1021 (Phase 1G of epic #1007): SwiftBookSource is the first view-source
    // per-source target. No prior SwiftBookStrategy to rename: SwiftBook is a
    // sub-source of SwiftOrgStrategy (URL-prefix tagging at emission time);
    // SwiftBookSource contributes only the SourceDefinition + SwiftBookIndexer.
    // makeStrategy returns a private no-op strategy. ASTIndexer dep is
    // load-bearing for SwiftBookIndexer.extractCode's Extractor call over
    // chapter code blocks. First net STRICT_PRODUCERS add since #893 closed at
    // 47 (count goes to 48 in this PR).
    let swiftBookSourceTarget = Target.target(
        name: "SwiftBookSource",
        dependencies: [
            "ASTIndexer",
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // #1093: swift-book gains its own independent fetch leg
            // (no longer a view-source over swift-org). Reuses
            // `AppleDocsSource.WebCrawlFetchStrategy` — the same
            // crawler concrete other web-crawlable sources use.
            "AppleDocsSource",
        ]
    )

    // #1023 (Phase 1H of epic #1007; FINAL): PackagesSource is the
    // first source whose destinationDB is NOT .search. No prior
    // PackagesStrategy or PackagesIndexer: #789 removed both alongside
    // the search.db `packages` table; packages indexing today runs
    // through Indexer.PackagesService against packages.db. PackagesSource
    // contributes a SourceDefinition + FetchInfo + destinationDB = .packages
    // discriminator; makeStrategy + makeIndexer return private noop
    // concretes. No ASTIndexer dep (no indexer logic) and no
    // SearchStrategyHelpers dep (no strategy concrete). Second net-add
    // (count goes 48 -> 49).
    let packagesSourceTarget = Target.target(
        name: "PackagesSource",
        dependencies: [
            "SearchModels",
            "SharedConstants",
            // 2026-05-26 audit Finding 9.7 + 11.1: PackagesFetchStrategy
            // wraps the 3-stage Core.PackageIndexing pipeline.
            "Core",
            "CorePackageIndexing",
            "CorePackageIndexingModels",
            "CoreProtocols", // declares the `Core` namespace anchor that CorePackageIndexingModels extends with `PackageIndexing`.
            "CrawlerModels",
            "LoggingModels",
        ]
    )

    // #899 sub-PR G: extract AppleArchiveStrategy (renamed to AppleArchiveSource in #1014).
    // ASTIndexer dep is load-bearing: Search.AppleArchiveIndexer.swift runs ASTIndexer.Extractor
    // conditionally over Swift-shaped content (guarded by a contains-`func ` / `struct ` /
    // `class ` / `import ` check; Apple Archive content is mixed Swift + Objective-C, parsed
    // best-effort).
    let appleArchiveSourceTarget = Target.target(
        name: "AppleArchiveSource",
        dependencies: [
            "ASTIndexer",
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "CoreProtocols",
            "SearchStrategyHelpers",
            // 2026-05-26 audit Finding 9.7 + 11.1: AppleArchiveFetchStrategy
            // wraps `Crawler.AppleArchive` + `Crawler.ArchiveGuideCatalog`
            // (both physically moved into this target).
            "CrawlerModels",
            "Resources",
        ]
    )

    // 2026-05-26 audit follow-up: single canonical declaration of the
    // production source set. Both CLI's CLIImpl.makeProductionSourceRegistry
    // and SearchToolProviderTests' MCP route-map fixture delegate
    // here so adding a new source = one register-call in
    // Cupertino.CompositionRoot.swift, and no test fixture drifts.
    let cupertinoCompositionTarget = Target.target(
        name: "CupertinoComposition",
        dependencies: [
            "SearchModels",
        ] + allSourceTargetDeps
    )

    let sampleIndexTarget = Target.target(
        name: "SampleIndex",
        dependencies: ["SampleIndexModels", "SearchModels", "SharedConstants", "LoggingModels", "ASTIndexer"]
    )
    let sampleIndexTestsTarget = Target.testTarget(
        name: "SampleIndexTests",
        dependencies: [
            "SampleIndex",
            "SampleIndexSQLite",
            "SampleIndexModels",
            "SearchModels",
            "SharedConstants",
            "ASTIndexer",
            "LoggingModels",
            "TestSupport",
        ]
    )

    // ---------- SampleIndexSQLite (#902 mirror of #898 sub-PR E:
    // SQLite-backed concrete for the `Sample.Index.Reader` +
    // `Sample.Index.Writer` protocol seams in SampleIndexModels.
    // Owns the `Sample.Index.Database` actor + its read-side conformance
    // witness. The SampleIndex orchestration target keeps `Builder` +
    // `AvailabilitySidecar` + `Error` and operates exclusively through
    // the SampleIndexModels protocol seams.
    let sampleIndexSQLiteTarget = Target.target(
        name: "SampleIndexSQLite",
        dependencies: [
            "SampleIndexModels",
            "SearchModels",
            "SharedConstants",
            "LoggingModels",
            "ASTIndexer",
        ]
    )
    let sampleIndexSQLiteTestsTarget = Target.testTarget(
        name: "SampleIndexSQLiteTests",
        dependencies: ["SampleIndexSQLite", "SampleIndexModels", "SharedConstants"]
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
        dependencies: ["ServicesModels", "SearchModels", "SampleIndexModels", "SharedConstants"]
    )
    let servicesTestsTarget = Target.testTarget(
        name: "ServicesTests",
        dependencies: ["Services", "ServicesModels", "SearchModels", "SampleIndex", "SampleIndexSQLite", "SampleIndexModels", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        // 2026-05-26 audit Cluster 12 follow-up: SearchModels carries
        // `Search.URIResourceStrategy` + `Search.URIResourceEnvironment`
        // — the seam the per-source URI dispatch consumes. Foundation
        // tier import (gof-di-rules § 4-8 allows it).
        dependencies: ["MCPCore", "MCPSharedTools", "SearchModels", "SharedConstants", "LoggingModels"],
        path: "Sources/MCP/Support"
    )
    let mcpSupportTestsTarget = Target.testTarget(
        name: "MCPSupportTests",
        // 2026-05-26 audit Cluster 12 follow-up: per-source URI
        // strategy concretes live in their owning source targets
        // (AppleDocsSource / SwiftEvolutionSource / AppleArchiveSource);
        // tests that build a DocsResourceProvider need access to
        // instantiate them.
        dependencies: [
            "AppleDocsSource",
            "AppleArchiveSource",
            "MCPSupport",
            "MCPCore",
            "MCPSharedTools",
            "SearchModels",
            "SharedConstants",
            "SwiftEvolutionSource",
            "TestSupport",
        ],
        path: "Tests/MCP/SupportTests"
    )

    let searchToolProviderTarget = Target.target(
        name: "SearchToolProvider",
        dependencies: ["MCPCore", "MCPSharedTools", "SearchModels", "SampleIndexModels", "ServicesModels", "SharedConstants"]
    )
    let searchToolProviderTestsTarget = Target.testTarget(
        name: "SearchToolProviderTests",
        dependencies: [
            "SearchToolProvider",
            "SearchAPI",
            "SearchSQLite",
            "SearchModels",
            "SampleIndex",
            "SampleIndexSQLite",
            "SampleIndexModels",
            "Services",
            "ServicesModels",
            "MCPSharedTools",
            "ASTIndexer",
            "TestSupport",
            // 2026-05-26 audit Finding 14.4: convenience-init fixture
            // sources the canonical route map from the production
            // composition root so adding a new <X>Source automatically
            // extends the test fixture's route dispatch.
            "CupertinoComposition",
        ]
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

    // ---------- RemoteSyncModels (foundation-only seam — closures-to-Observer epic) ----------
    // Carries the `RemoteSync` namespace anchor + `Progress` /
    // `IndexState` / `IndexerResult` / `IndexerError` value types
    // and the `DocumentIndexing` Strategy + `IndexerProgressObserving`
    // / `IndexerDocumentObserving` Observer protocols. Flat-named
    // because the producer `RemoteSync.Indexer` is a public actor
    // (can't be extended from outside).
    let remoteSyncModelsTarget = Target.target(
        name: "RemoteSyncModels",
        dependencies: ["SharedConstants"]
    )
    let remoteSyncModelsTestsTarget = Target.testTarget(
        name: "RemoteSyncModelsTests",
        dependencies: ["RemoteSyncModels", "SharedConstants", "TestSupport"]
    )

    let remoteSyncTarget = Target.target(
        name: "RemoteSync",
        dependencies: ["RemoteSyncModels", "SharedConstants"]
    )
    let remoteSyncTestsTarget = Target.testTarget(
        name: "RemoteSyncTests",
        dependencies: ["RemoteSync", "RemoteSyncModels", "TestSupport"]
    )

    let availabilityModelsTarget = Target.target(
        name: "AvailabilityModels",
        dependencies: []
    )
    let availabilityTarget = Target.target(
        name: "Availability",
        dependencies: ["AvailabilityModels", "SharedConstants"]
    )
    let availabilityFoundationNetworkingTarget = Target.target(
        name: "AvailabilityFoundationNetworking",
        dependencies: ["AvailabilityModels"]
    )
    let availabilityTestsTarget = Target.testTarget(
        name: "AvailabilityTests",
        dependencies: ["Availability", "AvailabilityFoundationNetworking", "TestSupport"]
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

    // ---------- Distribution family (Sources/Distribution/{Core,Model}) ----------
    // Per folder-grouping.md: family root with Core/ (live concrete)
    // + Model/ (foundation-only seam). Subfolder names singular.
    let distributionModelsTarget = Target.target(
        name: "DistributionModels",
        // LoggingModels added in #930 so Distribution.DatabaseHealthCheck
        // (the Doctor per-DB strategy seam) can take `any Logging.Recording`
        // as its output sink without leaking the live recorder concrete.
        dependencies: ["SharedConstants", "LoggingModels"]
    )
    let distributionModelsTestsTarget = Target.testTarget(
        name: "DistributionModelsTests",
        dependencies: ["DistributionModels", "TestSupport"]
    )

    let distributionTarget = Target.target(
        name: "Distribution",
        dependencies: ["DistributionModels", "SearchModels", "SharedConstants"]
    )
    let distributionTestsTarget = Target.testTarget(
        name: "DistributionTests",
        dependencies: ["Distribution", "DistributionModels", "SearchModels", "TestSupport"]
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

    // ---------- Enrichment family (#1042 follow-up: folder-grouping.md
    // restructure). All Enrichment-related targets live under
    // Sources/Enrichment/ with subfolders: Core/ (runtime LiveRunner),
    // Models/ (foundation-only seam), Passes/ (6 single-file
    // per-pass targets). Per folder-grouping.md the single-file pass
    // targets share one parent folder via explicit `path:` + `sources:`
    // so the filesystem flattens to one folder of 6 sibling files
    // while SPM target identity stays separate (lift-out preservation).
    let enrichmentModelsTarget = Target.target(
        name: "EnrichmentModels",
        dependencies: []
    )
    let enrichmentModelsTestsTarget = Target.testTarget(
        name: "EnrichmentModelsTests",
        dependencies: ["EnrichmentModels", "TestSupport"]
    )

    let enrichmentTarget = Target.target(
        name: "Enrichment",
        dependencies: ["EnrichmentModels", "SearchModels", "SampleIndexModels", "SharedConstants"]
    )
    let enrichmentTestsTarget = Target.testTarget(
        name: "EnrichmentTests",
        dependencies: ["Enrichment", "EnrichmentModels", "AppleConstraintsPass", "TestSupport"]
    )

    // Per-pass single-file targets, co-located under
    // Sources/Enrichment/Passes/ via shared `path:` + per-target
    // disjoint `sources:` lists. Target identity preserved; consumers
    // still import `AppleConstraintsPass` / etc. unchanged. Adding a
    // 7th pass = one more append below + one new `.swift` file in
    // the same directory.
    let appleConstraintsPassTarget = Target.target(
        name: "AppleConstraintsPass",
        dependencies: [
            "EnrichmentModels",
            "SearchModels",
            "SharedConstants",
        ]
    )

    let hierarchyPassTarget = Target.target(
        name: "HierarchyPass",
        dependencies: [
            "EnrichmentModels",
            "SearchModels",
        ]
    )

    // 2026-05-27: HIG-specific topic-aware platform-inference pass.
    let higPlatformInferencePassTarget = Target.target(
        name: "HIGPlatformInferencePass",
        dependencies: [
            "EnrichmentModels",
            "SearchModels",
        ]
    )

    let packagesAppleConstraintsPassTarget = Target.target(
        name: "PackagesAppleConstraintsPass",
        dependencies: [
            "EnrichmentModels",
            "SearchModels",
        ]
    )

    let packagesAppleImportsPassTarget = Target.target(
        name: "PackagesAppleImportsPass",
        dependencies: [
            "EnrichmentModels",
            "SearchModels",
        ]
    )

    let samplesAppleConstraintsPassTarget = Target.target(
        name: "SamplesAppleConstraintsPass",
        dependencies: [
            "EnrichmentModels",
            "SampleIndexModels",
            "SearchModels",
            "SharedConstants",
        ]
    )

    let synonymsPassTarget = Target.target(
        name: "SynonymsPass",
        dependencies: [
            "EnrichmentModels",
            "SearchModels",
        ]
    )

    // ---------- Indexer (#244: SaveCommand indexer + preflight lift) ----------
    let indexerTarget = Target.target(
        name: "Indexer",
        dependencies: ["IndexerModels", "SearchModels", "SampleIndexModels", "SharedConstants"]
    )
    let indexerTestsTarget = Target.testTarget(
        name: "IndexerTests",
        // #1059: Issue1059OptionalDirScopeTests stubs the
        // Search.DocsIndexingRunner + related strategy protocols and
        // references Shared.Models.StructuredDocumentationPage in
        // those stub signatures, so SearchModels + SharedConstants
        // need to be visible.
        dependencies: ["Indexer", "IndexerModels", "SearchModels", "SharedConstants", "TestSupport"]
    )

    // 2026-05-26 audit Finding 9.7 + 11.1: the Ingest target's contents
    // (`Ingest.Session.swift` + `Ingest.swift` — session resume / requeue /
    // baseline / urls-file helpers) lifted into `AppleDocsSource` (the
    // only consumer post-lift). The empty Ingest target + IngestTests
    // were dropped; existing tests cover the same surface via
    // `Tests/IngestTests/` which now lives under AppleDocsSourceTests
    // (TODO follow-up). Pre-lift was `#247: FetchCommand session +
    // pipelines lift`; today the pipelines themselves are per-source.

    let cliTarget = Target.executableTarget(
        name: "CLI",
        dependencies: [
            "SharedConstants",
            "CoreProtocols", "CoreJSONParser", "CoreJSONParserWebKit", "CorePackageIndexing", "CorePackageIndexingModels", "Core", "CoreSampleCode", "CoreSampleCodeWebKit",
            "CrawlerWebKit",
            "Cleanup",
            "SearchAPI",
            "SearchSQLite",
        ] + allSourceTargetDeps + [
            "CupertinoComposition",
            "AppleConstraintsPass",
            "HierarchyPass",
            // 2026-05-27 (#1073): HIGPlatformInferencePass is owned by
            // HIGSource (transits here via `allSourceTargetDeps`). CLI
            // no longer depends on per-source enrichment modules.
            "PackagesAppleConstraintsPass",
            "PackagesAppleImportsPass",
            "SamplesAppleConstraintsPass",
            "SynonymsPass",
            "SampleIndex",
            "SampleIndexSQLite",
            "Services",
            "ServicesModels",
            "Distribution",
            "DistributionModels",
            "Diagnostics",
            "Indexer",
            "Logging",
            "RemoteSync",
            "Availability",
            "AvailabilityFoundationNetworking",
            "AvailabilityModels",
            "AppleConstraintsKit",
            "Enrichment",
            "EnrichmentModels",
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
            "SearchAPI",
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

    // ---------- AppleConstraintsKit (#759 iteration 3) ----------
    // Producer-side companion to the `Search.StaticConstraintsLookup`
    // protocol seam (declared in `SearchModels`). Parses Apple's
    // `swift symbolgraph-extract` JSON into the cupertino constraints
    // table. Foundation-only + SearchModels (the protocol-seam
    // companion) — per gof-di-rules.md rule 8 (producer foundation-only).
    let appleConstraintsKitTarget = Target.target(
        name: "AppleConstraintsKit",
        dependencies: ["SearchModels"]
    )
    let appleConstraintsKitTestsTarget = Target.testTarget(
        name: "AppleConstraintsKitTests",
        dependencies: [
            "AppleConstraintsKit",
            "SearchModels",
        ]
    )
    let constraintsGenTarget = Target.executableTarget(
        name: "ConstraintsGen",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "AppleConstraintsKit",
            "SearchModels",
        ]
    )

    let testSupportTarget = Target.target(
        name: "TestSupport",
        dependencies: []
    )

    // CLI Command Test Targets
    let serveTestsTarget = Target.testTarget(
        name: "ServeTests",
        dependencies: [
            "AppleArchiveSource",
            "AppleDocsSource",
            "CLI",
            "CrawlerWebKit",
            "MCPCore",
            "MCPSupport",
            "SearchAPI",
            "SearchModels",
            "SearchToolProvider",
            "SampleIndex",
            "SampleIndexSQLite",
            "SampleIndexModels",
            "Services",
            "ServicesModels",
            "SharedConstants",
            "SwiftEvolutionSource",
            "TestSupport",
        ],
        path: "Tests/CLICommandTests/ServeTests"
    )

    let doctorTestsTarget = Target.testTarget(
        name: "DoctorTests",
        dependencies: ["CLI", "Diagnostics", "MCPCore", "MCPSupport", "SearchAPI", "SearchModels", "TestSupport"],
        path: "Tests/CLICommandTests/DoctorTests"
    )

    let fetchTestsTarget = Target.testTarget(
        name: "FetchTests",
        // 2026-05-26 audit 9.7+11.1: Crawler.X concretes + Ingest.Session
        // moved into per-source targets. FetchTests depends on the per-source
        // targets (spread via the `allSourceTargetDeps` helper per the
        // Cluster-14 anti-co-location contract) + CrawlerModels (foundation)
        // + CrawlerWebKit (Live factory). The empty Crawler/Ingest packages
        // were deleted.
        dependencies: [
            "CLI",
            "CoreProtocols", "CorePackageIndexing", "CoreJSONParser", "Core",
            "CrawlerModels", "CrawlerWebKit",
            "TestSupport",
        ] + allSourceTargetDeps,
        path: "Tests/CLICommandTests/FetchTests"
    )

    let saveTestsTarget = Target.testTarget(
        name: "SaveTests",
        dependencies: [
            "AppleDocsSource",
            "CLI",
            "CoreProtocols",
            "Core",
            "CoreJSONParser",
            "CorePackageIndexing",
            "CrawlerModels",
            "CrawlerWebKit",
            "Indexer",
            "SearchAPI",
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
        // DistributionModels added in #930 so tests can name
        // `Distribution.DatabaseHealthCheck` for the strategy-seam
        // conformance checks on the 3 CLI conformers.
        // Distribution added by the per-source-db-split epic so
        // ConstantsAuditTests can pin PerSourceDBSplitMigrator.legacyRenameSuffix.
        // Diagnostics added so PerSourceDestinationRoundtripTests can read
        // the per-DB PRAGMA user_version stamp via Diagnostics.Probes.
        // Services + ServicesModels added in #1042 so
        // Issue1042PluggabilityContractTests can assert against
        // Services.ReadService.Source (Cluster 9 sub-3). The same
        // pattern is used in Issue1039ReadHigRoundtripTests.
        // RemoteSyncModels added so the contract test can reference
        // RemoteSync.IndexState.Phase (Cluster 11 sub-1).
        // SearchSQLite added so the contract test can reference
        // Search.DocsSourceCandidateFetcher.defaultSwiftVersionSources +
        // defaultFrameworkScopedSources (Cluster 4 sub-1 + sub-2).
        // 2026-05-26 audit Cluster 12 follow-up: AppleDocsSource +
        // AppleArchiveSource + SwiftEvolutionSource added so the
        // contract test in Issue1042PluggabilityContractTests can
        // build a DocsResourceProvider with the per-source URI
        // strategy concretes.
        // EnrichmentModels + HIGSource added in #1073 so
        // Issue1073PluggabilityContractTests can assert HIGSource's
        // makeSourceSpecificEnrichmentPasses override returns a
        // non-empty list + the production call-site grep in
        // CLIImpl.Command.Save.Indexers.swift iterates providers.
        dependencies: [
            "AppleArchiveSource",
            "AppleDocsSource",
            "CLI", "CupertinoComposition", "Diagnostics", "Distribution", "DistributionModels",
            "EnrichmentModels",
            "HIGSource",
            "MCPSupport",
            "Services", "ServicesModels", "RemoteSyncModels", "SearchSQLite",
            "SwiftEvolutionSource",
        ]
    )
    let mockAIAgentTestsTarget = Target.testTarget(
        name: "MockAIAgentTests",
        dependencies: [
            "MCPCore",
            "SampleIndex",
            "SampleIndexSQLite",
            "TestSupport",
        ]
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
        coreJSONParserWebKitTarget,
        corePackageIndexingModelsTarget,
        corePackageIndexingModelsTestsTarget,
        corePackageIndexingTarget,
        corePackageIndexingTestsTarget,
        resourcesTarget,
        resourcesTestsTarget,
        coreSampleCodeModelsTarget,
        coreSampleCodeModelsTestsTarget,
        coreSampleCodeTarget,
        coreSampleCodeTestsTarget,
        coreSampleCodeWebKitTarget,
        coreTarget,
        coreTestsTarget,
        crawlerModelsTarget,
        crawlerModelsTestsTarget,
        crawlerWebKitTarget,
        crawlerTestsTarget,
        cleanupModelsTarget,
        cleanupModelsTestsTarget,
        cleanupTarget,
        cleanupTestsTarget,
        searchModelsTarget,
        searchModelsTestsTarget,
        sampleIndexModelsTarget,
        sampleIndexModelsTestsTarget,
        searchSchemaTarget,
        searchSchemaTestsTarget,
        searchSQLiteTarget,
        searchSQLiteTestsTarget,
        searchTarget,
        searchTestsTarget,
        searchStrategyHelpersTarget,
        searchStrategiesTestsTarget,
        appleDocsSourceTarget,
        higSourceTarget,
        sampleCodeSourceTarget,
        swiftEvolutionSourceTarget,
        swiftOrgSourceTarget,
        swiftBookSourceTarget,
        packagesSourceTarget,
        appleArchiveSourceTarget,
        cupertinoCompositionTarget,
        sampleIndexTarget,
        sampleIndexTestsTarget,
        sampleIndexSQLiteTarget,
        sampleIndexSQLiteTestsTarget,
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
        enrichmentModelsTarget,
        enrichmentModelsTestsTarget,
        enrichmentTarget,
        appleConstraintsPassTarget,
        hierarchyPassTarget,
        higPlatformInferencePassTarget,
        packagesAppleConstraintsPassTarget,
        packagesAppleImportsPassTarget,
        samplesAppleConstraintsPassTarget,
        synonymsPassTarget,
        enrichmentTestsTarget,
        indexerTarget,
        indexerTestsTarget,
        mcpSupportTarget,
        mcpSupportTestsTarget,
        searchToolProviderTarget,
        searchToolProviderTestsTarget,
        mcpClientTarget,
        mcpClientTestsTarget,
        remoteSyncModelsTarget,
        remoteSyncModelsTestsTarget,
        remoteSyncTarget,
        remoteSyncTestsTarget,
        availabilityModelsTarget,
        availabilityTarget,
        availabilityFoundationNetworkingTarget,
        availabilityTestsTarget,
        astIndexerTarget,
        astIndexerTestsTarget,
        testSupportTarget,
        cliTarget,
        tuiTarget,
        mockAIAgentTarget,
        releaseToolTarget,
        releaseToolTestsTarget,
        appleConstraintsKitTarget,
        appleConstraintsKitTestsTarget,
        constraintsGenTarget,
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

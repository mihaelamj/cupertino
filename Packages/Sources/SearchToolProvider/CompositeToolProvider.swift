import Foundation
import MCPCore
import MCPSharedTools
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants

// MARK: - Unified Cupertino Tool Provider

/// Composite tool provider that provides unified search across all documentation sources.
/// Handles the unified `search` tool with a `source` parameter for docs, samples, HIG, archive, packages, etc.
public actor CompositeToolProvider: MCP.Core.ToolProvider {
    // Protocol-typed so this file doesn't import the Search, SampleIndex,
    // or Services behavioural targets — every cross-package surface is
    // an abstraction from a Models target. The CLI composition root
    // constructs the concrete actors and passes them across the seam.

    private let docsService: (any Services.DocsSearcher)?
    private let sampleService: (any Sample.Search.Searcher)?
    private let teaserService: (any Services.Teaser)?
    private let unifiedService: (any Services.UnifiedSearcher)?

    // Kept for low-level operations (list frameworks, read document,
    // semantic-symbol searches) that don't have a service-layer wrapper.
    private let searchIndex: (any Search.Database)?
    private let sampleDatabase: (any Sample.Index.Reader)?

    /// #50: the documentation-tree children listing, supplied by the composition root (the
    /// embedded data engine over the current corpus). `handle_list_children` delegates to this so
    /// the server and the embedded apps share ONE topic-group parser instead of two copies. When
    /// nil the `list_children` tool reports the index does not support children listing.
    /// #50 / query-side source pluggability: the engine-backed document browser the composition
    /// root injects (CupertinoDataEngine over every per-source corpus). `list_documents` and
    /// `list_children` route through it for ALL sources, not just apple-docs: the engine has a
    /// reader per source, so the curated sources (swift-org, swift-evolution, swift-book, hig,
    /// apple-archive) list their documents instead of being rejected. When nil the two tools
    /// report the index does not support browsing.
    private let documentBrowsing: (any Search.DocumentBrowsing)?

    /// `#789`-style architectural gap fix landed in v1.2.0 PR-2. Pre-fix,
    /// MCP `search source=packages` routed through
    /// `handleSearchDocs(source:"packages")` → `docsService.search` →
    /// `Search.Database.search` against `search.db`, which returns zero
    /// rows because `packages` isn't one of the six source values
    /// search.db knows. The fix wires `packages.db` directly through this
    /// seam; the new `handleSearchPackages` dispatch path consults it.
    /// When nil (no packages.db on disk, composition root didn't wire),
    /// the `packages` single-source MCP path responds with the same
    /// "Documentation index not available"-style error frame as the
    /// docs path uses for a missing search.db.
    private let packagesSearcher: (any Search.PackagesSearcher)?

    /// #645 — set when `search.db` exists on disk but couldn't be
    /// opened (schema mismatch, corrupt file, "not a database"). When
    /// non-nil the tool provider still advertises the search.db-
    /// dependent tools so `tools/list` is honest about the server's
    /// capability surface; per-tool handlers throw a clear error
    /// frame naming the reason. When nil + searchIndex is also nil,
    /// the file is legitimately missing and we hide the tools (the
    /// pre-#645 status quo for samples-only servers).
    private let searchIndexDisabledReason: String?

    // #582: fallback resource provider used by `handleReadDocument` when
    // the search-index lookup misses. `MCP.Support.DocsResourceProvider`
    // (the same instance the CLI uses for `resources/read`) does a
    // filesystem fallback over the crawled docs directory that the
    // search-index direct lookup doesn't. Pre-fix, `read_document` and
    // `resources/read` had divergent lookup paths and the tool failed
    // for URIs the resource path accepted (e.g.
    // `apple-docs://accelerate/documentation_accelerate` against a
    // pre-#293 indexed bundle). Wiring the same provider into both
    // paths makes them symmetric.
    //
    // Typed against `MCP.Core.ResourceProvider` (already imported) so
    // this file still doesn't reach for `MCP.Support` and the per-
    // package import-contract stays clean.
    private let documentResourceProvider: (any MCP.Core.ResourceProvider)?

    /// #1042 Cluster 7 pluggability anchor: registry-derived list of
    /// source IDs the MCP `search` tool advertises in its
    /// `source` enum schema. Composition root supplies
    /// `["all"] + registry.allEnabled.map(\.definition.id)`; pre-fix
    /// this list was hardcoded in `listTools` as 10 SourcePrefix
    /// constants.
    private let searchToolSourceEnumValues: [String]

    /// 2026-05-26 audit Finding 14.4: registry-derived source-id →
    /// SearchRoute dispatch map. `handleSearch` consults this dict
    /// instead of switching on source-id literals. Pre-fix the
    /// dispatcher hardcoded 9 source-ids in a switch; adding a new
    /// source required editing this file. Post-fix the route is the
    /// source's own declared property; new sources plug in via their
    /// `SourceProvider.searchRoute`.
    private let searchToolRoutesByID: [String: Search.SearchRoute]

    /// #1277: the canonical active-source inventory (registry-declared per-source databases with
    /// on-disk presence + schema version), supplied by the composition root. When non-nil the
    /// `list_sources` tool is advertised and returns it; when nil the tool stays hidden, so
    /// existing call sites and test doubles that do not wire it are unaffected.
    private let sourceInventory: Search.SourceInventory?

    /// #1311: registry-derived source-id → declared `Search.SourceHierarchy`. The unified `list`
    /// tool returns this for level 0 (`list(source)`) so a client can discover a source's shape
    /// (depth, per-level kind, leaf content type) instead of assuming framework -> document.
    /// Empty when the composition root does not wire it (the `list` tool then stays hidden).
    private let sourceHierarchies: [String: Search.SourceHierarchy]

    /// #1311: per-source framework enumeration for `list` level 1. The composition root supplies a
    /// closure over the engine's per-source reader (`engine.documentBrowser(id: source)
    /// .listFrameworks()`), so each source lists ITS OWN frameworks, fixing the source-blind
    /// `list_frameworks` leftover. Nil when not wired.
    private let sourceFrameworks: (@Sendable (String) async throws -> [String: Int])?

    /// The sources the `list` tool browses as CATALOGS (samples, packages): their corpus is a set of
    /// entries each holding a file tree, not a documentation graph, so level 1 enumerates entries and
    /// levels 2..N walk a file tree (any depth) rather than the framework -> document -> topic model.
    /// Empty when not wired.
    private let catalogSources: Set<String>

    /// Catalog level 1: one window of a catalog source's entries (every project / every package).
    private let catalogEntries: (@Sendable (_ source: String, _ offset: Int, _ limit: Int) async throws -> Search.CatalogEntryPage)?

    /// Catalog levels 2..N: the immediate children of a node (an entry root or a folder beneath it).
    private let catalogChildren: (@Sendable (_ source: String, _ parentURI: String) async throws -> [Search.CatalogNode])?

    /// Primary init used by the CLI composition root. Each cross-package
    /// surface arrives pre-wired as a protocol-typed value so this file
    /// doesn't have to import the Search / SampleIndex / Services
    /// behavioural targets to do any wiring of its own.
    public init(
        searchIndex: (any Search.Database)?,
        sampleDatabase: (any Sample.Index.Reader)?,
        docsService: (any Services.DocsSearcher)?,
        sampleService: (any Sample.Search.Searcher)?,
        teaserService: (any Services.Teaser)?,
        unifiedService: (any Services.UnifiedSearcher)?,
        packagesSearcher: (any Search.PackagesSearcher)? = nil,
        documentResourceProvider: (any MCP.Core.ResourceProvider)? = nil,
        searchIndexDisabledReason: String? = nil,
        searchToolSourceEnumValues: [String] = [],
        searchToolRoutesByID: [String: Search.SearchRoute] = [:],
        sourceInventory: Search.SourceInventory? = nil,
        documentBrowsing: (any Search.DocumentBrowsing)? = nil,
        sourceHierarchies: [String: Search.SourceHierarchy] = [:],
        sourceFrameworks: (@Sendable (String) async throws -> [String: Int])? = nil,
        catalogSources: Set<String> = [],
        catalogEntries: (@Sendable (_ source: String, _ offset: Int, _ limit: Int) async throws -> Search.CatalogEntryPage)? = nil,
        catalogChildren: (@Sendable (_ source: String, _ parentURI: String) async throws -> [Search.CatalogNode])? = nil
    ) {
        self.searchIndex = searchIndex
        self.sampleDatabase = sampleDatabase
        self.documentBrowsing = documentBrowsing
        self.docsService = docsService
        self.sampleService = sampleService
        self.teaserService = teaserService
        self.unifiedService = unifiedService
        self.packagesSearcher = packagesSearcher
        self.documentResourceProvider = documentResourceProvider
        self.searchIndexDisabledReason = searchIndexDisabledReason
        self.searchToolSourceEnumValues = searchToolSourceEnumValues
        self.searchToolRoutesByID = searchToolRoutesByID
        self.sourceInventory = sourceInventory
        self.sourceHierarchies = sourceHierarchies
        self.sourceFrameworks = sourceFrameworks
        self.catalogSources = catalogSources
        self.catalogEntries = catalogEntries
        self.catalogChildren = catalogChildren
    }

    /// True when the server should advertise search.db-dependent tools.
    /// The DB is either currently open (ready path) or present-but-
    /// unopenable (configuration-error path, #645). When the file is
    /// legitimately missing, both branches are false and the tools stay
    /// hidden in `tools/list`.
    private var searchToolsVisible: Bool {
        searchIndex != nil || searchIndexDisabledReason != nil
    }

    /// #645 — error frame for tool calls when `search.db` is present
    /// but unopenable. The handler funnel checks `searchIndex` and
    /// throws this when nil with `searchIndexDisabledReason` set,
    /// instead of the generic "index not available" message. AI agents
    /// reading the error see the same actionable text the CLI prints
    /// (e.g. "schema mismatch — run `cupertino setup` …"), matching
    /// the #640 degradation pattern on the unified search path.
    private func searchIndexUnavailableError(_ paramName: String) -> Shared.Core.ToolError {
        let message: String
        if let reason = searchIndexDisabledReason {
            message = "Documentation index disabled: \(reason)"
        } else {
            message = "Documentation index not available"
        }
        return Shared.Core.ToolError.invalidArgument(paramName, message)
    }

    /// #1283 — actionable error frame for the sample-code tools
    /// (`list_samples`, `read_sample`, `read_sample_file`) and the
    /// `source: samples` search path when the samples database is not
    /// installed. Mirrors `searchIndexUnavailableError`: an AI agent or CLI
    /// caller reading the frame sees both remediation paths (download a
    /// prebuilt bundle, or build the source locally) rather than a dead-end
    /// "not available" with no next step.
    private func sampleDatabaseUnavailableError(_ paramName: String) -> Shared.Core.ToolError {
        Shared.Core.ToolError.invalidArgument(
            paramName,
            "Sample code database not available. Run `cupertino setup` to download it, "
                + "or `cupertino save --source samples` to build it."
        )
    }

    // The two-argument convenience init that constructed concrete
    // service actors from the index seams moved to the
    // SearchToolProviderTests target (`CompositeToolProvider+ServicesWiring.swift`).
    // Production code calls the explicit six-argument init above; that
    // shape keeps `import Services` out of this file.

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> MCP.Core.Protocols.ListToolsResult {
        var allTools: [MCP.Core.Protocols.Tool] = []

        let searchProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamQuery: stringSchema(
                description: "Search query string."
            ),
            Shared.Constants.Search.schemaParamSource: stringSchema(
                description: "Optional source filter.",
                // #1042 Cluster 7: list is supplied by the composition root
                // from the production source registry (plus "all" + the
                // appleSampleCode alias the existing dispatch accepts).
                // When the init was called without a list (legacy two-arg
                // path / tests that don't exercise the search tool),
                // fall back to the historical 10-element literal.
                enumValues: !searchToolSourceEnumValues.isEmpty
                    ? searchToolSourceEnumValues
                    : [
                        "all",
                        Shared.Constants.SourcePrefix.appleDocs,
                        Shared.Constants.SourcePrefix.samples,
                        Shared.Constants.SourcePrefix.appleSampleCode,
                        Shared.Constants.SourcePrefix.hig,
                        Shared.Constants.SourcePrefix.appleArchive,
                        Shared.Constants.SourcePrefix.swiftEvolution,
                        Shared.Constants.SourcePrefix.swiftOrg,
                        Shared.Constants.SourcePrefix.swiftBook,
                        Shared.Constants.SourcePrefix.packages,
                    ]
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework filter (e.g. swiftui, foundation)."
            ),
            Shared.Constants.Search.schemaParamLanguage: stringSchema(
                description: "Language filter for Swift.org sources."
            ),
            Shared.Constants.Search.schemaParamIncludeArchive: boolSchema(
                description: "Legacy compatibility flag. Current fan-out already includes apple-archive; use source=apple-archive for archive-only results."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 20)."
            ),
            Shared.Constants.Search.schemaParamMinIOS: stringSchema(
                description: "Minimum iOS version filter (e.g. 17.0)."
            ),
            Shared.Constants.Search.schemaParamMinMacOS: stringSchema(
                description: "Minimum macOS version filter (e.g. 14.0)."
            ),
            Shared.Constants.Search.schemaParamMinTvOS: stringSchema(
                description: "Minimum tvOS version filter (e.g. 17.0)."
            ),
            Shared.Constants.Search.schemaParamMinWatchOS: stringSchema(
                description: "Minimum watchOS version filter (e.g. 10.0)."
            ),
            Shared.Constants.Search.schemaParamMinVisionOS: stringSchema(
                description: "Minimum visionOS version filter (e.g. 1.0)."
            ),
            Shared.Constants.Search.schemaParamMinSwift: stringSchema(
                description: Self.schemaDescriptionMinSwift
            ),
            Shared.Constants.Search.schemaParamAppleImports: stringSchema(
                description: Self.schemaDescriptionAppleImports
            ),
        ]

        let readDocumentProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamURI: stringSchema(
                description: "Document URI to read."
            ),
            Shared.Constants.Search.schemaParamFormat: stringSchema(
                description: "Output format (json or markdown).",
                enumValues: [
                    Shared.Constants.Search.formatValueJSON,
                    Shared.Constants.Search.formatValueMarkdown,
                ]
            ),
        ]

        let typedOutputFormatProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamFormat: stringSchema(
                description: "Output format. Default: markdown. Use json for a typed, GUI-decodable payload.",
                enumValues: [
                    Shared.Constants.Search.formatValueJSON,
                    Shared.Constants.Search.formatValueMarkdown,
                ]
            ),
        ]

        let listDocumentsProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework identifier, import name, or display name (e.g. swiftui, SwiftUI)."
            ),
            Shared.Constants.Search.schemaParamSource: stringSchema(
                description: "Source to browse. Default: apple-docs.",
                enumValues: [Shared.Constants.SourcePrefix.appleDocs]
            ),
            Shared.Constants.Search.schemaParamOffset: intSchema(
                description: "Zero-based result offset (default 0)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum documents to return (default 100, maximum 500)."
            ),
        ]

        let listChildrenProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamURI: stringSchema(
                description: "Apple documentation URI or topic-group fragment URI (e.g. apple-docs://swiftui#Essentials)."
            ),
            Shared.Constants.Search.schemaParamSource: stringSchema(
                description: "Source to browse. Default: apple-docs.",
                enumValues: [Shared.Constants.SourcePrefix.appleDocs]
            ),
        ]

        let readSampleProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamProjectId: stringSchema(
                description: "Sample project identifier."
            ),
        ].merging(typedOutputFormatProperties) { lhs, _ in lhs }

        let readSampleFileProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamProjectId: stringSchema(
                description: "Sample project identifier."
            ),
            Shared.Constants.Search.schemaParamFilePath: stringSchema(
                description: "File path relative to the sample project root."
            ),
        ].merging(typedOutputFormatProperties) { lhs, _ in lhs }

        // #1200 — advertise the params `handleListSamples` actually reads.
        // Both are optional; matches the `cupertino list-samples` CLI options.
        let listSamplesProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Filter by framework name (e.g. swiftui, uikit)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 50)."
            ),
        ].merging(typedOutputFormatProperties) { lhs, _ in lhs }

        // #226 — platform-filter schema fragment shared by all 4
        // AST search-style tools. Same shape as the unified `search`
        // tool's existing platform args (CompositeToolProvider.swift:147-161).
        // Applied client-side via Search.PlatformFilter.passes after the
        // existing Search.Index method returns its result list (the
        // helper fetches min_* per result URI in one batched query).
        let platformFilterProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamMinIOS: stringSchema(
                description: "Minimum iOS version filter (e.g. 17.0)."
            ),
            Shared.Constants.Search.schemaParamMinMacOS: stringSchema(
                description: "Minimum macOS version filter (e.g. 14.0)."
            ),
            Shared.Constants.Search.schemaParamMinTvOS: stringSchema(
                description: "Minimum tvOS version filter (e.g. 17.0)."
            ),
            Shared.Constants.Search.schemaParamMinWatchOS: stringSchema(
                description: "Minimum watchOS version filter (e.g. 10.0)."
            ),
            Shared.Constants.Search.schemaParamMinVisionOS: stringSchema(
                description: "Minimum visionOS version filter (e.g. 1.0)."
            ),
        ]

        let searchSymbolsProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamQuery: stringSchema(
                description: "Symbol name pattern (partial match)."
            ),
            Shared.Constants.Search.schemaParamKind: stringSchema(
                description: "Symbol kind filter (struct, class, actor, enum, protocol, function, property)."
            ),
            Shared.Constants.Search.schemaParamIsAsync: boolSchema(
                description: "Filter async functions only."
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework filter (e.g. swiftui, foundation)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 20)."
            ),
        ]
        .merging(platformFilterProperties) { lhs, _ in lhs }
        .merging(typedOutputFormatProperties) { lhs, _ in lhs }

        let searchPropertyWrappersProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamWrapper: stringSchema(
                description: "Property wrapper name (with or without @)."
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework filter (e.g. swiftui, foundation)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 20)."
            ),
        ]
        .merging(platformFilterProperties) { lhs, _ in lhs }
        .merging(typedOutputFormatProperties) { lhs, _ in lhs }

        let searchConcurrencyProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamPattern: stringSchema(
                description: "Concurrency pattern (async, actor, sendable, mainactor, task, asyncsequence)."
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework filter (e.g. swiftui, foundation)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 20)."
            ),
        ]
        .merging(platformFilterProperties) { lhs, _ in lhs }
        .merging(typedOutputFormatProperties) { lhs, _ in lhs }

        let searchConformancesProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamProtocol: stringSchema(
                description: "Protocol name to search for (e.g. View, Codable)."
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework filter (e.g. swiftui, foundation)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 20)."
            ),
        ]
        .merging(platformFilterProperties) { lhs, _ in lhs }
        .merging(typedOutputFormatProperties) { lhs, _ in lhs }

        // #665 / #409 Layer 2 — generic-parameter constraint search.
        // #226 follow-up — `platformFilterProperties` merged in so the 12th
        // MCP tool gets the same `min_*` axis the other 4 AST tools carry.
        let searchGenericsProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: stringSchema(
                description: "Generic constraint to search for (e.g. Sendable, Hashable, View)."
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Framework filter (e.g. swiftui, foundation)."
            ),
            Shared.Constants.Search.schemaParamLimit: intSchema(
                description: "Maximum results to return (default 20)."
            ),
        ]
        .merging(platformFilterProperties) { lhs, _ in lhs }
        .merging(typedOutputFormatProperties) { lhs, _ in lhs }

        // #274 — class-inheritance walk over the `inheritance` edge table.
        let getInheritanceProperties: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamSymbol: stringSchema(
                description: "Symbol name to walk from (e.g. UIButton, NSView)."
            ),
            Shared.Constants.Search.schemaParamDirection: stringSchema(
                description: "Walk direction. 'up' = ancestors (default), 'down' = descendants, 'both'.",
                enumValues: ["up", "down", "both"]
            ),
            Shared.Constants.Search.schemaParamDepth: intSchema(
                description: "Maximum walk depth (default 5)."
            ),
            Shared.Constants.Search.schemaParamFramework: stringSchema(
                description: "Disambiguate to a specific framework when the symbol exists in multiple."
            ),
        ].merging(typedOutputFormatProperties) { lhs, _ in lhs }

        // Unified search tool (replaces search_docs, search_hig, search_all, search_samples).
        // #645 — visible when EITHER search.db is openable (or present-but-
        // unopenable) or samples.db has content. The schema-mismatch path
        // makes searchToolsVisible true even when searchIndex is nil.
        if searchToolsVisible || sampleDatabase != nil {
            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolSearch,
                description: MCP.SharedTools.Copy.toolSearchDescription,
                inputSchema: objectSchema(
                    properties: searchProperties,
                    required: [Shared.Constants.Search.schemaParamQuery]
                )
            ))
        }

        // List frameworks tool (alias for `list` level 1; kept for existing clients).
        if searchToolsVisible {
            let listFrameworksProperties: [String: MCP.Core.Protocols.AnyCodable] = [
                Shared.Constants.Search.schemaParamSource: stringSchema(
                    description: "Source whose frameworks to list. Omit for the global merged list (legacy behaviour). Alias for `list(source, level:1)`.",
                    enumValues: sourceHierarchies.keys.sorted()
                ),
            ]
            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolListFrameworks,
                description: MCP.SharedTools.Copy.toolListFrameworksDescription,
                inputSchema: objectSchema(properties: sourceHierarchies.isEmpty ? [:] : listFrameworksProperties)
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolListDocuments,
                description: MCP.SharedTools.Copy.toolListDocumentsDescription,
                inputSchema: objectSchema(
                    properties: listDocumentsProperties,
                    required: [Shared.Constants.Search.schemaParamFramework]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolListChildren,
                description: MCP.SharedTools.Copy.toolListChildrenDescription,
                inputSchema: objectSchema(
                    properties: listChildrenProperties,
                    required: [Shared.Constants.Search.schemaParamURI]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolReadDocument,
                description: MCP.SharedTools.Copy.toolReadDocumentDescription,
                inputSchema: objectSchema(
                    properties: readDocumentProperties,
                    required: [Shared.Constants.Search.schemaParamURI]
                )
            ))
        }

        // #1311: unified, source-aware hierarchy navigation. Advertised only when the composition
        // root wired the per-source hierarchies (engine-backed), so test doubles that do not wire
        // it are unaffected. `list_frameworks` above remains as a thin alias for `list` level 1.
        if !sourceHierarchies.isEmpty {
            let listProperties: [String: MCP.Core.Protocols.AnyCodable] = [
                Shared.Constants.Search.schemaParamSource: stringSchema(
                    description: "Source to browse.",
                    enumValues: sourceHierarchies.keys.sorted()
                ),
                Shared.Constants.Search.schemaParamLevel: intSchema(
                    description: "1-based level to enumerate. Omit (or 0) to describe the source: depth, the kind at each level, and the leaf content type (markdown/image/pdf/code)."
                ),
                Shared.Constants.Search.schemaParamParent: stringSchema(
                    description: "Parent node from the level above: a framework id at level 2, a node uri at level 3. Omit for level 1."
                ),
                Shared.Constants.Search.schemaParamOffset: intSchema(
                    description: "Zero-based offset for paged levels (default 0)."
                ),
                Shared.Constants.Search.schemaParamLimit: intSchema(
                    description: "Maximum items to return (default 100)."
                ),
            ]
            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolList,
                description: "Navigate a source's documentation hierarchy. `list(source)` (level 0/omitted) returns the source's shape: depth, the kind at each level, and the leaf content type. `list(source, level:1)` lists the top level; `list(source, level:N, parent:…)` lists the next level under a parent (a framework id at level 2, a node uri at level 3). Leaf nodes are read with read_document.",
                inputSchema: objectSchema(
                    properties: listProperties,
                    required: [Shared.Constants.Search.schemaParamSource]
                )
            ))
        }

        // #1277: the installed-source inventory. Independent of the search.db tools (it reports
        // which per-source databases exist even when none are open), so it is gated on its own
        // injected value rather than `searchToolsVisible`.
        if sourceInventory != nil {
            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolListSources,
                description: "List the installed documentation sources (per-source databases), each with on-disk presence and schema version.",
                inputSchema: objectSchema(properties: [:])
            ))
        }

        // Sample code tools
        if sampleDatabase != nil {
            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolListSamples,
                description: MCP.SharedTools.Copy.toolListSamplesDescription,
                inputSchema: objectSchema(properties: listSamplesProperties)
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolReadSample,
                description: MCP.SharedTools.Copy.toolReadSampleDescription,
                inputSchema: objectSchema(
                    properties: readSampleProperties,
                    required: [Shared.Constants.Search.schemaParamProjectId]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolReadSampleFile,
                description: MCP.SharedTools.Copy.toolReadSampleFileDescription,
                inputSchema: objectSchema(
                    properties: readSampleFileProperties,
                    required: [
                        Shared.Constants.Search.schemaParamProjectId,
                        Shared.Constants.Search.schemaParamFilePath,
                    ]
                )
            ))
        }

        // Semantic search tools (#81)
        if searchToolsVisible {
            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolSearchSymbols,
                description: MCP.SharedTools.Copy.toolSearchSymbolsDescription,
                inputSchema: objectSchema(properties: searchSymbolsProperties)
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolSearchPropertyWrappers,
                description: MCP.SharedTools.Copy.toolSearchPropertyWrappersDescription,
                inputSchema: objectSchema(
                    properties: searchPropertyWrappersProperties,
                    required: [Shared.Constants.Search.schemaParamWrapper]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolSearchConcurrency,
                description: MCP.SharedTools.Copy.toolSearchConcurrencyDescription,
                inputSchema: objectSchema(
                    properties: searchConcurrencyProperties,
                    required: [Shared.Constants.Search.schemaParamPattern]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolGetInheritance,
                description: "Walk class-inheritance chains (UIKit / AppKit / Foundation). " +
                    "Returns ancestors (`direction=up`), descendants (`direction=down`), or both. " +
                    "`format=json` returns a typed GUI payload with title-bearing tree nodes. " +
                    "When the walk is empty, the response carries the `_No inheritance data` " +
                    "semantic marker with a kind-aware reason: a class at the root of its " +
                    "hierarchy reads 'Root type'; a protocol directs at `search_conformances`; " +
                    "value types (struct / enum / actor) say 'Swift value type'.",
                inputSchema: objectSchema(
                    properties: getInheritanceProperties,
                    required: [Shared.Constants.Search.schemaParamSymbol]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolSearchConformances,
                description: MCP.SharedTools.Copy.toolSearchConformancesDescription,
                inputSchema: objectSchema(
                    properties: searchConformancesProperties,
                    required: [Shared.Constants.Search.schemaParamProtocol]
                )
            ))

            allTools.append(MCP.Core.Protocols.Tool(
                name: Shared.Constants.Search.toolSearchGenerics,
                description: MCP.SharedTools.Copy.toolSearchGenericsDescription,
                inputSchema: objectSchema(
                    properties: searchGenericsProperties,
                    required: [Shared.Constants.Search.schemaParamConstraint]
                )
            ))
        }

        return MCP.Core.Protocols.ListToolsResult(tools: allTools)
    }

    public func callTool(name: String, arguments: [String: MCP.Core.Protocols.AnyCodable]?) async throws -> MCP.Core.Protocols.CallToolResult {
        let args = MCP.SharedTools.ArgumentExtractor(arguments)

        switch name {
        case Shared.Constants.Search.toolSearch:
            return try await handleSearch(args: args)
        case Shared.Constants.Search.toolList:
            return try await handleList(args: args)
        case Shared.Constants.Search.toolListFrameworks:
            return try await handleListFrameworks(args: args)
        case Shared.Constants.Search.toolListDocuments:
            return try await handleListDocuments(args: args)
        case Shared.Constants.Search.toolListChildren:
            return try await handleListChildren(args: args)
        case Shared.Constants.Search.toolListSources:
            return try await handleListSources()
        case Shared.Constants.Search.toolReadDocument:
            return try await handleReadDocument(args: args)
        case Shared.Constants.Search.toolListSamples:
            return try await handleListSamples(args: args)
        case Shared.Constants.Search.toolReadSample:
            return try await handleReadSample(args: args)
        case Shared.Constants.Search.toolReadSampleFile:
            return try await handleReadSampleFile(args: args)
        case Shared.Constants.Search.toolSearchSymbols:
            return try await handleSearchSymbols(args: args)
        case Shared.Constants.Search.toolSearchPropertyWrappers:
            return try await handleSearchPropertyWrappers(args: args)
        case Shared.Constants.Search.toolSearchConcurrency:
            return try await handleSearchConcurrency(args: args)
        case Shared.Constants.Search.toolSearchConformances:
            return try await handleSearchConformances(args: args)
        case Shared.Constants.Search.toolSearchGenerics:
            return try await handleSearchGenerics(args: args)
        case Shared.Constants.Search.toolGetInheritance:
            return try await handleGetInheritance(args: args)
        default:
            throw Shared.Core.ToolError.unknownTool(name)
        }
    }

    private func objectSchema(
        properties: [String: MCP.Core.Protocols.AnyCodable]?,
        required: [String] = []
    ) -> MCP.Core.Protocols.JSONSchema {
        MCP.Core.Protocols.JSONSchema(
            type: Shared.Constants.Search.schemaTypeObject,
            properties: properties,
            required: required
        )
    }

    private func stringSchema(description: String? = nil, enumValues: [String]? = nil) -> MCP.Core.Protocols.AnyCodable {
        var schema: [String: MCP.Core.Protocols.AnyCodable] = ["type": MCP.Core.Protocols.AnyCodable("string")]
        if let description {
            schema["description"] = MCP.Core.Protocols.AnyCodable(description)
        }
        if let enumValues {
            let values = enumValues.map { MCP.Core.Protocols.AnyCodable($0) }
            schema["enum"] = MCP.Core.Protocols.AnyCodable(values)
        }
        return MCP.Core.Protocols.AnyCodable(schema)
    }

    private func boolSchema(description: String? = nil) -> MCP.Core.Protocols.AnyCodable {
        var schema: [String: MCP.Core.Protocols.AnyCodable] = ["type": MCP.Core.Protocols.AnyCodable("boolean")]
        if let description {
            schema["description"] = MCP.Core.Protocols.AnyCodable(description)
        }
        return MCP.Core.Protocols.AnyCodable(schema)
    }

    private func intSchema(description: String? = nil) -> MCP.Core.Protocols.AnyCodable {
        var schema: [String: MCP.Core.Protocols.AnyCodable] = ["type": MCP.Core.Protocols.AnyCodable("integer")]
        if let description {
            schema["description"] = MCP.Core.Protocols.AnyCodable(description)
        }
        return MCP.Core.Protocols.AnyCodable(schema)
    }

    // MARK: - Unified Search Handler

    private func handleSearch(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        let rawQuery: String = try args.require(Shared.Constants.Search.schemaParamQuery)
        // #596: reject empty / whitespace-only queries with an explicit
        // invalidArgument frame. Pre-fix, MCP returned a 620-char "no
        // results" response for `query=""` while CLI errored — clients
        // had to special-case both transports. Tightened MCP side here
        // so both transports now consistently reject empty queries.
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamQuery,
                "Query cannot be empty"
            )
        }
        let source = args.optional(Shared.Constants.Search.schemaParamSource)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let language = args.optional(Shared.Constants.Search.schemaParamLanguage)
        let limit = args.limit()
        let includeArchive = args.includeArchive()
        // #226 — validate + canonicalise the 5 platform filter values up
        // front so empty / malformed strings get a clear MCP error rather
        // than silently no-oping past `Search.PlatformFilter.passes(...)`.
        // The shipped 5-field shape replaces the original "platform +
        // min_version pair" spec; each `min_*` field is self-naming
        // (platform implied by the field) so the original required-
        // together rule doesn't translate — what we can validate is that
        // each present value is well-formed.
        let platform = try Self.extractPlatformArgs(args)
        let minIOS = platform.minIOS
        let minMacOS = platform.minMacOS
        let minTvOS = platform.minTvOS
        let minWatchOS = platform.minWatchOS
        let minVisionOS = platform.minVisionOS
        // #225 Part B — Swift toolchain filter for swift-evolution rows
        // via docs_metadata.implementation_swift_version. Plumbed
        // through handleSearchDocs → Services.SearchQuery; non-evolution
        // rows are rejected by the index's NULL-rejection semantic when
        // this is set. nil when the MCP arg is absent (filter off).
        let minSwift: String? = args.optional(Shared.Constants.Search.schemaParamMinSwift)
        // `#837` PR-2 — apple-framework-import filter on the packages
        // bucket. Threaded through both the single-source path
        // (`handleSearchPackages`) and the fan-out path
        // (`handleSearchAll` → `Services.UnifiedSearchService.searchAll`).
        // No-op when source is anything other than `packages` (the
        // search.db-backed sources don't carry apple_imports_json).
        let appleImports: String? = args.optional(Shared.Constants.Search.schemaParamAppleImports)

        // #226 — decide the cross-source partial-filter notice before
        // dispatch. The notice prepends to the response markdown when
        // the user passed any platform filter AND the dispatch path
        // produces unfiltered rows. Two cases:
        //
        // 1. Specific-source dispatch (`apple-docs` / `apple-archive` /
        //    `swift-evolution` / `swift-org` / `swift-book` / `packages`
        //    via `handleSearchDocs`) — filter IS applied, no notice.
        //    `hig` / `samples` via the standalone HIG/Samples handlers
        //    DO NOT thread platform args — notice fires.
        //
        // 2. Fan-out dispatch (no source, "all", empty) via
        //    `handleSearchAll` — currently drops platform args for ALL
        //    sources. Notice fires for every contributing source. When
        //    `handleSearchAll` is updated to thread args (filed as
        //    follow-up), the partition switches automatically.
        //
        // The `Search.PlatformFilterScope.Dispatch` enum encodes this
        // path-dependent fact so the helper knows whether to treat all
        // contributing sources as unfiltered (fan-out) or partition
        // them per `dispatchAppliesFilter` (single-source).
        // #1042 Cluster 5 sub-1: thread the registry-derived
        // fan-out source list through PlatformFilterScope.dispatch.
        // `searchToolSourceEnumValues` (sans `"all"` + the
        // appleSampleCode alias) is the production fan-out set
        // assembled by the Serve composition root from
        // makeProductionSourceRegistry().allEnabled. When the init was
        // called without the list (legacy two-arg path), fall back to
        // the historical 8-element literal.
        let fanOutSources = !searchToolSourceEnumValues.isEmpty
            ? searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
            : Search.PlatformFilterScope.allFanOutSources
        let dispatchDecision = Search.PlatformFilterScope.dispatch(for: source, fanOutSources: fanOutSources)
        let notice = Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: Self.platformDescriptions(platform: platform, minSwift: minSwift),
            dispatch: dispatchDecision.kind,
            contributingSources: dispatchDecision.sources
        )

        // 2026-05-26 audit Finding 14.4: dispatch via
        // `Search.SourceProvider.searchRoute` instead of switching on
        // source-id literals. Pre-fix this switch hardcoded 9 source
        // ids; adding a new source required editing this file. The
        // route map is wired at Serve composition root from
        // `registry.allEnabled.reduce { $0[$1.definition.id] =
        // $1.provider.searchRoute }` so a new source plugs in by
        // declaring its searchRoute and the dispatcher finds it.
        //
        // Legacy alias `apple-sample-code` is aliased to `samples`
        // (one-DB-two-tracks per the SampleCodeSource design).
        // Empty source / "all" / unrecognised → unified fan-out.
        let raw: MCP.Core.Protocols.CallToolResult
        let canonicalSourceID = source == Shared.Constants.SourcePrefix.appleSampleCode
            ? Shared.Constants.SourcePrefix.samples
            : source
        let route = canonicalSourceID.flatMap { searchToolRoutesByID[$0] } ?? .unified
        // 2026-05-26 audit #1055 layer-2: SearchRoute is now an open
        // RawRepresentable struct. Dispatch via `==` equality chains
        // so an unrecognised route falls through to the unified
        // fan-out. Adding a new bucket-tier route is a `static let`
        // declaration in `Search.SearchRoute` plus a single new
        // `else if` arm here (and the matching CLI arm); the dispatch
        // never breaks on a missing case.
        if route == .samples {
            raw = try await handleSearchSamples(
                query: query,
                framework: framework,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS
            )
        } else if route == .hig {
            raw = try await handleSearchHIG(
                query: query,
                framework: framework,
                limit: limit
            )
        } else if route == .docs {
            // Specific docs-tier source requested: search only that source
            raw = try await handleSearchDocs(
                query: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )
        } else if route == .packages {
            // `#789`-style fix: packages live in `packages.db` with a
            // richer schema (BM25 + chunk + apple_imports_json); the
            // pre-PR-2 fall-through to `handleSearchDocs(source:"packages")`
            // returned zero rows because `search.db` doesn't carry the
            // `packages` source value. Route to the dedicated handler.
            raw = try await handleSearchPackages(
                query: query,
                framework: framework,
                limit: limit,
                appleImports: appleImports
            )
        } else {
            // Default (nil source / "all" / future registered sources
            // whose searchRoute is .unified): search ALL sources for comprehensive results
            raw = try await handleSearchAll(
                query: query,
                framework: framework,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift,
                appleImports: appleImports
            )
        }
        return Self.prependNoticeIfNeeded(notice: notice, to: raw)
    }

    /// #226 — format a per-platform description list (e.g. `["min_ios=18.0",
    /// "min_macos=14.0"]`) for the notice prefix. Includes the `--swift`
    /// filter when set; pre-#226 it lived in #225 Part B's filter and the
    /// notice ignored it.
    private static func platformDescriptions(
        platform: PlatformArgs,
        minSwift: String?
    ) -> [String] {
        var out: [String] = []
        if let value = platform.minIOS { out.append("min_ios=\(value)") }
        if let value = platform.minMacOS { out.append("min_macos=\(value)") }
        if let value = platform.minTvOS { out.append("min_tvos=\(value)") }
        if let value = platform.minWatchOS { out.append("min_watchos=\(value)") }
        if let value = platform.minVisionOS { out.append("min_visionos=\(value)") }
        if let value = minSwift { out.append("min_swift=\(value)") }
        return out
    }

    /// #226 — prepend the notice markdown to the first text-content block
    /// of a `CallToolResult`. No-op when notice is nil or the result has
    /// no text content. Returns a new result rather than mutating.
    static func prependNoticeIfNeeded(
        notice: String?,
        to result: MCP.Core.Protocols.CallToolResult
    ) -> MCP.Core.Protocols.CallToolResult {
        guard let notice else { return result }
        let newContent: [MCP.Core.Protocols.ContentBlock] = result.content.enumerated().map { idx, block in
            guard idx == 0, case let .text(textContent) = block else { return block }
            return .text(MCP.Core.Protocols.TextContent(text: notice + textContent.text))
        }
        return MCP.Core.Protocols.CallToolResult(content: newContent, isError: result.isError)
    }

    // MARK: - Documentation Search

    private func handleSearchDocs(
        query: String,
        source: String?,
        framework: String?,
        language: String?,
        limit: Int,
        includeArchive: Bool,
        minIOS: String?,
        minMacOS: String?,
        minTvOS: String?,
        minWatchOS: String?,
        minVisionOS: String?,
        minSwift: String?
    ) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let docsService else {
            throw Shared.Core.ToolError.invalidArgument("source", "Documentation index not available")
        }

        // Use service layer (same as CLI)
        let results = try await docsService.search(Services.SearchQuery(
            text: query,
            source: source,
            framework: framework,
            language: language,
            limit: limit,
            includeArchive: includeArchive,
            minimumiOS: minIOS,
            minimumMacOS: minMacOS,
            minimumTvOS: minTvOS,
            minimumWatchOS: minWatchOS,
            minimumVisionOS: minVisionOS,
            minimumSwift: minSwift
        ))

        // Fetch teaser results from all sources user didn't search
        let teasers = await fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: source,
            includeArchive: includeArchive
        )

        // Use shared formatter
        let filters = Services.SearchFilters(
            source: source,
            framework: framework,
            language: language,
            minimumiOS: minIOS,
            minimumMacOS: minMacOS,
            minimumTvOS: minTvOS,
            minimumWatchOS: minWatchOS,
            minimumVisionOS: minVisionOS
        )

        // #976: was `Services.Formatter.Config.mcpDefault`; the static
        // was removed as a Rule 1 Service Locator. `makeStandardConfig`
        // is a private factory on this actor (Rule 1 carve-out: internal
        // helper, not a Service Locator reachable from outside).
        var config = Self.makeStandardConfig()
        if results.isEmpty, !includeArchive, source != Shared.Constants.SourcePrefix.appleArchive {
            config = Services.Formatter.Config(
                showScore: true,
                showWordCount: true,
                showSource: false,
                showAvailability: true,
                showSeparators: true,
                emptyMessage: Shared.Constants.Search.messageNoResults + "\n\n" + Shared.Constants.Search.tipTryArchive
            )
        }

        // #1045 Gap 2 wiring: registry-derived source-id list for the
        // formatter's footer tips. Strip "all" and the appleSampleCode
        // alias the schema enum carries but the formatter doesn't display.
        let docsAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        let formatter = Services.Formatter.Markdown(
            query: query,
            filters: filters,
            config: config,
            teasers: teasers,
            availableSources: docsAvailableSources
        )
        let markdown = formatter.format(results)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - Teaser Results

    // Uses shared Services.TeaserService from Services module

    /// Fetch teaser results from all sources the user didn't search
    private func fetchAllTeasers(
        query: String,
        framework: String?,
        currentSource: String?,
        includeArchive: Bool
    ) async -> Services.Formatter.TeaserResults {
        guard let teaserService else { return Services.Formatter.TeaserResults() }
        return await teaserService.fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: currentSource,
            includeArchive: includeArchive
        )
    }

    // MARK: - Sample Code Search

    private func handleSearchSamples(
        query: String,
        framework: String?,
        limit: Int,
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil
    ) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let sampleService else {
            throw sampleDatabaseUnavailableError("source")
        }

        // #732 — pass the 5-field shape natively into `Sample.Search.Query`.
        // Multiple `min_*` values AND-combine inside
        // `Sample.Index.Database.searchProjects` SQL: a project must
        // satisfy every requested minimum to pass. #226's precedence-
        // pick translation (then needed because `searchProjects` only
        // had `(platform, minVersion)`) is gone — the 5-field path is
        // end-to-end now.
        let result = try await sampleService.search(Sample.Search.Query(
            text: query,
            framework: framework,
            searchFiles: true,
            limit: limit,
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS
        ))

        // Fetch teaser results from other sources
        let teasers = await fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: Shared.Constants.SourcePrefix.samples,
            includeArchive: false
        )

        // Use shared formatter — #1045 Gap 2 wiring.
        let samplesAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        let formatter = Sample.Format.Markdown.Search(
            query: query,
            framework: framework,
            teasers: teasers,
            availableSources: samplesAvailableSources
        )
        let markdown = formatter.format(result)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - Packages Search (packages.db)

    /// `#789`-style architectural gap fix. Pre-PR-2, MCP
    /// `search source=packages` fell through the docs path against
    /// `search.db`, which never carries the `packages` source value, so
    /// every query returned zero rows. This handler routes through the
    /// dedicated `Search.PackagesSearcher` seam against `packages.db`
    /// (which has the rich `package_metadata` + `package_files` +
    /// `package_symbols` schema). The `--apple-imports` filter applies
    /// here too. Result formatting reuses
    /// `Services.Formatter.Markdown` so the output shape matches the
    /// docs and HIG handlers; the `packages` source label naturally
    /// flows through `Search.Result.source`.
    private func handleSearchPackages(
        query: String,
        framework: String?,
        limit: Int,
        appleImports: String?
    ) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let packagesSearcher else {
            // Composition root didn't wire a `packages.db`-backed
            // searcher (file missing, schema mismatch handled at open
            // time, or test bootstrap took the legacy two-arg init).
            // Fall back to the pre-PR-2 path against `Search.Database`:
            // production search.db doesn't carry `packages` source rows
            // so this returns empty for real users (matching the
            // historical zero-result behaviour). Test fixtures that
            // synthesise `source = packages` rows in search.db continue
            // to be served by the legacy path. `apple_imports` is
            // dropped on the fallback — search.db has no
            // `apple_imports_json` column to filter against.
            return try await handleSearchDocs(
                query: query,
                source: Shared.Constants.SourcePrefix.packages,
                framework: framework,
                language: nil,
                limit: limit,
                includeArchive: false,
                minIOS: nil,
                minMacOS: nil,
                minTvOS: nil,
                minWatchOS: nil,
                minVisionOS: nil,
                minSwift: nil
            )
        }

        let results = try await packagesSearcher.searchPackages(
            query: query,
            limit: limit,
            availability: nil,
            swiftTools: nil,
            appleImport: appleImports
        )

        let teasers = await fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: Shared.Constants.SourcePrefix.packages,
            includeArchive: false
        )

        let filters = Services.SearchFilters(
            source: Shared.Constants.SourcePrefix.packages,
            framework: framework,
            language: nil,
            minimumiOS: nil,
            minimumMacOS: nil,
            minimumTvOS: nil,
            minimumWatchOS: nil,
            minimumVisionOS: nil
        )
        // #1045 Gap 2 wiring: registry-derived source-id list.
        let packagesAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        let formatter = Services.Formatter.Markdown(
            query: query,
            filters: filters,
            config: Self.makeStandardConfig(),
            teasers: teasers,
            availableSources: packagesAvailableSources
        )
        let markdown = formatter.format(results)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - HIG Search

    private func handleSearchHIG(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let docsService else {
            throw Shared.Core.ToolError.invalidArgument("source", "Documentation index not available")
        }

        // Use service layer (same as CLI)
        let results = try await docsService.search(Services.SearchQuery(
            text: query,
            source: Shared.Constants.SourcePrefix.hig,
            framework: framework,
            language: nil,
            limit: limit,
            includeArchive: false
        ))

        // Fetch teaser results from other sources
        let teasers = await fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: Shared.Constants.SourcePrefix.hig,
            includeArchive: false
        )

        // Use shared formatter — #1045 Gap 2 wiring: thread registry-
        // derived source-id list (sans "all" / appleSampleCode alias)
        // into the formatter so the footer's "narrow with --source" tip
        // reflects every registered source.
        let higQuery = Services.HIGQuery(text: query, platform: nil, category: nil)
        let higAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        let formatter = Services.Formatter.HIG.Markdown(
            query: higQuery,
            config: Self.makeStandardConfig(),
            teasers: teasers,
            availableSources: higAvailableSources
        )
        let markdown = formatter.format(results)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - Unified Search (All Sources)

    private func handleSearchAll(
        query: String,
        framework: String?,
        limit: Int,
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil,
        minSwift: String? = nil,
        appleImports: String? = nil
    ) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let unifiedService else {
            throw Shared.Core.ToolError.invalidArgument("source", "No indexes available for unified search")
        }
        // #226 expansion: thread platform args + minSwift through the
        // fan-out so each search.db-backed fetcher applies the filter at
        // SQL time. Samples within the fan-out remain unfiltered until
        // the #732 follow-up extends `Sample.Index.Database.searchProjects`
        // — `PlatformFilterScope` partitions samples into the unaware
        // bucket so the partial-filter notice still fires for fan-out +
        // platform args (see `handleSearch` line 535).
        //
        // `#837` PR-2 expansion: `appleImports` is threaded into the
        // packages bucket only. The other 7 sources ignore it.
        // #1042 Cluster 2 wiring (Services path): thread the registry-
        // derived source-id list through to the formatter input so a
        // registered new source appears in the "Searched ALL sources"
        // header + the footer tip.
        let unifiedAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        let rawInput = await unifiedService.searchAll(
            query: query,
            framework: framework,
            limit: limit,
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS,
            minSwift: minSwift,
            appleImports: appleImports,
            availableSources: unifiedAvailableSources
        )

        // #648 (open-time path) — main's post-#642 retest found that the
        // existing `classifyDegradation` plumbing only fires for per-
        // fetcher errors thrown at query time. When `search.db` fails
        // to open at server startup (#645's path), `unifiedService` is
        // constructed with `searchIndex: nil`; the apple-docs / hig /
        // swift-evolution / apple-archive / swift-org / swift-book
        // fetchers register as unavailable and are never called for
        // the query, so no per-fetcher throw exists to classify and
        // `degradedSources` stays empty. The renderer then claims
        // `_Searched ALL sources_` while in fact only samples + packages
        // ran. Bridge the gap here: when `searchIndexDisabledReason` is
        // set on the provider, synthesise one `DegradedSource` per
        // search.db-backed source and merge them into the formatter
        // input. The Markdown / Text / JSON renderers already gate the
        // warning blockquote + "Searched: <list>" line off
        // `degradedSources`, so the same render path now triggers for
        // the open-time path with no formatter changes.
        let input = Self.injectOpenTimeDegradation(
            into: rawInput,
            disabledReason: searchIndexDisabledReason,
            searchToolSourceEnumValues: searchToolSourceEnumValues
        )

        // Use shared formatter (identical to CLI --format markdown output)
        let formatter = Services.Formatter.Unified.Markdown(
            query: query,
            framework: framework,
            config: Self.makeStandardConfig()
        )
        let markdown = formatter.format(input)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    /// #648 — merge synthetic `DegradedSource` entries for each search.db-
    /// backed source into the formatter input when `disabledReason` is
    /// set. Pure function; no provider state captured beyond the
    /// parameters. Lifted to an internal static so the tests pin the
    /// merge logic (preserved-fields, source-list, dedup-against-existing-
    /// entries) without standing up the full `handleSearchAll` pipeline.
    static func injectOpenTimeDegradation(
        into input: Services.Formatter.Unified.Input,
        disabledReason: String?,
        searchToolSourceEnumValues: [String] = []
    ) -> Services.Formatter.Unified.Input {
        guard let disabledReason else { return input }

        // The 6 sources backed by `search.db`. `samples` (samples.db) and
        // `packages` (packages.db) live in different DBs and aren't
        // affected by `search.db` being closed, so they stay out of the
        // synthesized degraded list.
        let dbSources: [String] = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ]

        // Dedup against anything the per-fetcher classifier already
        // populated (in practice it won't have, because fetchers don't
        // even run when `searchIndex` is nil — but a future refactor
        // that wires partial-fetcher availability shouldn't double-
        // count).
        let existing = Set(input.degradedSources.map(\.name))
        let synthesised = dbSources
            .filter { !existing.contains($0) }
            .map { Search.DegradedSource(name: $0, reason: disabledReason) }

        // #1042 Cluster 2 wiring (MCP path): thread the registry-derived
        // source-id list through to the formatter so a registered new
        // source appears in the "Searched ALL sources" header + the
        // footer tip. Strip the "all" + appleSampleCode alias tokens
        // the schema enum carries but the formatter doesn't display.
        let formatterAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        return Services.Formatter.Unified.Input(
            docResults: input.docResults,
            archiveResults: input.archiveResults,
            sampleResults: input.sampleResults,
            higResults: input.higResults,
            swiftEvolutionResults: input.swiftEvolutionResults,
            swiftOrgResults: input.swiftOrgResults,
            swiftBookResults: input.swiftBookResults,
            packagesResults: input.packagesResults,
            availableSources: formatterAvailableSources,
            limit: input.limit,
            degradedSources: input.degradedSources + synthesised
        )
    }

    // MARK: - Unified list (#1311)

    /// Level-0 (`list(source)`) payload: the source's self-described hierarchy.
    private struct ListDescribeResult: Encodable {
        let source: String
        let kind: String // always "describe"
        let depth: Int
        let leafContentType: String
        let levels: [Level]
        struct Level: Encodable { let level: Int; let kind: String; let isLeaf: Bool }
    }

    /// One node at a level. `count` is the document count for level-1 framework rows; nil otherwise.
    private struct ListItem: Encodable {
        let id: String
        let title: String
        let kind: String
        let hasChildren: Bool
        let count: Int?
    }

    /// Level-N (`list(source, level:N, parent:…)`) payload: a paged window of nodes.
    private struct ListPageResult: Encodable {
        let source: String
        let level: Int
        let levelKind: String
        let isLeafLevel: Bool
        let parent: String?
        let offset: Int
        let limit: Int
        let total: Int
        let items: [ListItem]
    }

    private func listJSON(_ value: some Encodable) throws -> MCP.Core.Protocols.CallToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = String(decoding: try encoder.encode(value), as: UTF8.self)
        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: json))])
    }

    private func browsingUnavailableError() -> any Error {
        Shared.Core.ToolError.invalidArgument("index", "Documentation index does not support document browsing")
    }

    /// The single, source-aware hierarchy navigator. Level 0 (or omitted) describes the source;
    /// level 1 lists the top level (per-source frameworks); level 2 lists a framework's documents;
    /// level >= 3 lists a node's children. Everything routes through the source's declared
    /// `Search.SourceHierarchy` and the engine's per-source readers, so nothing is hardcoded.
    private func handleList(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        let source = try args.require(Shared.Constants.Search.schemaParamSource)
        guard let hierarchy = sourceHierarchies[source] else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamSource,
                "Unknown source '\(source)'. Known: \(sourceHierarchies.keys.sorted().joined(separator: ", "))."
            )
        }

        let level = args.optional(Shared.Constants.Search.schemaParamLevel, default: 0)

        // Level 0 / omitted: describe the source's shape.
        if level <= 0 {
            return try listJSON(ListDescribeResult(
                source: source,
                kind: "describe",
                depth: hierarchy.depth,
                leafContentType: hierarchy.leafContentType.rawValue,
                levels: hierarchy.levels.map { .init(level: $0.level, kind: $0.kind, isLeaf: $0.isLeaf) }
            ))
        }

        // Catalog sources (samples, packages): entries + a file tree, not framework -> doc -> topic.
        // Their tree is arbitrary depth, so they skip the fixed-depth guard and walk by node URI.
        if catalogSources.contains(source) {
            return try await handleCatalogList(source: source, hierarchy: hierarchy, level: level, args: args)
        }

        guard level <= hierarchy.depth else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamLevel,
                "Source '\(source)' has depth \(hierarchy.depth); level \(level) is out of range."
            )
        }

        let levelSpec = hierarchy.levels.first { $0.level == level }
        let levelKind = levelSpec?.kind ?? ""
        let isLeafLevel = levelSpec?.isLeaf ?? (level >= hierarchy.depth)
        let parent = args.optional(Shared.Constants.Search.schemaParamParent) ?? ""
        let offset = max(args.optional(Shared.Constants.Search.schemaParamOffset, default: 0), 0)
        let limit = min(
            max(args.optional(Shared.Constants.Search.schemaParamLimit, default: Shared.Constants.Limit.defaultDocumentListLimit), 0),
            Shared.Constants.Limit.maxDocumentListLimit
        )

        switch level {
        case 1:
            // Top level: this source's OWN frameworks (per-source, not the global merged list).
            guard let sourceFrameworks else {
                throw Shared.Core.ToolError.invalidArgument("index", "This server does not support per-source level-1 listing")
            }
            let all = try await sourceFrameworks(source)
                .sorted { $0.key < $1.key }
                .map { ListItem(id: $0.key, title: $0.key, kind: levelKind, hasChildren: !isLeafLevel, count: $0.value) }
            let windowed = Array(all.dropFirst(offset).prefix(limit))
            return try listJSON(ListPageResult(
                source: source, level: 1, levelKind: levelKind, isLeafLevel: isLeafLevel,
                parent: nil, offset: offset, limit: limit, total: all.count, items: windowed
            ))

        case 2:
            // A framework's documents.
            guard let documentBrowsing else { throw browsingUnavailableError() }
            guard !parent.isEmpty else {
                throw Shared.Core.ToolError.invalidArgument(Shared.Constants.Search.schemaParamParent, "level 2 requires `parent` (a level-1 id, e.g. a framework).")
            }
            let page = try await documentBrowsing.listDocuments(source: source, framework: parent, offset: offset, limit: limit)
            let items = page.documents.map {
                ListItem(id: $0.uri, title: $0.title, kind: $0.kind.isEmpty ? levelKind : $0.kind, hasChildren: !isLeafLevel, count: nil)
            }
            return try listJSON(ListPageResult(
                source: source, level: 2, levelKind: levelKind, isLeafLevel: isLeafLevel,
                parent: parent, offset: page.offset, limit: page.limit, total: page.total, items: items
            ))

        default:
            // level >= 3: a node's children (the topic-group / outline tree).
            guard let documentBrowsing else { throw browsingUnavailableError() }
            guard !parent.isEmpty else {
                throw Shared.Core.ToolError.invalidArgument(Shared.Constants.Search.schemaParamParent, "level \(level) requires `parent` (a node uri from the level above).")
            }
            let page = try await documentBrowsing.listChildren(source: source, uri: parent)
            let all = page.children.map {
                ListItem(id: $0.uri, title: $0.title, kind: $0.kind, hasChildren: $0.hasChildren, count: nil)
            }
            let windowed = Array(all.dropFirst(offset).prefix(limit))
            return try listJSON(ListPageResult(
                source: source, level: level, levelKind: levelKind, isLeafLevel: isLeafLevel,
                parent: parent, offset: offset, limit: limit, total: all.count, items: windowed
            ))
        }
    }

    // MARK: - List Frameworks (alias for `list` level 1)

    /// Back-compat alias for `list(source, level:1)`. Kept because existing MCP clients call
    /// `list_frameworks` directly. Now source-aware (#1311): when a `source` is given and the
    /// per-source lister is wired, it lists THAT source's frameworks (fixing the source-blind
    /// leftover); with no `source` it falls back to the global merged list as before, so callers
    /// that never passed a source keep their behaviour and output shape (markdown).
    /// `list` for a catalog source (samples, packages): level 1 enumerates entries (every project /
    /// every package, paged across the whole corpus), and levels 2..N walk one entry's file tree by
    /// node URI. At level 2 `parent` is a bare entry id (`sample-nav`); deeper it is a node URI
    /// (`samples://sample-nav/Sources`). Directories report `hasChildren`; files are leaves. The
    /// tree is arbitrary depth, so there is no fixed-depth ceiling.
    private func handleCatalogList(
        source: String,
        hierarchy: Search.SourceHierarchy,
        level: Int,
        args: MCP.SharedTools.ArgumentExtractor
    ) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let catalogEntries, let catalogChildren else { throw browsingUnavailableError() }
        let offset = max(args.optional(Shared.Constants.Search.schemaParamOffset, default: 0), 0)
        let limit = min(
            max(args.optional(Shared.Constants.Search.schemaParamLimit, default: Shared.Constants.Limit.defaultDocumentListLimit), 0),
            Shared.Constants.Limit.maxDocumentListLimit
        )
        let parent = args.optional(Shared.Constants.Search.schemaParamParent) ?? ""
        let entryKind = hierarchy.levels.first { $0.level == 1 }?.kind ?? "entry"

        if level == 1 {
            let page = try await catalogEntries(source, offset, limit)
            let items = page.entries.map {
                ListItem(id: $0.id, title: $0.title, kind: entryKind, hasChildren: true, count: $0.fileCount)
            }
            return try listJSON(ListPageResult(
                source: source, level: 1, levelKind: entryKind, isLeafLevel: false,
                parent: nil, offset: page.offset, limit: page.limit, total: page.total, items: items
            ))
        }

        guard !parent.isEmpty else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamParent,
                "level \(level) requires `parent` (a level-1 entry id, or a node uri from the level above)."
            )
        }
        // Level 2's parent is a bare entry id; deeper levels pass a full node URI.
        let parentURI = parent.contains("://") ? parent : "\(source)://\(parent)"
        let all = try await catalogChildren(source, parentURI).map {
            ListItem(id: $0.uri, title: $0.name, kind: $0.isDirectory ? "directory" : "file", hasChildren: $0.isDirectory, count: nil)
        }
        let windowed = Array(all.dropFirst(offset).prefix(limit))
        let levelKind = hierarchy.levels.first { $0.level == level }?.kind ?? "node"
        return try listJSON(ListPageResult(
            source: source, level: level, levelKind: levelKind, isLeafLevel: false,
            parent: parent, offset: offset, limit: limit, total: all.count, items: windowed
        ))
    }

    private func handleListFrameworks(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let requestedSource = args.optional(Shared.Constants.Search.schemaParamSource)
        let frameworks: [String: Int]
        if let requestedSource, !requestedSource.isEmpty, let sourceFrameworks {
            frameworks = try await sourceFrameworks(requestedSource)
        } else {
            frameworks = try await searchIndex.listFrameworks()
        }
        let totalDocs = try await searchIndex.documentCount()

        // #1045 Gap 2 wiring: registry-derived source-id list.
        let frameworksAvailableSources: [String] = searchToolSourceEnumValues.isEmpty
            ? []
            : searchToolSourceEnumValues.filter { id in
                id != "all" && id != Shared.Constants.SourcePrefix.appleSampleCode
            }
        let formatter = Services.Formatter.Frameworks.Markdown(
            totalDocs: totalDocs,
            availableSources: frameworksAvailableSources
        )
        let markdown = formatter.format(frameworks)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - List Documents

    private func handleListDocuments(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard searchIndex != nil else {
            throw searchIndexUnavailableError("index")
        }
        // Pluggability: route through the engine-backed browser (a reader per source) so
        // list_documents serves ALL sources, not just apple-docs.
        guard let listing = documentBrowsing else {
            throw Shared.Core.ToolError.invalidArgument(
                "index",
                "Documentation index does not support document listing"
            )
        }

        let framework: String = try args.require(Shared.Constants.Search.schemaParamFramework)
        let source = args.optional(
            Shared.Constants.Search.schemaParamSource,
            default: Shared.Constants.SourcePrefix.appleDocs
        )

        let offset = max(args.optional(Shared.Constants.Search.schemaParamOffset, default: 0), 0)
        let requestedLimit = args.optional(
            Shared.Constants.Search.schemaParamLimit,
            default: Shared.Constants.Limit.defaultDocumentListLimit
        )
        let limit = min(max(requestedLimit, 0), Shared.Constants.Limit.maxDocumentListLimit)
        let page = try await listing.listDocuments(
            source: source,
            framework: framework,
            offset: offset,
            limit: limit
        )
        let json = Services.Formatter.Documents.JSON().format(page)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: json))])
    }

    // MARK: - List Children

    private func handleListChildren(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard searchIndex != nil else {
            throw searchIndexUnavailableError("index")
        }
        // #50 / pluggability: delegate to the engine-backed browser the composition root injects.
        // It has a reader per source, so children listing works for ALL sources, not just
        // apple-docs (the previous hardcoded guard is gone).
        guard let listing = documentBrowsing else {
            throw Shared.Core.ToolError.invalidArgument(
                "index",
                "Documentation index does not support document children listing"
            )
        }

        let uri: String = try args.require(Shared.Constants.Search.schemaParamURI)
        let source = args.optional(
            Shared.Constants.Search.schemaParamSource,
            default: Shared.Constants.SourcePrefix.appleDocs
        )

        let page = try await listing.listChildren(source: source, uri: uri)
        let json = Services.Formatter.DocumentChildren.JSON().format(page)

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: json))])
    }

    // MARK: - List Sources (#1277)

    /// Return the injected active-source inventory as JSON: the per-source databases the server
    /// declares, each with on-disk presence and schema version, so a client can detect a missing
    /// or partial corpus and guide setup. Advertised only when the composition root injected the
    /// inventory, so this is non-nil here.
    private func handleListSources() async throws -> MCP.Core.Protocols.CallToolResult {
        guard let sourceInventory else {
            throw Shared.Core.ToolError.invalidArgument("index", "Source inventory is not available")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json: String = if let data = try? encoder.encode(sourceInventory),
                              let text = String(data: data, encoding: .utf8) {
            text
        } else {
            #"{"sources":[]}"#
        }
        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: json))])
    }

    // MARK: - Read Document

    private func handleReadDocument(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let rawURI: String = try args.require(Shared.Constants.Search.schemaParamURI)
        // #587: accept canonical Apple Developer web URLs by converting
        // them to `apple-docs://...` before search.db lookup, matching
        // CLI `cupertino read`'s entry-point normalisation. Users
        // and AI agents routinely pass web URLs through MCP; rejecting
        // them at the boundary forced clients to learn the URI scheme.
        let uri = Self.normalizeReadDocumentURI(rawURI)
        let formatString = args.format()
        let format: Search.DocumentFormat = formatString == Shared.Constants.Search.formatValueMarkdown
            ? .markdown : .json

        if let documentContent = try await searchIndex.getDocumentContent(uri: uri, format: format) {
            let tagged = format == .json ? taggedWithContentType(documentContent, uri: uri) : documentContent
            return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: tagged))])
        }

        // #582: search-index direct lookup missed. Fall back through the
        // same path `resources/read` uses (filesystem read of the
        // crawled JSON / MD under `<outputDirectory>/<framework>/`).
        // Pre-fix the two paths were asymmetric and the tool failed for
        // URIs the resource path accepted (typical with bundles whose
        // indexer-written URIs use the pre-#293 `.lastPathComponent`
        // shape while the resource-list URI generator already used
        // `URLUtilities.filename(from:)`).
        if let provider = documentResourceProvider {
            let result = try await provider.readResource(uri: uri)
            if let firstText = result.contents.compactMap({ contents -> String? in
                if case .text(let textContents) = contents {
                    return textContents.text
                }
                return nil
            }).first {
                return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: firstText))])
            }
        }

        throw Shared.Core.ToolError.invalidArgument(
            Shared.Constants.Search.schemaParamURI,
            "Document not found: \(uri)"
        )
    }

    /// #1312: tag a JSON `read_document` payload with the leaf `contentType` (markdown/image/pdf/
    /// code) declared by the URI's source, so a client knows how to render it. Additive: an existing
    /// consumer that ignores the field is unaffected; the markdown format is never touched. Derived
    /// from the source's `Search.SourceHierarchy.leafContentType`, falling back to markdown when the
    /// source is unknown or hierarchies were not wired.
    private func taggedWithContentType(_ json: String, uri: String) -> String {
        guard let scheme = uri.range(of: "://").map({ String(uri[uri.startIndex ..< $0.lowerBound]) }) else { return json }
        let leaf = sourceHierarchies[scheme]?.leafContentType ?? .markdown
        guard let data = json.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return json }
        object["contentType"] = leaf.rawValue
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]),
              let string = String(data: out, encoding: .utf8)
        else { return json }
        return string
    }

    // MARK: - Read Document — URI normalisation (#587)

    /// Convert a canonical Apple Developer web URL into the lossless
    /// `apple-docs://...` URI shape; pass anything else through unchanged.
    /// Mirrors `Services.ReadService.normalizeIdentifier` so CLI `cupertino
    /// read` and MCP `read_document` accept the same input shapes.
    static func normalizeReadDocumentURI(_ raw: String) -> String {
        guard raw.hasPrefix("https://") || raw.hasPrefix("http://") else {
            return raw
        }
        guard let url = URL(string: raw),
              let uri = Shared.Models.URLUtilities.appleDocsURI(from: url)
        else {
            return raw
        }
        return uri
    }

    // MARK: - Sample Code Tools

    private func handleListSamples(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let sampleDatabase else {
            throw sampleDatabaseUnavailableError("database")
        }

        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit(default: 50)
        let format = try Self.mcpToolOutputFormat(args: args)

        let projects = try await sampleDatabase.listProjects(framework: framework, limit: limit)
        let totalProjects = try await sampleDatabase.projectCount()
        let totalFiles = try await sampleDatabase.fileCount()

        if format == .json {
            let json = Self.formatListSamplesJSON(
                projects: projects,
                totalProjects: totalProjects,
                totalFiles: totalFiles,
                framework: framework,
                limit: limit
            )
            return Self.textResult(json)
        }

        var markdown = "# Indexed Sample Code Projects\n\n"
        markdown += "Total projects: **\(totalProjects)**\n"
        markdown += "Total files: **\(totalFiles)**\n\n"

        if let framework {
            markdown += "_Filtered to framework: **\(framework)**_\n\n"
        }

        if projects.isEmpty {
            markdown += "_No projects found. Run `cupertino save --source samples` to index sample code._\n"
        } else {
            markdown += "| Project | Framework | Files |\n"
            markdown += "|---------|-----------|------:|\n"

            for project in projects {
                let frameworks = project.frameworks.joined(separator: ", ")
                markdown += "| `\(project.id)` | \(frameworks) | \(project.fileCount) |\n"
            }

            markdown += "\n"
            markdown += "💡 **Tip:** Use `search` with `source: samples` to find projects by keyword."
            markdown += "\n"
        }

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    private func handleReadSample(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let sampleDatabase else {
            throw sampleDatabaseUnavailableError("database")
        }

        let projectId: String = try args.require(Shared.Constants.Search.schemaParamProjectId)
        let format = try Self.mcpToolOutputFormat(args: args)

        guard let project = try await sampleDatabase.getProject(id: projectId) else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamProjectId,
                "Project not found: \(projectId)"
            )
        }

        let files = try await sampleDatabase.listFiles(projectId: projectId, folder: nil)
        if format == .json {
            return Self.textResult(Self.formatReadSampleJSON(project: project, files: files))
        }

        var markdown = "# \(project.title)\n\n"
        markdown += "**Project ID:** `\(project.id)`\n\n"

        if !project.description.isEmpty {
            markdown += "## Description\n\n"
            markdown += project.description + "\n\n"
        }

        markdown += "## Metadata\n\n"
        markdown += "- **Frameworks:** \(project.frameworks.joined(separator: ", "))\n"
        markdown += "- **Files:** \(project.fileCount)\n"
        markdown += "- **Size:** \(Shared.Utils.Formatting.formatBytes(project.totalSize))\n"
        if !project.webURL.isEmpty {
            markdown += "- **Apple Developer:** \(project.webURL)\n"
        }
        markdown += "\n"

        if let readme = project.readme, !readme.isEmpty {
            markdown += "## README\n\n"
            markdown += readme
            markdown += "\n\n"
        }

        if !files.isEmpty {
            markdown += "## Files (\(files.count) total)\n\n"
            for file in files.prefix(30) {
                markdown += "- `\(file.path)`\n"
            }
            if files.count > 30 {
                markdown += "- _... and \(files.count - 30) more files_\n"
            }
            markdown += "\n"
            markdown += "💡 Use `read_sample_file` with project_id and file_path to view source code.\n"
        }

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    private func handleReadSampleFile(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let sampleDatabase else {
            throw sampleDatabaseUnavailableError("database")
        }

        let projectId: String = try args.require(Shared.Constants.Search.schemaParamProjectId)
        let filePath: String = try args.require(Shared.Constants.Search.schemaParamFilePath)
        let format = try Self.mcpToolOutputFormat(args: args)

        guard let file = try await sampleDatabase.getFile(projectId: projectId, path: filePath) else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamFilePath,
                "File not found: \(filePath) in project \(projectId)"
            )
        }

        let language = languageForExtension(file.fileExtension)
        if format == .json {
            return Self.textResult(Self.formatReadSampleFileJSON(file: file, language: language))
        }

        var markdown = "# \(file.filename)\n\n"
        markdown += "**Project:** `\(file.projectId)`\n"
        markdown += "**Path:** `\(file.path)`\n"
        markdown += "**Size:** \(Shared.Utils.Formatting.formatBytes(file.size))\n\n"

        markdown += "```\(language)\n"
        markdown += file.content
        if !file.content.hasSuffix("\n") {
            markdown += "\n"
        }
        markdown += "```\n"

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - Semantic Search Handlers (#81)

    private func handleSearchSymbols(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let query = args.optional(Shared.Constants.Search.schemaParamQuery)
        let kind = args.optional(Shared.Constants.Search.schemaParamKind)
        let isAsync = args.optionalBool(Shared.Constants.Search.schemaParamIsAsync)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()
        let platform = try Self.extractPlatformArgs(args)
        let format = try Self.mcpToolOutputFormat(args: args)

        let results = try await searchIndex.searchSymbols(
            query: query,
            kind: kind,
            isAsync: isAsync,
            framework: framework,
            limit: limit
        )
        let filtered = try await Self.applyPlatformFilter(
            results: results, platform: platform, searchIndex: searchIndex
        )

        if format == .json {
            let filters = Self.SymbolFiltersJSON(
                query: query,
                kind: kind,
                isAsync: isAsync,
                framework: framework,
                limit: limit,
                platform: platform
            )
            return Self.textResult(Self.formatSymbolSearchJSON(filters: filters, results: filtered))
        }

        let markdown = formatSymbolResults(
            results: filtered,
            title: "Symbol Search Results",
            query: query,
            filters: ["kind": kind, "is_async": isAsync.map { String($0) }, "framework": framework]
        )

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    private func handleSearchPropertyWrappers(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let wrapper: String = try args.require(Shared.Constants.Search.schemaParamWrapper)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()
        let platform = try Self.extractPlatformArgs(args)
        let format = try Self.mcpToolOutputFormat(args: args)

        let raw = try await searchIndex.searchPropertyWrappers(
            wrapper: wrapper,
            framework: framework,
            limit: limit
        )
        let results = try await Self.applyPlatformFilter(
            results: raw, platform: platform, searchIndex: searchIndex
        )

        let normalizedWrapper = wrapper.hasPrefix("@") ? wrapper : "@\(wrapper)"
        if format == .json {
            let filters = Self.SymbolFiltersJSON(
                wrapper: normalizedWrapper,
                framework: framework,
                limit: limit,
                platform: platform
            )
            return Self.textResult(Self.formatSymbolSearchJSON(filters: filters, results: results))
        }

        let markdown = formatSymbolResults(
            results: results,
            title: "Property Wrapper: \(normalizedWrapper)",
            query: wrapper,
            filters: ["wrapper": wrapper, "framework": framework]
        )

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    private func handleSearchConcurrency(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let pattern: String = try args.require(Shared.Constants.Search.schemaParamPattern)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()
        let platform = try Self.extractPlatformArgs(args)
        let format = try Self.mcpToolOutputFormat(args: args)

        let raw = try await searchIndex.searchConcurrencyPatterns(
            pattern: pattern,
            framework: framework,
            limit: limit
        )
        let results = try await Self.applyPlatformFilter(
            results: raw, platform: platform, searchIndex: searchIndex
        )

        if format == .json {
            let filters = Self.SymbolFiltersJSON(
                pattern: pattern,
                framework: framework,
                limit: limit,
                platform: platform
            )
            return Self.textResult(Self.formatSymbolSearchJSON(filters: filters, results: results))
        }

        let markdown = formatSymbolResults(
            results: results,
            title: "Concurrency Pattern: \(pattern)",
            query: pattern,
            filters: ["pattern": pattern, "framework": framework]
        )

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - Inheritance walk (#274)

    // swiftlint:disable:next function_body_length
    private func handleGetInheritance(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let symbol: String = try args.require(Shared.Constants.Search.schemaParamSymbol)
        let directionString = args.optional(Shared.Constants.Search.schemaParamDirection) ?? "up"
        let frameworkFilter = args.optional(Shared.Constants.Search.schemaParamFramework)
        let depth = args.optional(Shared.Constants.Search.schemaParamDepth, default: 5)
        let format = try Self.mcpToolOutputFormat(args: args)

        guard let direction = Search.InheritanceDirection(rawValue: directionString.lowercased()) else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamDirection,
                "Invalid direction `\(directionString)`. Valid values: up, down, both."
            )
        }
        guard depth > 0 else {
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamDepth,
                "Depth must be at least 1; got \(depth)."
            )
        }

        let candidates = try await searchIndex.resolveSymbolURIs(title: symbol)
        let candidate: Search.InheritanceCandidate
        switch candidates.count {
        case 0:
            let body = "No symbol named `\(symbol)` in apple-docs. " +
                "Try `search` first to find the right name, or check `list_frameworks`."
            if format == .json {
                return Self.textResult(Self.formatInheritanceNotFoundJSON(
                    symbol: symbol,
                    message: body
                ))
            }
            return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: body))])
        case 1:
            candidate = candidates[0]
        default:
            if let frameworkFilter,
               let match = candidates.first(where: { $0.framework.lowercased() == frameworkFilter.lowercased() }) {
                candidate = match
            } else {
                // Ambiguity → emit a disambiguation block per the
                // `get_symbol_summary` pattern (#70).
                var body = "`\(symbol)` is ambiguous across \(candidates.count) frameworks. " +
                    "Re-call with the matching `framework` argument:\n\n"
                for candidate in candidates {
                    body += "- `\(candidate.title)` in `\(candidate.framework)` — \(candidate.uri)\n"
                }
                if format == .json {
                    return Self.textResult(Self.formatInheritanceAmbiguousJSON(
                        symbol: symbol,
                        message: body,
                        candidates: candidates
                    ))
                }
                return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: body))])
            }
        }

        let tree = try await searchIndex.walkInheritance(
            startURI: candidate.uri,
            direction: direction,
            maxDepth: depth
        )

        if format == .json {
            return try await Self.textResult(Self.formatInheritanceJSON(
                candidate: candidate,
                direction: direction,
                depth: depth,
                tree: tree,
                searchIndex: searchIndex
            ))
        }

        var body = "# Inheritance: \(candidate.title)\n\n"
        body += "**URI:** `\(candidate.uri)`  **Framework:** `\(candidate.framework)`  **Direction:** `\(direction.rawValue)`  **Depth:** `\(depth)`\n\n"
        if tree.isEmpty {
            // #754 secondary: pick the empty-tree message based on
            // candidate.kind. A class with no ancestors going `up` is a
            // root type (NSObject), not a Swift value type or protocol.
            body += Search.emptyInheritanceMessage(kind: candidate.kind, direction: direction) + "\n"
            return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: body))])
        }
        if !tree.ancestors.isEmpty {
            body += "## Inherits from\n\n"
            renderInheritanceTreeMarkdown(tree.ancestors, indent: 0, into: &body)
            body += "\n"
        }
        if !tree.descendants.isEmpty {
            body += "## Inherited by\n\n"
            renderInheritanceTreeMarkdown(tree.descendants, indent: 0, into: &body)
        }
        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: body))])
    }

    private func renderInheritanceTreeMarkdown(
        _ nodes: [Search.InheritanceNode],
        indent: Int,
        into body: inout String
    ) {
        let pad = String(repeating: "  ", count: indent)
        for node in nodes {
            body += "\(pad)- `\(node.uri)`\n"
            if !node.children.isEmpty {
                renderInheritanceTreeMarkdown(node.children, indent: indent + 1, into: &body)
            }
        }
    }

    private func handleSearchConformances(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        guard let searchIndex else {
            throw searchIndexUnavailableError("index")
        }

        let protocolName: String = try args.require(Shared.Constants.Search.schemaParamProtocol)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()
        let platform = try Self.extractPlatformArgs(args)
        let format = try Self.mcpToolOutputFormat(args: args)

        let raw = try await searchIndex.searchConformances(
            protocolName: protocolName,
            framework: framework,
            limit: limit
        )
        let results = try await Self.applyPlatformFilter(
            results: raw, platform: platform, searchIndex: searchIndex
        )

        if format == .json {
            let filters = Self.SymbolFiltersJSON(
                protocolName: protocolName,
                framework: framework,
                limit: limit,
                platform: platform
            )
            return Self.textResult(Self.formatSymbolSearchJSON(filters: filters, results: results))
        }

        let markdown = formatSymbolResults(
            results: results,
            title: "Protocol Conformance: \(protocolName)",
            query: protocolName,
            filters: ["protocol": protocolName, "framework": framework]
        )

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    // MARK: - #226 — platform filter helpers (shared across 4 search-style tools)

    /// 5-tuple of `min*` filter strings extracted from the MCP call's
    /// arguments. All optional. Empty / missing fields stay nil so the
    /// `Search.PlatformFilter.passes(...)` predicate treats them as
    /// "no constraint" downstream.
    struct PlatformArgs {
        let minIOS: String?
        let minMacOS: String?
        let minTvOS: String?
        let minWatchOS: String?
        let minVisionOS: String?

        var isAnySet: Bool {
            minIOS != nil || minMacOS != nil || minTvOS != nil || minWatchOS != nil || minVisionOS != nil
        }
    }

    private static func extractPlatformArgs(
        _ args: MCP.SharedTools.ArgumentExtractor
    ) throws -> PlatformArgs {
        try PlatformArgs(
            minIOS: validatePlatformValue(
                args.optional(Shared.Constants.Search.schemaParamMinIOS),
                paramName: Shared.Constants.Search.schemaParamMinIOS
            ),
            minMacOS: validatePlatformValue(
                args.optional(Shared.Constants.Search.schemaParamMinMacOS),
                paramName: Shared.Constants.Search.schemaParamMinMacOS
            ),
            minTvOS: validatePlatformValue(
                args.optional(Shared.Constants.Search.schemaParamMinTvOS),
                paramName: Shared.Constants.Search.schemaParamMinTvOS
            ),
            minWatchOS: validatePlatformValue(
                args.optional(Shared.Constants.Search.schemaParamMinWatchOS),
                paramName: Shared.Constants.Search.schemaParamMinWatchOS
            ),
            minVisionOS: validatePlatformValue(
                args.optional(Shared.Constants.Search.schemaParamMinVisionOS),
                paramName: Shared.Constants.Search.schemaParamMinVisionOS
            )
        )
    }

    /// #226 — reject empty or malformed `min_<platform>` values up-front so
    /// they cannot silently no-op past the filter. Pre-#226 the args
    /// extractor accepted any string (or nil); empty strings, whitespace,
    /// and shapes like `"v18.0"` / `"18"` / `"ios18.0"` all flowed through
    /// to `Search.PlatformFilter.passes(...)` which compares lexicographic
    /// after splitting on `.`, producing surprising (and silently wrong)
    /// matches.
    ///
    /// Validation rule: a value is acceptable when its trimmed form matches
    /// `<digits>(\.<digits>)*` (semver-prefix shape — major, major.minor,
    /// or major.minor.patch). Any other shape rejects with a
    /// `ToolError.invalidArgument` carrying the offending param name so the
    /// MCP client sees a clear error frame rather than a silent no-op.
    ///
    /// Returns the *trimmed* value (or nil) so downstream callers consume
    /// the canonical form.
    static func validatePlatformValue(
        _ raw: String?,
        paramName: String
    ) throws -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Shared.Core.ToolError.invalidArgument(
                paramName,
                "Platform version filter must not be empty / whitespace-only — pass nil to omit the filter or a numeric version like \"18.0\"."
            )
        }
        // Permitted: digits, optional dot-separated digit groups.
        // Examples: "18", "18.0", "18.0.1". Rejected: "v18.0", "18.0a",
        // "ios18", "18..0", ".18", "18.".
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let allDigitGroups = parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isWholeNumber)
        }
        guard allDigitGroups else {
            throw Shared.Core.ToolError.invalidArgument(
                paramName,
                "Platform version filter must be a numeric semver-prefix (e.g. \"18\", \"18.0\", \"18.0.1\") — got \"\(raw)\"."
            )
        }
        return trimmed
    }

    /// Apply the MCP-level platform filter to a `[SymbolSearchResult]`.
    /// Short-circuits when no filter is set (the common case) — returns
    /// the input unchanged. When set, batch-fetches `docs_metadata.min_*`
    /// for each result's URI in one query, then filters in-process via
    /// `Search.PlatformFilter.passes`. Same semver semantics as the
    /// unified `search` tool (`Search.Index.Search.swift:730`).
    private static func applyPlatformFilter(
        results: [Search.SymbolSearchResult],
        platform: PlatformArgs,
        searchIndex: any Search.Database
    ) async throws -> [Search.SymbolSearchResult] {
        // #962: the fetch-minima + `PlatformFilter.passes` application now lives
        // in the shared `Search.Database.applyingPlatformFloors` so the AST CLI
        // subcommands filter identically. `PlatformArgs` is already validated by
        // `extractPlatformArgs`, so this `PlatformFloors` build does not re-throw.
        let floors = try Search.PlatformFloors(
            minIOS: platform.minIOS,
            minMacOS: platform.minMacOS,
            minTvOS: platform.minTvOS,
            minWatchOS: platform.minWatchOS,
            minVisionOS: platform.minVisionOS
        )
        return try await searchIndex.applyingPlatformFloors(to: results, floors: floors)
    }

    /// #665 / #409 Layer 2 — surfaces `doc_symbols.generic_params`.
    /// #226 follow-up — applies the MCP-level platform filter post-search
    /// to match the other 4 AST tools (search_symbols /
    /// search_property_wrappers / search_concurrency / search_conformances).
    ///
    /// `#857` v1.2.0 expansion: fan out across all three databases
    /// (search.db apple-docs, samples.db `file_symbols`, packages.db
    /// `package_symbols`). The search.db arm preserves the pre-`#857`
    /// rich `Search.SymbolSearchResult` rendering (`formatSymbolResults`)
    /// so callers that relied on the structured output for apple-docs
    /// keep their behaviour. Samples + packages get appended below the
    /// apple-docs block, each in their own section so the response is
    /// readable as a single markdown blob. When `searchIndex` is nil but
    /// `sampleDatabase` or `packagesSearcher` is available, the apple-
    /// docs arm is skipped silently and the response is built from the
    /// remaining sources — closer to the `SmartQuery` fan-out behaviour
    /// for default search than the pre-`#857` all-or-nothing path.
    private func handleSearchGenerics(args: MCP.SharedTools.ArgumentExtractor) async throws -> MCP.Core.Protocols.CallToolResult {
        // `#645` semantic preserved: when search.db is in the
        // disabled-reason state (file present but unopenable, e.g.
        // schema mismatch), still throw an explicit error frame so MCP
        // clients see the configuration-level failure rather than a
        // silently-degraded cross-DB response.
        if searchIndex == nil, searchIndexDisabledReason != nil {
            throw searchIndexUnavailableError("index")
        }

        let constraint: String = try args.require(Shared.Constants.Search.schemaParamConstraint)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()
        let platform = try Self.extractPlatformArgs(args)
        let format = try Self.mcpToolOutputFormat(args: args)

        // Source A: search.db apple-docs (rich `Search.SymbolSearchResult`).
        var appleDocsMarkdown: String?
        var appleDocsResults: [Search.SymbolSearchResult] = []
        if let searchIndex {
            let raw = try await searchIndex.searchByGenericConstraint(
                constraint: constraint,
                framework: framework,
                limit: limit
            )
            let results = try await Self.applyPlatformFilter(
                results: raw, platform: platform, searchIndex: searchIndex
            )
            appleDocsResults = results
            appleDocsMarkdown = formatSymbolResults(
                results: results,
                title: "Apple Docs",
                query: constraint,
                filters: ["constraint": constraint, "framework": framework]
            )
        }

        // Source B: samples.db `file_symbols`. Default-impl returns
        // empty array when the reader hasn't been updated, keeping the
        // fan-out resilient to mixed bundle versions.
        var samplesRows: [Sample.Index.FileSearchResult] = []
        if let sampleDatabase {
            samplesRows = await (try? sampleDatabase.searchFilesByGenericConstraint(
                constraint: constraint,
                framework: framework,
                limit: limit
            )) ?? []
        }

        // Source C: packages.db `package_symbols` (joined to
        // `package_files` + `package_metadata` for owner/repo/module).
        var packagesRows: [Search.Result] = []
        if let packagesSearcher {
            packagesRows = await (try? packagesSearcher.searchPackageSymbolsByGenericConstraint(
                constraint: constraint,
                framework: framework,
                limit: limit
            )) ?? []
        }

        if format == .json {
            let filters = Self.SymbolFiltersJSON(
                constraint: constraint,
                framework: framework,
                limit: limit,
                platform: platform
            )
            return Self.textResult(Self.formatGenericsJSON(
                filters: filters,
                appleDocs: appleDocsResults,
                samples: samplesRows,
                packages: packagesRows
            ))
        }

        let markdown = Self.formatCrossDBGenerics(
            constraint: constraint,
            framework: framework,
            appleDocsMarkdown: appleDocsMarkdown,
            samples: samplesRows,
            packages: packagesRows
        )

        return MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: markdown))])
    }

    /// `#857` cross-DB result renderer. Each contributing source emits
    /// its own section, source-tagged in the header so AI agents reading
    /// the response can identify provenance per row without parsing the
    /// surrounding markdown. The apple-docs section reuses the existing
    /// `formatSymbolResults` output so legacy parsers continue to work
    /// against the pre-`#857` shape for that source.
    static func formatCrossDBGenerics(
        constraint: String,
        framework: String?,
        appleDocsMarkdown: String?,
        samples: [Sample.Index.FileSearchResult],
        packages: [Search.Result]
    ) -> String {
        var blocks: [String] = []

        let headerFilters: String = {
            var parts = ["constraint=\(constraint)"]
            if let framework, !framework.isEmpty { parts.append("framework=\(framework)") }
            return parts.joined(separator: ", ")
        }()
        blocks.append("# Generic Constraint: \(constraint)\n")
        blocks.append("**Filters:** \(headerFilters)\n")

        if let appleDocsMarkdown, !appleDocsMarkdown.isEmpty {
            blocks.append("## Apple Docs (search.db)\n")
            blocks.append(appleDocsMarkdown)
        } else {
            blocks.append("## Apple Docs (search.db)\n_No symbols found in apple-docs._\n")
        }

        blocks.append("## Sample Code (samples.db)\n")
        if samples.isEmpty {
            blocks.append("_No symbols found in samples._\n")
        } else {
            blocks.append("Found **\(samples.count)** matching files:\n")
            for row in samples {
                blocks.append("- **\(row.filename)** (`\(row.projectId)`) — \(row.path)")
                if !row.snippet.isEmpty {
                    blocks.append("  ``")
                    blocks.append("  \(row.snippet.replacingOccurrences(of: "\n", with: " "))")
                    blocks.append("  ``")
                }
            }
            blocks.append("")
        }

        blocks.append("## Swift Packages (packages.db)\n")
        if packages.isEmpty {
            blocks.append("_No symbols found in packages._\n")
        } else {
            blocks.append("Found **\(packages.count)** matching symbols:\n")
            for row in packages {
                blocks.append("- **\(row.title)** (`\(row.framework)`) — `\(row.uri)`")
                if !row.summary.isEmpty {
                    let oneLiner = row.summary.replacingOccurrences(of: "\n", with: " ")
                    blocks.append("  ``\(oneLiner)``")
                }
            }
            blocks.append("")
        }

        return blocks.joined(separator: "\n")
    }

    /// Format symbol search results as markdown
    private func formatSymbolResults(
        results: [Search.SymbolSearchResult],
        title: String,
        query: String?,
        filters: [String: String?]
    ) -> String {
        var markdown = "# \(title)\n\n"

        // Show active filters
        let activeFilters = filters.compactMapValues { $0 }
        if !activeFilters.isEmpty {
            markdown += "**Filters:** "
            markdown += activeFilters.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            markdown += "\n\n"
        }

        if results.isEmpty {
            markdown += "_No symbols found matching your criteria._\n\n"
            markdown += "💡 **Tips:**\n"
            markdown += "- Try a broader search pattern\n"
            markdown += "- Check available symbol kinds: struct, class, actor, enum, protocol, function, property\n"
            return markdown
        }

        markdown += "Found **\(results.count)** symbols:\n\n"

        // Group by document for better organization
        var byDocument: [String: [(Search.SymbolSearchResult, Int)]] = [:]
        for (index, result) in results.enumerated() {
            byDocument[result.docUri, default: []].append((result, index))
        }

        for (docUri, symbols) in byDocument.sorted(by: { $0.key < $1.key }) {
            let firstSymbol = symbols[0].0
            markdown += "### \(firstSymbol.docTitle)\n"
            markdown += "_Framework: \(firstSymbol.framework.isEmpty ? "unknown" : firstSymbol.framework)_ "
            markdown += "| URI: `\(docUri)`\n\n"

            for (symbol, _) in symbols {
                markdown += "- **\(symbol.symbolKind)** `\(symbol.symbolName)`"
                if symbol.isAsync {
                    markdown += " `async`"
                }
                if let sig = symbol.signature, !sig.isEmpty {
                    let truncatedSig = sig.count > 60 ? String(sig.prefix(60)) + "..." : sig
                    markdown += "\n  - Signature: `\(truncatedSig)`"
                }
                if let attrs = symbol.attributes, !attrs.isEmpty {
                    markdown += "\n  - Attributes: \(attrs)"
                }
                if let conforms = symbol.conformances, !conforms.isEmpty {
                    markdown += "\n  - Conforms to: \(conforms)"
                }
                if let generics = symbol.genericParams, !generics.isEmpty {
                    markdown += "\n  - Generic params: `\(generics)`"
                }
                markdown += "\n"
            }
            markdown += "\n"
        }

        markdown += "---\n"
        markdown += "💡 Use `read_document` with the URI to get the full documentation.\n"

        return markdown
    }

    // MARK: - Helpers

    private func languageForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "h", "m", "mm": return "objc"
        case "c": return "c"
        case "cpp", "hpp": return "cpp"
        case "metal": return "metal"
        case "json": return "json"
        case "plist": return "xml"
        case "md": return "markdown"
        case "strings": return "properties"
        default: return ext
        }
    }

    // MARK: - Schema descriptions

    /// Pulled out as `static let` constants so each description can be
    /// long without tripping SwiftLint's 200-char line-length cap.
    private static let schemaDescriptionMinSwift = """
    Maximum Swift toolchain version for swift-evolution results \
    (e.g. 5.5, 6.0). Filters swift-evolution proposals to those \
    implemented at or below the given version; rows from other \
    sources (apple-docs, samples, hig, swift-org, swift-book, \
    packages) are filtered out when this is set.
    """

    private static let schemaDescriptionAppleImports = """
    Restrict packages results to packages that import the given \
    Apple framework (e.g. SwiftUI, Combine, CryptoKit). Filters on \
    packages.db's apple_imports_json column via a quote-bracketed \
    JSON LIKE so SwiftUI does not match SwiftUIHelper. No effect on \
    rows from sources other than packages.
    """

    /// #976: private factory for the canonical MCP-side
    /// `Services.Formatter.Config`. Pre-#976 the 4 call sites used
    /// `Services.Formatter.Config.mcpDefault`, a Rule 1 Service Locator
    /// static. The static was removed; this private helper constructs
    /// the same Config on demand. Rule 1 carve-out (b): internal
    /// factory, not reachable from outside the provider.
    private static func makeStandardConfig() -> Services.Formatter.Config {
        Services.Formatter.Config(
            showScore: true,
            showWordCount: true,
            showSource: false,
            showAvailability: true,
            showSeparators: true,
            emptyMessage: "_No results found. Try broader search terms._"
        )
    }
}

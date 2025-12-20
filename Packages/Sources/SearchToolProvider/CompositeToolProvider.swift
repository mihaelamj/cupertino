import Foundation
import MCP
import SampleIndex
import Search
import Services
import Shared

// MARK: - Unified Cupertino Tool Provider

/// Composite tool provider that provides unified search across all documentation sources.
/// Handles `search_docs` with `source` parameter to search docs, samples, HIG, archive, etc.
public actor CompositeToolProvider: ToolProvider {
    // Use service layer for consistency with CLI
    private let docsService: DocsSearchService?
    private let sampleService: SampleSearchService?

    // Keep direct access for low-level operations (list frameworks, read document)
    private let searchIndex: Search.Index?
    private let sampleDatabase: SampleIndex.Database?

    public init(searchIndex: Search.Index?, sampleDatabase: SampleIndex.Database?) {
        self.searchIndex = searchIndex
        self.sampleDatabase = sampleDatabase

        // Wrap databases with services for search operations
        if let searchIndex {
            docsService = DocsSearchService(index: searchIndex)
        } else {
            docsService = nil
        }

        if let sampleDatabase {
            sampleService = SampleSearchService(database: sampleDatabase)
        } else {
            sampleService = nil
        }
    }

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> ListToolsResult {
        var allTools: [Tool] = []

        // Unified search tool (replaces search_docs, search_hig, search_all, search_samples)
        if searchIndex != nil || sampleDatabase != nil {
            allTools.append(Tool(
                name: Shared.Constants.Search.toolSearch,
                description: Shared.Constants.Search.toolSearchDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.Search.schemaParamQuery]
                )
            ))
        }

        // List frameworks tool
        if searchIndex != nil {
            allTools.append(Tool(
                name: Shared.Constants.Search.toolListFrameworks,
                description: Shared.Constants.Search.toolListFrameworksDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.Search.toolReadDocument,
                description: Shared.Constants.Search.toolReadDocumentDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.Search.schemaParamURI]
                )
            ))
        }

        // Sample code tools
        if sampleDatabase != nil {
            allTools.append(Tool(
                name: Shared.Constants.Search.toolListSamples,
                description: Shared.Constants.Search.toolListSamplesDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.Search.toolReadSample,
                description: Shared.Constants.Search.toolReadSampleDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.Search.schemaParamProjectId]
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.Search.toolReadSampleFile,
                description: Shared.Constants.Search.toolReadSampleFileDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [
                        Shared.Constants.Search.schemaParamProjectId,
                        Shared.Constants.Search.schemaParamFilePath,
                    ]
                )
            ))
        }

        // Semantic search tools (#81)
        if searchIndex != nil {
            allTools.append(Tool(
                name: Shared.Constants.Search.toolSearchSymbols,
                description: Shared.Constants.Search.toolSearchSymbolsDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: []
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.Search.toolSearchPropertyWrappers,
                description: Shared.Constants.Search.toolSearchPropertyWrappersDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.Search.schemaParamWrapper]
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.Search.toolSearchConcurrency,
                description: Shared.Constants.Search.toolSearchConcurrencyDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.Search.schemaParamPattern]
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.Search.toolSearchConformances,
                description: Shared.Constants.Search.toolSearchConformancesDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.Search.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.Search.schemaParamProtocol]
                )
            ))
        }

        return ListToolsResult(tools: allTools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        let args = ArgumentExtractor(arguments)

        switch name {
        case Shared.Constants.Search.toolSearch:
            return try await handleSearch(args: args)
        case Shared.Constants.Search.toolListFrameworks:
            return try await handleListFrameworks()
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
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Unified Search Handler

    private func handleSearch(args: ArgumentExtractor) async throws -> CallToolResult {
        let query: String = try args.require(Shared.Constants.Search.schemaParamQuery)
        let source = args.optional(Shared.Constants.Search.schemaParamSource)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let language = args.optional(Shared.Constants.Search.schemaParamLanguage)
        let limit = args.limit()
        let includeArchive = args.includeArchive()
        let minIOS = args.minIOS()
        let minMacOS = args.minMacOS()
        let minTvOS = args.minTvOS()
        let minWatchOS = args.minWatchOS()
        let minVisionOS = args.minVisionOS()

        // Route based on source parameter
        // Default (nil) now searches ALL sources for better results (#81)
        switch source {
        case Shared.Constants.SourcePrefix.samples, Shared.Constants.SourcePrefix.appleSampleCode:
            return try await handleSearchSamples(
                query: query,
                framework: framework,
                limit: limit
            )
        case Shared.Constants.SourcePrefix.hig:
            return try await handleSearchHIG(
                query: query,
                framework: framework,
                limit: limit
            )
        case Shared.Constants.SourcePrefix.appleDocs,
             Shared.Constants.SourcePrefix.appleArchive,
             Shared.Constants.SourcePrefix.swiftEvolution,
             Shared.Constants.SourcePrefix.swiftOrg,
             Shared.Constants.SourcePrefix.swiftBook,
             Shared.Constants.SourcePrefix.packages:
            // Specific source requested: search only that source
            return try await handleSearchDocs(
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
                minVisionOS: minVisionOS
            )
        default:
            // Default (nil or "all"): search ALL sources for comprehensive results
            return try await handleSearchAll(
                query: query,
                framework: framework,
                limit: limit
            )
        }
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
        minVisionOS: String?
    ) async throws -> CallToolResult {
        guard let docsService else {
            throw ToolError.invalidArgument("source", "Documentation index not available")
        }

        // Use service layer (same as CLI)
        let results = try await docsService.search(SearchQuery(
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
            minimumVisionOS: minVisionOS
        ))

        // Fetch teaser results from all sources user didn't search
        let teasers = await fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: source,
            includeArchive: includeArchive
        )

        // Use shared formatter
        let filters = SearchFilters(
            source: source,
            framework: framework,
            language: language,
            minimumiOS: minIOS,
            minimumMacOS: minMacOS,
            minimumTvOS: minTvOS,
            minimumWatchOS: minWatchOS,
            minimumVisionOS: minVisionOS
        )

        // Configure empty message to suggest archive if not already searching it
        var config = SearchResultFormatConfig.mcpDefault
        if results.isEmpty, !includeArchive, source != Shared.Constants.SourcePrefix.appleArchive {
            config = SearchResultFormatConfig(
                showScore: true,
                showWordCount: true,
                showSource: false,
                showAvailability: true,
                showSeparators: true,
                emptyMessage: Shared.Constants.Search.messageNoResults + "\n\n" + Shared.Constants.Search.tipTryArchive
            )
        }

        let formatter = MarkdownSearchResultFormatter(
            query: query,
            filters: filters,
            config: config,
            teasers: teasers
        )
        let markdown = formatter.format(results)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Teaser Results

    // Uses shared TeaserService from Services module

    /// Fetch teaser results from all sources the user didn't search
    private func fetchAllTeasers(
        query: String,
        framework: String?,
        currentSource: String?,
        includeArchive: Bool
    ) async -> Services.TeaserResults {
        let teaserService = TeaserService(searchIndex: searchIndex, sampleDatabase: sampleDatabase)
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
        limit: Int
    ) async throws -> CallToolResult {
        guard let sampleService else {
            throw ToolError.invalidArgument("source", "Sample code database not available")
        }

        // Use service layer (same as CLI)
        let result = try await sampleService.search(SampleQuery(
            text: query,
            framework: framework,
            searchFiles: true,
            limit: limit
        ))

        // Fetch teaser results from other sources
        let teasers = await fetchAllTeasers(
            query: query,
            framework: framework,
            currentSource: Shared.Constants.SourcePrefix.samples,
            includeArchive: false
        )

        // Use shared formatter
        let formatter = SampleSearchMarkdownFormatter(query: query, framework: framework, teasers: teasers)
        let markdown = formatter.format(result)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - HIG Search

    private func handleSearchHIG(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> CallToolResult {
        guard let docsService else {
            throw ToolError.invalidArgument("source", "Documentation index not available")
        }

        // Use service layer (same as CLI)
        let results = try await docsService.search(SearchQuery(
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

        // Use shared formatter
        let higQuery = HIGQuery(text: query, platform: nil, category: nil)
        let formatter = HIGMarkdownFormatter(query: higQuery, config: .mcpDefault, teasers: teasers)
        let markdown = formatter.format(results)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Unified Search (All Sources)

    private func handleSearchAll(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> CallToolResult {
        // Use UnifiedSearchService to search all 8 sources
        let unifiedService = UnifiedSearchService(searchIndex: searchIndex, sampleDatabase: sampleDatabase)
        let input = await unifiedService.searchAll(
            query: query,
            framework: framework,
            limit: limit
        )

        // Use shared formatter (identical to CLI --format markdown output)
        let formatter = UnifiedSearchMarkdownFormatter(
            query: query,
            framework: framework,
            config: .mcpDefault
        )
        let markdown = formatter.format(input)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - List Frameworks

    private func handleListFrameworks() async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("index", "Documentation index not available")
        }

        let frameworks = try await searchIndex.listFrameworks()
        let totalDocs = try await searchIndex.documentCount()

        let formatter = FrameworksMarkdownFormatter(totalDocs: totalDocs)
        let markdown = formatter.format(frameworks)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Read Document

    private func handleReadDocument(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("index", "Documentation index not available")
        }

        let uri: String = try args.require(Shared.Constants.Search.schemaParamURI)
        let formatString = args.format()
        let format: Search.Index.DocumentFormat = formatString == Shared.Constants.Search.formatValueMarkdown
            ? .markdown : .json

        guard let documentContent = try await searchIndex.getDocumentContent(uri: uri, format: format) else {
            throw ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamURI,
                "Document not found: \(uri)"
            )
        }

        return CallToolResult(content: [.text(TextContent(text: documentContent))])
    }

    // MARK: - Sample Code Tools

    private func handleListSamples(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let sampleDatabase else {
            throw ToolError.invalidArgument("database", "Sample code database not available")
        }

        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit(default: 50)

        let projects = try await sampleDatabase.listProjects(framework: framework, limit: limit)
        let totalProjects = try await sampleDatabase.projectCount()
        let totalFiles = try await sampleDatabase.fileCount()

        var markdown = "# Indexed Sample Code Projects\n\n"
        markdown += "Total projects: **\(totalProjects)**\n"
        markdown += "Total files: **\(totalFiles)**\n\n"

        if let framework {
            markdown += "_Filtered to framework: **\(framework)**_\n\n"
        }

        if projects.isEmpty {
            markdown += "_No projects found. Run `cupertino index` to index sample code._\n"
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

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    private func handleReadSample(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let sampleDatabase else {
            throw ToolError.invalidArgument("database", "Sample code database not available")
        }

        let projectId: String = try args.require(Shared.Constants.Search.schemaParamProjectId)

        guard let project = try await sampleDatabase.getProject(id: projectId) else {
            throw ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamProjectId,
                "Project not found: \(projectId)"
            )
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
        markdown += "- **Size:** \(Shared.Formatting.formatBytes(project.totalSize))\n"
        if !project.webURL.isEmpty {
            markdown += "- **Apple Developer:** \(project.webURL)\n"
        }
        markdown += "\n"

        if let readme = project.readme, !readme.isEmpty {
            markdown += "## README\n\n"
            markdown += readme
            markdown += "\n\n"
        }

        // List some files
        let files = try await sampleDatabase.listFiles(projectId: projectId)
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

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    private func handleReadSampleFile(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let sampleDatabase else {
            throw ToolError.invalidArgument("database", "Sample code database not available")
        }

        let projectId: String = try args.require(Shared.Constants.Search.schemaParamProjectId)
        let filePath: String = try args.require(Shared.Constants.Search.schemaParamFilePath)

        guard let file = try await sampleDatabase.getFile(projectId: projectId, path: filePath) else {
            throw ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamFilePath,
                "File not found: \(filePath) in project \(projectId)"
            )
        }

        var markdown = "# \(file.filename)\n\n"
        markdown += "**Project:** `\(file.projectId)`\n"
        markdown += "**Path:** `\(file.path)`\n"
        markdown += "**Size:** \(Shared.Formatting.formatBytes(file.size))\n\n"

        let language = languageForExtension(file.fileExtension)

        markdown += "```\(language)\n"
        markdown += file.content
        if !file.content.hasSuffix("\n") {
            markdown += "\n"
        }
        markdown += "```\n"

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Semantic Search Handlers (#81)

    private func handleSearchSymbols(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("index", "Documentation index not available")
        }

        let query = args.optional(Shared.Constants.Search.schemaParamQuery)
        let kind = args.optional(Shared.Constants.Search.schemaParamKind)
        let isAsync = args.optionalBool(Shared.Constants.Search.schemaParamIsAsync)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()

        let results = try await searchIndex.searchSymbols(
            query: query,
            kind: kind,
            isAsync: isAsync,
            framework: framework,
            limit: limit
        )

        let markdown = formatSymbolResults(
            results: results,
            title: "Symbol Search Results",
            query: query,
            filters: ["kind": kind, "is_async": isAsync.map { String($0) }, "framework": framework]
        )

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    private func handleSearchPropertyWrappers(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("index", "Documentation index not available")
        }

        let wrapper: String = try args.require(Shared.Constants.Search.schemaParamWrapper)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()

        let results = try await searchIndex.searchPropertyWrappers(
            wrapper: wrapper,
            framework: framework,
            limit: limit
        )

        let normalizedWrapper = wrapper.hasPrefix("@") ? wrapper : "@\(wrapper)"
        let markdown = formatSymbolResults(
            results: results,
            title: "Property Wrapper: \(normalizedWrapper)",
            query: wrapper,
            filters: ["wrapper": wrapper, "framework": framework]
        )

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    private func handleSearchConcurrency(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("index", "Documentation index not available")
        }

        let pattern: String = try args.require(Shared.Constants.Search.schemaParamPattern)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()

        let results = try await searchIndex.searchConcurrencyPatterns(
            pattern: pattern,
            framework: framework,
            limit: limit
        )

        let markdown = formatSymbolResults(
            results: results,
            title: "Concurrency Pattern: \(pattern)",
            query: pattern,
            filters: ["pattern": pattern, "framework": framework]
        )

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    private func handleSearchConformances(args: ArgumentExtractor) async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("index", "Documentation index not available")
        }

        let protocolName: String = try args.require(Shared.Constants.Search.schemaParamProtocol)
        let framework = args.optional(Shared.Constants.Search.schemaParamFramework)
        let limit = args.limit()

        let results = try await searchIndex.searchConformances(
            protocolName: protocolName,
            framework: framework,
            limit: limit
        )

        let markdown = formatSymbolResults(
            results: results,
            title: "Protocol Conformance: \(protocolName)",
            query: protocolName,
            filters: ["protocol": protocolName, "framework": framework]
        )

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    /// Format symbol search results as markdown
    private func formatSymbolResults(
        results: [Search.Index.SymbolSearchResult],
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
        var byDocument: [String: [(Search.Index.SymbolSearchResult, Int)]] = [:]
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
}

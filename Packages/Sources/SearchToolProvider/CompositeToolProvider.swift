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
    private let searchIndex: Search.Index?
    private let sampleDatabase: SampleIndex.Database?

    public init(searchIndex: Search.Index?, sampleDatabase: SampleIndex.Database?) {
        self.searchIndex = searchIndex
        self.sampleDatabase = sampleDatabase
    }

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> ListToolsResult {
        var allTools: [Tool] = []

        // Unified search tool (replaces search_docs, search_hig, search_all, search_samples)
        if searchIndex != nil || sampleDatabase != nil {
            allTools.append(Tool(
                name: Shared.Constants.MCP.toolSearch,
                description: Shared.Constants.MCP.toolSearchDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamQuery]
                )
            ))
        }

        // List frameworks tool
        if searchIndex != nil {
            allTools.append(Tool(
                name: Shared.Constants.MCP.toolListFrameworks,
                description: Shared.Constants.MCP.toolListFrameworksDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.MCP.toolReadDocument,
                description: Shared.Constants.MCP.toolReadDocumentDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamURI]
                )
            ))
        }

        // Sample code tools
        if sampleDatabase != nil {
            allTools.append(Tool(
                name: Shared.Constants.MCP.toolListSamples,
                description: Shared.Constants.MCP.toolListSamplesDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.MCP.toolReadSample,
                description: Shared.Constants.MCP.toolReadSampleDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamProjectId]
                )
            ))

            allTools.append(Tool(
                name: Shared.Constants.MCP.toolReadSampleFile,
                description: Shared.Constants.MCP.toolReadSampleFileDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [
                        Shared.Constants.MCP.schemaParamProjectId,
                        Shared.Constants.MCP.schemaParamFilePath,
                    ]
                )
            ))
        }

        return ListToolsResult(tools: allTools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        let args = ArgumentExtractor(arguments)

        switch name {
        case Shared.Constants.MCP.toolSearch:
            return try await handleSearch(args: args)
        case Shared.Constants.MCP.toolListFrameworks:
            return try await handleListFrameworks()
        case Shared.Constants.MCP.toolReadDocument:
            return try await handleReadDocument(args: args)
        case Shared.Constants.MCP.toolListSamples:
            return try await handleListSamples(args: args)
        case Shared.Constants.MCP.toolReadSample:
            return try await handleReadSample(args: args)
        case Shared.Constants.MCP.toolReadSampleFile:
            return try await handleReadSampleFile(args: args)
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Unified Search Handler

    private func handleSearch(args: ArgumentExtractor) async throws -> CallToolResult {
        let query: String = try args.require(Shared.Constants.MCP.schemaParamQuery)
        let source = args.optional(Shared.Constants.MCP.schemaParamSource)
        let framework = args.optional(Shared.Constants.MCP.schemaParamFramework)
        let language = args.optional(Shared.Constants.MCP.schemaParamLanguage)
        let limit = args.limit()
        let includeArchive = args.includeArchive()
        let minIOS = args.minIOS()
        let minMacOS = args.minMacOS()
        let minTvOS = args.minTvOS()
        let minWatchOS = args.minWatchOS()
        let minVisionOS = args.minVisionOS()

        // Route based on source parameter
        switch source {
        case Shared.Constants.SourcePrefix.samples, Shared.Constants.SourcePrefix.appleSampleCode:
            return try await handleSearchSamples(
                query: query,
                framework: framework,
                limit: limit
            )
        case Shared.Constants.SourcePrefix.all:
            return try await handleSearchAll(
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
        default:
            // Default: search documentation index
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
        guard let searchIndex else {
            throw ToolError.invalidArgument("source", "Documentation index not available")
        }

        // Fetch more results if filtering by version (to account for filtering)
        let hasVersionFilter = minIOS != nil || minMacOS != nil || minTvOS != nil ||
            minWatchOS != nil || minVisionOS != nil
        let fetchLimit = hasVersionFilter
            ? min(limit * 3, Shared.Constants.Limit.maxSearchLimit)
            : limit

        // Perform search
        var results = try await searchIndex.search(
            query: query,
            source: source,
            framework: framework,
            language: language,
            limit: fetchLimit,
            includeArchive: includeArchive
        )

        // Apply version filters if specified
        if let minIOS {
            results = results.filter { result in
                guard let resultVersion = result.minimumiOS else { return false }
                return Self.isVersion(resultVersion, lessThanOrEqualTo: minIOS)
            }
        }

        if let minMacOS {
            results = results.filter { result in
                guard let resultVersion = result.minimumMacOS else { return false }
                return Self.isVersion(resultVersion, lessThanOrEqualTo: minMacOS)
            }
        }

        if let minTvOS {
            results = results.filter { result in
                guard let resultVersion = result.minimumTvOS else { return false }
                return Self.isVersion(resultVersion, lessThanOrEqualTo: minTvOS)
            }
        }

        if let minWatchOS {
            results = results.filter { result in
                guard let resultVersion = result.minimumWatchOS else { return false }
                return Self.isVersion(resultVersion, lessThanOrEqualTo: minWatchOS)
            }
        }

        if let minVisionOS {
            results = results.filter { result in
                guard let resultVersion = result.minimumVisionOS else { return false }
                return Self.isVersion(resultVersion, lessThanOrEqualTo: minVisionOS)
            }
        }

        // Trim to requested limit after filtering
        results = Array(results.prefix(limit))

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
                emptyMessage: Shared.Constants.MCP.messageNoResults + "\n\n" + Shared.Constants.MCP.tipTryArchive
            )
        }

        let formatter = MarkdownSearchResultFormatter(
            query: query,
            filters: filters,
            config: config
        )
        var markdown = formatter.format(results)

        // Append teaser sections if available (using shared formatter)
        let teaserFormatter = TeaserMarkdownFormatter()
        markdown += teaserFormatter.format(teasers)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Teaser Results

    // Uses shared TeaserResults from Services module

    /// Fetch teaser results from all sources the user didn't search
    private func fetchAllTeasers(
        query: String,
        framework: String?,
        currentSource: String?,
        includeArchive: Bool
    ) async -> Services.TeaserResults {
        var teasers = Services.TeaserResults()
        let source = currentSource ?? Shared.Constants.SourcePrefix.appleDocs

        // Samples teaser (unless searching samples)
        if source != Shared.Constants.SourcePrefix.samples,
           source != Shared.Constants.SourcePrefix.appleSampleCode {
            teasers.samples = await fetchTeaserSamples(query: query, framework: framework)
        }

        // Archive teaser (unless searching archive or include_archive is set)
        if !includeArchive, source != Shared.Constants.SourcePrefix.appleArchive {
            teasers.archive = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.appleArchive
            )
        }

        // HIG teaser (unless searching HIG)
        if source != Shared.Constants.SourcePrefix.hig {
            teasers.hig = await fetchTeaserFromSource(query: query, sourceType: Shared.Constants.SourcePrefix.hig)
        }

        // Swift Evolution teaser (unless searching swift-evolution)
        if source != Shared.Constants.SourcePrefix.swiftEvolution {
            teasers.swiftEvolution = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.swiftEvolution
            )
        }

        // Swift.org teaser (unless searching swift-org)
        if source != Shared.Constants.SourcePrefix.swiftOrg {
            teasers.swiftOrg = await fetchTeaserFromSource(query: query, sourceType: Shared.Constants.SourcePrefix.swiftOrg)
        }

        // Swift Book teaser (unless searching swift-book)
        if source != Shared.Constants.SourcePrefix.swiftBook {
            teasers.swiftBook = await fetchTeaserFromSource(
                query: query,
                sourceType: Shared.Constants.SourcePrefix.swiftBook
            )
        }

        // Packages teaser (unless searching packages)
        if source != Shared.Constants.SourcePrefix.packages {
            teasers.packages = await fetchTeaserFromSource(query: query, sourceType: Shared.Constants.SourcePrefix.packages)
        }

        return teasers
    }

    /// Fetch a few sample projects as teaser (returns empty if unavailable)
    private func fetchTeaserSamples(query: String, framework: String?) async -> [SampleIndex.Project] {
        guard let sampleDatabase else { return [] }
        do {
            return try await sampleDatabase.searchProjects(
                query: query,
                framework: framework,
                limit: Shared.Constants.Limit.teaserLimit
            )
        } catch {
            return []
        }
    }

    /// Fetch teaser results from a specific source
    private func fetchTeaserFromSource(query: String, sourceType: String) async -> [Search.Result] {
        guard let searchIndex else { return [] }
        do {
            return try await searchIndex.search(
                query: query,
                source: sourceType,
                framework: nil,
                language: nil,
                limit: Shared.Constants.Limit.teaserLimit,
                includeArchive: sourceType == Shared.Constants.SourcePrefix.appleArchive
            )
        } catch {
            return []
        }
    }

    // MARK: - Sample Code Search

    private func handleSearchSamples(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> CallToolResult {
        guard let sampleDatabase else {
            throw ToolError.invalidArgument("source", "Sample code database not available")
        }

        // Search projects
        let projects = try await sampleDatabase.searchProjects(query: query, framework: framework, limit: limit)

        // Also search files
        let files = try await sampleDatabase.searchFiles(query: query, projectId: nil, limit: limit)

        // Build result
        let result = SampleSearchResult(projects: projects, files: files)

        // Use shared formatter
        let formatter = SampleSearchMarkdownFormatter(query: query, framework: framework)
        let markdown = formatter.format(result)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - HIG Search

    private func handleSearchHIG(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> CallToolResult {
        guard let searchIndex else {
            throw ToolError.invalidArgument("source", "Documentation index not available")
        }

        // Search HIG content only
        let results = try await searchIndex.search(
            query: query,
            source: Shared.Constants.SourcePrefix.hig,
            framework: framework,
            language: nil,
            limit: limit,
            includeArchive: false
        )

        // Use shared formatter
        let higQuery = HIGQuery(text: query, platform: nil, category: nil)
        let formatter = HIGMarkdownFormatter(query: higQuery, config: .mcpDefault)
        let markdown = formatter.format(results)

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Unified Search (All Sources)

    private func handleSearchAll(
        query: String,
        framework: String?,
        limit: Int
    ) async throws -> CallToolResult {
        // Search ALL 8 sources
        var docResults: [Search.Result] = []
        var archiveResults: [Search.Result] = []
        var sampleResults: [SampleIndex.Project] = []
        var higResults: [Search.Result] = []
        var swiftEvolutionResults: [Search.Result] = []
        var swiftOrgResults: [Search.Result] = []
        var swiftBookResults: [Search.Result] = []
        var packagesResults: [Search.Result] = []

        // Apple Documentation (modern)
        if let searchIndex {
            docResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: framework,
                language: nil,
                limit: limit,
                includeArchive: false
            )) ?? []
        }

        // Apple Archive (legacy guides)
        if let searchIndex {
            archiveResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.appleArchive,
                framework: framework,
                language: nil,
                limit: limit,
                includeArchive: true
            )) ?? []
        }

        // Sample Code Projects
        if let sampleDatabase {
            sampleResults = await (try? sampleDatabase.searchProjects(
                query: query,
                framework: framework,
                limit: limit
            )) ?? []
        }

        // Human Interface Guidelines
        if let searchIndex {
            higResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.hig,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            )) ?? []
        }

        // Swift Evolution
        if let searchIndex {
            swiftEvolutionResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftEvolution,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            )) ?? []
        }

        // Swift.org
        if let searchIndex {
            swiftOrgResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftOrg,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            )) ?? []
        }

        // Swift Book
        if let searchIndex {
            swiftBookResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftBook,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            )) ?? []
        }

        // Swift Packages
        if let searchIndex {
            packagesResults = await (try? searchIndex.search(
                query: query,
                source: Shared.Constants.SourcePrefix.packages,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            )) ?? []
        }

        // Use shared formatter
        let formatter = UnifiedSearchMarkdownFormatter(
            query: query,
            framework: framework,
            config: .mcpDefault
        )
        let input = UnifiedSearchInput(
            docResults: docResults,
            archiveResults: archiveResults,
            sampleResults: sampleResults,
            higResults: higResults,
            swiftEvolutionResults: swiftEvolutionResults,
            swiftOrgResults: swiftOrgResults,
            swiftBookResults: swiftBookResults,
            packagesResults: packagesResults
        )
        var markdown = formatter.format(input)

        // Tip for AI about narrowing/expanding search
        markdown += "\n\n---\n\n"
        markdown += "_To narrow results, use `source` parameter: apple-docs, samples, hig, apple-archive, swift-evolution, swift-org, swift-book, packages_"

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

        let uri: String = try args.require(Shared.Constants.MCP.schemaParamURI)
        let formatString = args.format()
        let format: Search.Index.DocumentFormat = formatString == Shared.Constants.MCP.formatValueMarkdown
            ? .markdown : .json

        guard let documentContent = try await searchIndex.getDocumentContent(uri: uri, format: format) else {
            throw ToolError.invalidArgument(
                Shared.Constants.MCP.schemaParamURI,
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

        let framework = args.optional(Shared.Constants.MCP.schemaParamFramework)
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

        let projectId: String = try args.require(Shared.Constants.MCP.schemaParamProjectId)

        guard let project = try await sampleDatabase.getProject(id: projectId) else {
            throw ToolError.invalidArgument(
                Shared.Constants.MCP.schemaParamProjectId,
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
        markdown += "- **Size:** \(formatBytes(project.totalSize))\n"
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

        let projectId: String = try args.require(Shared.Constants.MCP.schemaParamProjectId)
        let filePath: String = try args.require(Shared.Constants.MCP.schemaParamFilePath)

        guard let file = try await sampleDatabase.getFile(projectId: projectId, path: filePath) else {
            throw ToolError.invalidArgument(
                Shared.Constants.MCP.schemaParamFilePath,
                "File not found: \(filePath) in project \(projectId)"
            )
        }

        var markdown = "# \(file.filename)\n\n"
        markdown += "**Project:** `\(file.projectId)`\n"
        markdown += "**Path:** `\(file.path)`\n"
        markdown += "**Size:** \(formatBytes(file.size))\n\n"

        let language = languageForExtension(file.fileExtension)

        markdown += "```\(language)\n"
        markdown += file.content
        if !file.content.hasSuffix("\n") {
            markdown += "\n"
        }
        markdown += "```\n"

        return CallToolResult(content: [.text(TextContent(text: markdown))])
    }

    // MARK: - Version Comparison

    /// Compare version strings (e.g., "13.0" vs "15.0")
    /// Returns true if lhs <= rhs (API was introduced before or at target version)
    private static func isVersion(_ lhs: String, lessThanOrEqualTo rhs: String) -> Bool {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }

        for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
            let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
            let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0

            if lhsValue < rhsValue { return true }
            if lhsValue > rhsValue { return false }
        }
        return true // Equal versions
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

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

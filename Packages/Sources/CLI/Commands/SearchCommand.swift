import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Search
import Services
import Shared

// MARK: - Search Command

/// CLI command for unified search across all documentation sources.
/// Mirrors MCP `search` tool functionality with `--source` parameter routing.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search Apple documentation, samples, HIG, and more",
        discussion: """
        Unified search across all documentation sources. By default, searches ALL sources
        for comprehensive results. Use --source to narrow to a specific source.

        SOURCES:
          (default)       Search ALL sources at once (docs, samples, HIG, etc.)
          apple-docs      Modern Apple API documentation only
          samples         Sample code projects with working examples
          hig             Human Interface Guidelines
          apple-archive   Legacy guides (Core Animation, Quartz 2D, KVO/KVC)
          swift-evolution Swift Evolution proposals
          swift-org       Swift.org documentation
          swift-book      The Swift Programming Language book
          packages        Swift package documentation

        SEMANTIC SEARCH:
          Search includes AST-extracted symbols from Swift source code.
          Find @Observable classes, async functions, View conformances, etc.
          Works across both documentation and sample code.

        EXAMPLES:
          cupertino search "SwiftUI view lifecycle"
          cupertino search "@Observable" --source samples
          cupertino search "Core Animation" --source apple-archive
          cupertino search "button styles" --source samples
          cupertino search "async throws" --source apple-docs
        """
    )

    @Argument(help: "Search query")
    var query: String

    @Option(
        name: .shortAndLong,
        help: """
        Filter by source: apple-docs, samples, hig, apple-archive, swift-evolution, swift-org, swift-book, packages, all
        """
    )
    var source: String?

    @Flag(
        name: .long,
        help: "Include Apple Archive documentation in results (excluded by default)"
    )
    var includeArchive: Bool = false

    @Option(
        name: .shortAndLong,
        help: "Filter by framework (e.g., swiftui, foundation, uikit)"
    )
    var framework: String?

    @Option(
        name: .shortAndLong,
        help: "Filter by programming language: swift, objc"
    )
    var language: String?

    @Option(
        name: .long,
        help: "Maximum number of results to return"
    )
    var limit: Int = Shared.Constants.Limit.defaultSearchLimit

    @Option(
        name: .long,
        help: "Filter to APIs available on iOS version (e.g., 13.0, 15.0)"
    )
    var minIos: String?

    @Option(
        name: .long,
        help: "Filter to APIs available on macOS version (e.g., 10.15, 12.0)"
    )
    var minMacos: String?

    @Option(
        name: .long,
        help: "Filter to APIs available on tvOS version (e.g., 13.0, 15.0)"
    )
    var minTvos: String?

    @Option(
        name: .long,
        help: "Filter to APIs available on watchOS version (e.g., 6.0, 8.0)"
    )
    var minWatchos: String?

    @Option(
        name: .long,
        help: "Filter to APIs available on visionOS version (e.g., 1.0, 2.0)"
    )
    var minVisionos: String?

    @Option(
        name: .long,
        help: "Path to search database"
    )
    var searchDb: String?

    @Option(
        name: .long,
        help: "Path to sample index database"
    )
    var sampleDb: String?

    @Option(
        name: .long,
        help: "Output format: text (default), json, markdown"
    )
    var format: OutputFormat = .text

    mutating func run() async throws {
        // Route based on source parameter
        // Default (nil) now searches ALL sources for better results (#81)
        switch source {
        case Shared.Constants.SourcePrefix.samples, Shared.Constants.SourcePrefix.appleSampleCode:
            try await runSampleSearch()
        case Shared.Constants.SourcePrefix.hig:
            try await runHIGSearch()
        case Shared.Constants.SourcePrefix.appleDocs,
             Shared.Constants.SourcePrefix.appleArchive,
             Shared.Constants.SourcePrefix.swiftEvolution,
             Shared.Constants.SourcePrefix.swiftOrg,
             Shared.Constants.SourcePrefix.swiftBook,
             Shared.Constants.SourcePrefix.packages:
            // Specific source requested: search only that source
            try await runDocsSearch()
        default:
            // Default (nil or "all"): search ALL sources for comprehensive results
            try await runUnifiedSearch()
        }
    }

    // MARK: - Documentation Search

    private func runDocsSearch() async throws {
        let results = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
            try await service.search(SearchQuery(
                text: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive,
                minimumiOS: minIos,
                minimumMacOS: minMacos,
                minimumTvOS: minTvos,
                minimumWatchOS: minWatchos,
                minimumVisionOS: minVisionos
            ))
        }

        // Fetch teaser results from all sources user didn't search
        let teasers = try await ServiceContainer.withTeaserService(
            searchDbPath: searchDb,
            sampleDbPath: resolveSampleDbPath()
        ) { service in
            await service.fetchAllTeasers(
                query: query,
                framework: framework,
                currentSource: source,
                includeArchive: includeArchive
            )
        }

        // Output results using formatters
        switch format {
        case .text:
            let formatter = TextSearchResultFormatter(
                query: query,
                source: source,
                teasers: teasers
            )
            Log.output(formatter.format(results))
        case .json:
            let formatter = JSONSearchResultFormatter()
            Log.output(formatter.format(results))
        case .markdown:
            let formatter = MarkdownSearchResultFormatter(
                query: query,
                filters: SearchFilters(
                    source: source,
                    framework: framework,
                    language: language,
                    minimumiOS: minIos,
                    minimumMacOS: minMacos,
                    minimumTvOS: minTvos,
                    minimumWatchOS: minWatchos,
                    minimumVisionOS: minVisionos
                ),
                config: .cliDefault,
                teasers: teasers
            )
            Log.output(formatter.format(results))
        }
    }

    // MARK: - Sample Search

    private func runSampleSearch() async throws {
        let dbPath = resolveSampleDbPath()

        let result = try await ServiceContainer.withSampleService(dbPath: dbPath) { service in
            try await service.search(SampleQuery(
                text: query,
                framework: framework,
                searchFiles: true,
                limit: limit
            ))
        }

        // Fetch teaser results from other sources
        let teasers = try await ServiceContainer.withTeaserService(
            searchDbPath: searchDb,
            sampleDbPath: resolveSampleDbPath()
        ) { service in
            await service.fetchAllTeasers(
                query: query,
                framework: framework,
                currentSource: Shared.Constants.SourcePrefix.samples,
                includeArchive: false
            )
        }

        // Output results using formatters
        switch format {
        case .text:
            let formatter = SampleSearchTextFormatter(query: query, framework: framework, teasers: teasers)
            Log.output(formatter.format(result))
        case .json:
            let formatter = SampleSearchJSONFormatter(query: query, framework: framework)
            Log.output(formatter.format(result))
        case .markdown:
            let formatter = SampleSearchMarkdownFormatter(query: query, framework: framework, teasers: teasers)
            Log.output(formatter.format(result))
        }
    }

    // MARK: - HIG Search

    private func runHIGSearch() async throws {
        let results = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
            try await service.search(SearchQuery(
                text: query,
                source: Shared.Constants.SourcePrefix.hig,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            ))
        }

        // Fetch teaser results from other sources
        let teasers = try await ServiceContainer.withTeaserService(
            searchDbPath: searchDb,
            sampleDbPath: resolveSampleDbPath()
        ) { service in
            await service.fetchAllTeasers(
                query: query,
                framework: framework,
                currentSource: Shared.Constants.SourcePrefix.hig,
                includeArchive: false
            )
        }

        let higQuery = HIGQuery(text: query, platform: nil, category: nil)

        switch format {
        case .text:
            let formatter = HIGTextFormatter(query: higQuery, teasers: teasers)
            Log.output(formatter.format(results))
        case .json:
            let formatter = HIGJSONFormatter(query: higQuery)
            Log.output(formatter.format(results))
        case .markdown:
            let formatter = HIGMarkdownFormatter(query: higQuery, config: .cliDefault, teasers: teasers)
            Log.output(formatter.format(results))
        }
    }

    // MARK: - Unified Search (All Sources)

    private func runUnifiedSearch() async throws {
        // Use UnifiedSearchService to search all 8 sources
        let input = try await ServiceContainer.withUnifiedSearchService(
            searchDbPath: searchDb,
            sampleDbPath: resolveSampleDbPath()
        ) { service in
            await service.searchAll(
                query: query,
                framework: framework,
                limit: limit
            )
        }

        switch format {
        case .text:
            // Formatter already includes tip about narrowing scope
            let formatter = UnifiedSearchTextFormatter(query: query, framework: framework)
            Log.output(formatter.format(input))
        case .json:
            let formatter = UnifiedSearchJSONFormatter(query: query, framework: framework)
            Log.output(formatter.format(input))
        case .markdown:
            // Use shared formatter (identical to MCP output)
            let formatter = UnifiedSearchMarkdownFormatter(
                query: query,
                framework: framework,
                config: .cliDefault
            )
            Log.output(formatter.format(input))
        }
    }

    // MARK: - Path Resolution

    private func resolveSampleDbPath() -> URL {
        if let sampleDb {
            return URL(fileURLWithPath: sampleDb).expandingTildeInPath
        }
        return SampleIndex.defaultDatabasePath
    }
}

// MARK: - Output Format

extension SearchCommand {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

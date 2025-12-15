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
        Unified search across all documentation sources. Use --source to specify the target:

        SOURCES:
          apple-docs      Modern Apple API documentation (default)
          samples         Sample code projects with working examples
          hig             Human Interface Guidelines
          apple-archive   Legacy guides (Core Animation, Quartz 2D, KVO/KVC)
          swift-evolution Swift Evolution proposals
          swift-org       Swift.org documentation
          swift-book      The Swift Programming Language book
          packages        Swift package documentation
          all             Search ALL sources at once

        EXAMPLES:
          cupertino search "SwiftUI view lifecycle"
          cupertino search "Core Animation" --source apple-archive
          cupertino search "button styles" --source samples
          cupertino search "navigation" --source hig
          cupertino search "actors" --source all
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
        switch source {
        case Shared.Constants.SourcePrefix.samples, Shared.Constants.SourcePrefix.appleSampleCode:
            try await runSampleSearch()
        case Shared.Constants.SourcePrefix.all:
            try await runUnifiedSearch()
        case Shared.Constants.SourcePrefix.hig:
            try await runHIGSearch()
        default:
            try await runDocsSearch()
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
        let teasers = await fetchAllTeasers()

        // Output results using formatters
        switch format {
        case .text:
            let formatter = TextSearchResultFormatter(query: query)
            var output = formatter.format(results)
            output += formatTeaserSectionText(teasers)
            Log.output(output)
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
                config: .cliDefault
            )
            var output = formatter.format(results)
            // Use shared TeaserMarkdownFormatter (same as MCP)
            let teaserFormatter = TeaserMarkdownFormatter()
            output += teaserFormatter.format(teasers)
            Log.output(output)
        }
    }

    // MARK: - Teaser Results

    // Uses shared TeaserResults from Services module

    /// Fetch teaser results from all sources the user didn't search
    private func fetchAllTeasers() async -> Services.TeaserResults {
        var teasers = Services.TeaserResults()
        let currentSource = source ?? Shared.Constants.SourcePrefix.appleDocs

        // Samples teaser (unless searching samples)
        if currentSource != Shared.Constants.SourcePrefix.samples,
           currentSource != Shared.Constants.SourcePrefix.appleSampleCode {
            teasers.samples = await fetchTeaserSamples()
        }

        // Archive teaser (unless searching archive or include_archive is set)
        if !includeArchive, currentSource != Shared.Constants.SourcePrefix.appleArchive {
            teasers.archive = await fetchTeaserFromSource(Shared.Constants.SourcePrefix.appleArchive)
        }

        // HIG teaser (unless searching HIG)
        if currentSource != Shared.Constants.SourcePrefix.hig {
            teasers.hig = await fetchTeaserFromSource(Shared.Constants.SourcePrefix.hig)
        }

        // Swift Evolution teaser (unless searching swift-evolution)
        if currentSource != Shared.Constants.SourcePrefix.swiftEvolution {
            teasers.swiftEvolution = await fetchTeaserFromSource(Shared.Constants.SourcePrefix.swiftEvolution)
        }

        // Swift.org teaser (unless searching swift-org)
        if currentSource != Shared.Constants.SourcePrefix.swiftOrg {
            teasers.swiftOrg = await fetchTeaserFromSource(Shared.Constants.SourcePrefix.swiftOrg)
        }

        // Swift Book teaser (unless searching swift-book)
        if currentSource != Shared.Constants.SourcePrefix.swiftBook {
            teasers.swiftBook = await fetchTeaserFromSource(Shared.Constants.SourcePrefix.swiftBook)
        }

        // Packages teaser (unless searching packages)
        if currentSource != Shared.Constants.SourcePrefix.packages {
            teasers.packages = await fetchTeaserFromSource(Shared.Constants.SourcePrefix.packages)
        }

        return teasers
    }

    /// Fetch a few sample projects as teaser (returns empty if unavailable)
    private func fetchTeaserSamples() async -> [SampleIndex.Project] {
        let dbPath = resolveSampleDbPath()
        do {
            return try await ServiceContainer.withSampleService(dbPath: dbPath) { service in
                let result = try await service.search(SampleQuery(
                    text: query,
                    framework: framework,
                    searchFiles: false,
                    limit: Shared.Constants.Limit.teaserLimit
                ))
                return result.projects
            }
        } catch {
            return []
        }
    }

    /// Fetch teaser results from a specific source
    private func fetchTeaserFromSource(_ sourceType: String) async -> [Search.Result] {
        do {
            return try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: sourceType,
                    framework: nil,
                    language: nil,
                    limit: Shared.Constants.Limit.teaserLimit,
                    includeArchive: sourceType == Shared.Constants.SourcePrefix.appleArchive
                ))
            }
        } catch {
            return []
        }
    }

    /// Format teaser section for CLI text output (different style from markdown)
    private func formatTeaserSectionText(_ teasers: Services.TeaserResults) -> String {
        var output = ""

        // Sample code teaser
        if !teasers.samples.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Sample Code:\n"
            for project in teasers.samples {
                output += "  • \(project.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.samples)\n"
        }

        // Archive teaser
        if !teasers.archive.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Apple Archive:\n"
            for result in teasers.archive {
                output += "  • \(result.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.appleArchive)\n"
        }

        // HIG teaser
        if !teasers.hig.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Human Interface Guidelines:\n"
            for result in teasers.hig {
                output += "  • \(result.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.hig)\n"
        }

        // Swift Evolution teaser
        if !teasers.swiftEvolution.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Swift Evolution:\n"
            for result in teasers.swiftEvolution {
                output += "  • \(result.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.swiftEvolution)\n"
        }

        // Swift.org teaser
        if !teasers.swiftOrg.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Swift.org:\n"
            for result in teasers.swiftOrg {
                output += "  • \(result.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.swiftOrg)\n"
        }

        // Swift Book teaser
        if !teasers.swiftBook.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Swift Book:\n"
            for result in teasers.swiftBook {
                output += "  • \(result.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.swiftBook)\n"
        }

        // Packages teaser
        if !teasers.packages.isEmpty {
            output += "\n" + String(repeating: "-", count: 40) + "\n"
            output += "Also in Swift Packages:\n"
            for result in teasers.packages {
                output += "  • \(result.title)\n"
            }
            output += "  → Use --source \(Shared.Constants.SourcePrefix.packages)\n"
        }

        return output
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

        // Output results using formatters
        switch format {
        case .text:
            let formatter = SampleSearchTextFormatter(query: query, framework: framework)
            Log.output(formatter.format(result))
        case .json:
            let formatter = SampleSearchJSONFormatter(query: query, framework: framework)
            Log.output(formatter.format(result))
        case .markdown:
            let formatter = SampleSearchMarkdownFormatter(query: query, framework: framework)
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

        let higQuery = HIGQuery(text: query, platform: nil, category: nil)

        switch format {
        case .text:
            let formatter = HIGTextFormatter(query: higQuery)
            Log.output(formatter.format(results))
        case .json:
            let formatter = HIGJSONFormatter(query: higQuery)
            Log.output(formatter.format(results))
        case .markdown:
            let formatter = HIGMarkdownFormatter(query: higQuery, config: .cliDefault)
            Log.output(formatter.format(results))
        }
    }

    // MARK: - Unified Search (All Sources)

    private func runUnifiedSearch() async throws {
        var docResults: [Search.Result] = []
        var archiveResults: [Search.Result] = []
        var sampleResults: [SampleIndex.Project] = []
        var higResults: [Search.Result] = []
        var swiftEvolutionResults: [Search.Result] = []
        var swiftOrgResults: [Search.Result] = []
        var swiftBookResults: [Search.Result] = []
        var packagesResults: [Search.Result] = []

        // Search Apple Documentation (modern)
        do {
            docResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.appleDocs,
                    framework: framework,
                    language: nil,
                    limit: limit,
                    includeArchive: false
                ))
            }
        } catch {
            Log.warning("Could not search documentation: \(error)")
        }

        // Search Apple Archive
        do {
            archiveResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.appleArchive,
                    framework: framework,
                    language: nil,
                    limit: limit,
                    includeArchive: true
                ))
            }
        } catch {
            Log.warning("Could not search archive: \(error)")
        }

        // Search Sample Code
        do {
            let dbPath = resolveSampleDbPath()
            sampleResults = try await ServiceContainer.withSampleService(dbPath: dbPath) { service in
                let result = try await service.search(SampleQuery(
                    text: query,
                    framework: framework,
                    searchFiles: false,
                    limit: limit
                ))
                return result.projects
            }
        } catch {
            Log.warning("Could not search samples: \(error)")
        }

        // Search HIG
        do {
            higResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.hig,
                    framework: nil,
                    language: nil,
                    limit: limit,
                    includeArchive: false
                ))
            }
        } catch {
            Log.warning("Could not search HIG: \(error)")
        }

        // Search Swift Evolution
        do {
            swiftEvolutionResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.swiftEvolution,
                    framework: nil,
                    language: nil,
                    limit: limit,
                    includeArchive: false
                ))
            }
        } catch {
            Log.warning("Could not search Swift Evolution: \(error)")
        }

        // Search Swift.org
        do {
            swiftOrgResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.swiftOrg,
                    framework: nil,
                    language: nil,
                    limit: limit,
                    includeArchive: false
                ))
            }
        } catch {
            Log.warning("Could not search Swift.org: \(error)")
        }

        // Search Swift Book
        do {
            swiftBookResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.swiftBook,
                    framework: nil,
                    language: nil,
                    limit: limit,
                    includeArchive: false
                ))
            }
        } catch {
            Log.warning("Could not search Swift Book: \(error)")
        }

        // Search Packages
        do {
            packagesResults = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
                try await service.search(SearchQuery(
                    text: query,
                    source: Shared.Constants.SourcePrefix.packages,
                    framework: nil,
                    language: nil,
                    limit: limit,
                    includeArchive: false
                ))
            }
        } catch {
            Log.warning("Could not search packages: \(error)")
        }

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

        // Tip about narrowing scope (for --source all)
        let scopeTip = """

        ----------------------------------------
        Tip: Narrow your search with --source:
          apple-docs, samples, hig, apple-archive,
          swift-evolution, swift-org, swift-book, packages
        """

        switch format {
        case .text:
            let formatter = UnifiedSearchTextFormatter(query: query, framework: framework)
            Log.output(formatter.format(input) + scopeTip)
        case .json:
            let formatter = UnifiedSearchJSONFormatter(query: query, framework: framework)
            Log.output(formatter.format(input))
        case .markdown:
            let formatter = UnifiedSearchMarkdownFormatter(
                query: query,
                framework: framework,
                config: .cliDefault
            )
            Log
                .output(formatter
                    .format(input) +
                    "\n\n---\n\n💡 **Tip:** Narrow your search with `--source`: apple-docs, samples, hig, apple-archive, swift-evolution, swift-org, swift-book, packages")
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

// MARK: - Text Formatter for Unified Search

struct UnifiedSearchTextFormatter: ResultFormatter {
    private let query: String
    private let framework: String?

    init(query: String, framework: String?) {
        self.query = query
        self.framework = framework
    }

    func format(_ input: UnifiedSearchInput) -> String {
        var output = "Unified Search Results for \"\(query)\"\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        if let framework {
            output += "Filtered to framework: \(framework)\n\n"
        }

        output += "Total: \(input.totalCount) results across all sources\n\n"

        // Only show sections with results
        if !input.docResults.isEmpty {
            output += "APPLE DOCUMENTATION (\(input.docResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.docResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
                if let availability = result.availabilityString, !availability.isEmpty {
                    output += "    Availability: \(availability)\n"
                }
            }
            output += "\n"
        }

        if !input.sampleResults.isEmpty {
            output += "SAMPLE CODE (\(input.sampleResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for project in input.sampleResults {
                output += "  \(project.title)\n"
                output += "    ID: \(project.id)\n"
            }
            output += "\n"
        }

        if !input.higResults.isEmpty {
            output += "HUMAN INTERFACE GUIDELINES (\(input.higResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.higResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
            }
            output += "\n"
        }

        if !input.archiveResults.isEmpty {
            output += "APPLE ARCHIVE (\(input.archiveResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.archiveResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
            }
            output += "\n"
        }

        if !input.swiftEvolutionResults.isEmpty {
            output += "SWIFT EVOLUTION (\(input.swiftEvolutionResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.swiftEvolutionResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
            }
            output += "\n"
        }

        if !input.swiftOrgResults.isEmpty {
            output += "SWIFT.ORG (\(input.swiftOrgResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.swiftOrgResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
            }
            output += "\n"
        }

        if !input.swiftBookResults.isEmpty {
            output += "SWIFT BOOK (\(input.swiftBookResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.swiftBookResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
            }
            output += "\n"
        }

        if !input.packagesResults.isEmpty {
            output += "SWIFT PACKAGES (\(input.packagesResults.count))\n"
            output += String(repeating: "-", count: 40) + "\n"
            for result in input.packagesResults {
                output += "  \(result.title)\n"
                output += "    URI: \(result.uri)\n"
            }
            output += "\n"
        }

        if input.totalCount == 0 {
            output += "No results found across any source.\n\n"
        }

        return output
    }
}

// MARK: - JSON Formatter for Unified Search

struct UnifiedSearchJSONFormatter: ResultFormatter {
    private let query: String
    private let framework: String?

    init(query: String, framework: String?) {
        self.query = query
        self.framework = framework
    }

    func format(_ input: UnifiedSearchInput) -> String {
        struct JSONOutput: Encodable {
            let query: String
            let framework: String?
            let documentation: [DocResult]
            let archive: [DocResult]
            let samples: [SampleResult]

            struct DocResult: Encodable {
                let title: String
                let framework: String
                let uri: String
                let availability: String?
                let summary: String
            }

            struct SampleResult: Encodable {
                let id: String
                let title: String
                let frameworks: [String]
                let fileCount: Int
                let description: String
            }
        }

        let output = JSONOutput(
            query: query,
            framework: framework,
            documentation: input.docResults.map { result in
                JSONOutput.DocResult(
                    title: result.title,
                    framework: result.framework,
                    uri: result.uri,
                    availability: result.availabilityString,
                    summary: result.summary
                )
            },
            archive: input.archiveResults.map { result in
                JSONOutput.DocResult(
                    title: result.title,
                    framework: result.framework,
                    uri: result.uri,
                    availability: result.availabilityString,
                    summary: result.summary
                )
            },
            samples: input.sampleResults.map { project in
                JSONOutput.SampleResult(
                    id: project.id,
                    title: project.title,
                    frameworks: project.frameworks,
                    fileCount: project.fileCount,
                    description: project.description
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(output),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{\"error\": \"Failed to encode results\"}"
        }

        return json
    }
}

// MARK: - HIG Text Formatter

struct HIGTextFormatter: ResultFormatter {
    private let query: HIGQuery

    init(query: HIGQuery) {
        self.query = query
    }

    func format(_ results: [Search.Result]) -> String {
        var output = "HIG Search Results for \"\(query.text)\"\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        if let platform = query.platform {
            output += "Platform: \(platform)\n"
        }
        if let category = query.category {
            output += "Category: \(category)\n"
        }
        if query.platform != nil || query.category != nil {
            output += "\n"
        }

        output += "Found \(results.count) guideline(s)\n\n"

        if results.isEmpty {
            output += "No Human Interface Guidelines found matching your query.\n\n"
            output += "Tips:\n"
            output += "- Try broader design terms (e.g., 'buttons', 'typography', 'navigation')\n"
            output += "- Specify a platform: iOS, macOS, watchOS, visionOS, tvOS\n"
            output += "- Specify a category: foundations, patterns, components, technologies, inputs\n"
            return output
        }

        for (index, result) in results.enumerated() {
            output += "\(index + 1). \(result.title)\n"
            output += "   URI: \(result.uri)\n"
            if let availability = result.availabilityString, !availability.isEmpty {
                output += "   Availability: \(availability)\n"
            }
            output += "\n   \(result.summary)\n\n"
        }

        return output
    }
}

// MARK: - HIG JSON Formatter

struct HIGJSONFormatter: ResultFormatter {
    private let query: HIGQuery

    init(query: HIGQuery) {
        self.query = query
    }

    func format(_ results: [Search.Result]) -> String {
        struct JSONOutput: Encodable {
            let query: String
            let platform: String?
            let category: String?
            let count: Int
            let results: [HIGResult]

            struct HIGResult: Encodable {
                let title: String
                let uri: String
                let availability: String?
                let summary: String
            }
        }

        let output = JSONOutput(
            query: query.text,
            platform: query.platform,
            category: query.category,
            count: results.count,
            results: results.map { result in
                JSONOutput.HIGResult(
                    title: result.title,
                    uri: result.uri,
                    availability: result.availabilityString,
                    summary: result.summary
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(output),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{\"error\": \"Failed to encode results\"}"
        }

        return json
    }
}

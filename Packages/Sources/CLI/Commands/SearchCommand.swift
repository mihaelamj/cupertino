import ArgumentParser
import Foundation
import Logging
import Services
import Shared

// MARK: - Search Command

/// CLI command for searching documentation - mirrors MCP tool functionality.
/// Allows AI agents and users to search from the command line.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search Apple documentation, Swift Evolution, and Swift packages"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(
        name: .shortAndLong,
        help: """
        Filter by source: apple-docs, swift-evolution, swift-org, swift-book, packages, apple-sample-code, apple-archive, hig
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
        help: "Path to search database"
    )
    var searchDb: String?

    @Option(
        name: .long,
        help: "Output format: text (default), json, markdown"
    )
    var format: OutputFormat = .text

    mutating func run() async throws {
        // Use ServiceContainer for managed lifecycle
        let results = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
            try await service.search(SearchQuery(
                text: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive
            ))
        }

        // Output results using formatters
        switch format {
        case .text:
            let formatter = TextSearchResultFormatter(query: query)
            Log.output(formatter.format(results))
        case .json:
            let formatter = JSONSearchResultFormatter()
            Log.output(formatter.format(results))
        case .markdown:
            let formatter = MarkdownSearchResultFormatter(
                query: query,
                filters: SearchFilters(source: source, framework: framework, language: language),
                config: .cliDefault
            )
            Log.output(formatter.format(results))
        }
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

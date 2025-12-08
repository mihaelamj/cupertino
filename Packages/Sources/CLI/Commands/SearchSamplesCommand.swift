import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Services
import Shared

// MARK: - Search Samples Command

/// CLI command for searching sample code projects - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SearchSamplesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search-samples",
        abstract: "Search Apple sample code projects and files"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(
        name: .shortAndLong,
        help: "Filter by framework (e.g., swiftui, uikit, appkit)"
    )
    var framework: String?

    @Flag(
        name: .long,
        help: "Search file contents in addition to project metadata"
    )
    var searchFiles: Bool = false

    @Option(
        name: .long,
        help: "Maximum number of results to return"
    )
    var limit: Int = Shared.Constants.Limit.defaultSearchLimit

    @Option(
        name: .long,
        help: "Output format: text (default), json, markdown"
    )
    var format: OutputFormat = .text

    @Option(
        name: .long,
        help: "Path to sample index database"
    )
    var sampleDb: String?

    mutating func run() async throws {
        // Resolve database path
        let dbPath = resolveSampleDbPath()

        // Use ServiceContainer for managed lifecycle
        let result = try await ServiceContainer.withSampleService(dbPath: dbPath) { service in
            try await service.search(SampleQuery(
                text: query,
                framework: framework,
                searchFiles: searchFiles,
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

    // MARK: - Path Resolution

    private func resolveSampleDbPath() -> URL {
        if let sampleDb {
            return URL(fileURLWithPath: sampleDb).expandingTildeInPath
        }
        return SampleIndex.defaultDatabasePath
    }
}

// MARK: - Output Format

extension SearchSamplesCommand {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

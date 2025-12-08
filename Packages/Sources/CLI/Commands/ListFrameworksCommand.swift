import ArgumentParser
import Foundation
import Logging
import Services
import Shared

// MARK: - List Frameworks Command

/// CLI command for listing available frameworks - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ListFrameworksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-frameworks",
        abstract: "List available frameworks with document counts"
    )

    @Option(
        name: .long,
        help: "Output format: text (default), json, markdown"
    )
    var format: OutputFormat = .text

    @Option(
        name: .long,
        help: "Path to search database"
    )
    var searchDb: String?

    mutating func run() async throws {
        // Use ServiceContainer for managed lifecycle
        let (frameworks, totalDocs) = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
            let frameworks = try await service.listFrameworks()
            let totalDocs = try await service.documentCount()
            return (frameworks, totalDocs)
        }

        // Output results using formatters
        switch format {
        case .text:
            let formatter = FrameworksTextFormatter(totalDocs: totalDocs)
            Log.output(formatter.format(frameworks))
        case .json:
            let formatter = FrameworksJSONFormatter()
            Log.output(formatter.format(frameworks))
        case .markdown:
            let formatter = FrameworksMarkdownFormatter(totalDocs: totalDocs)
            Log.output(formatter.format(frameworks))
        }
    }
}

// MARK: - Output Format

extension ListFrameworksCommand {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

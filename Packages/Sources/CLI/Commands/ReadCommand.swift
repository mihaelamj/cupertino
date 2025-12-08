import ArgumentParser
import Foundation
import Logging
import Search
import Services
import Shared

// MARK: - Read Command

/// CLI command for reading full document content by URI.
/// Mirrors MCP read_document tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a document by URI"
    )

    @Argument(help: "Document URI (e.g., apple-docs://swiftui/documentation_swiftui_view)")
    var uri: String

    @Option(
        name: .long,
        help: "Output format: json (default), markdown"
    )
    var format: OutputFormat = .json

    @Option(
        name: .long,
        help: "Path to search database"
    )
    var searchDb: String?

    mutating func run() async throws {
        // Use ServiceContainer for managed lifecycle
        let documentFormat: Search.Index.DocumentFormat = format == .markdown ? .markdown : .json

        let content = try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
            try await service.read(uri: uri, format: documentFormat)
        }

        guard let content else {
            Log.error("Document not found: \(uri)")
            throw ExitCode.failure
        }

        Log.output(content)
    }
}

// MARK: - Output Format

extension ReadCommand {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case json
        case markdown
    }
}

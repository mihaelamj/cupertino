import ArgumentParser
import Foundation
import Logging
import Search
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
        // Resolve database path
        let dbPath = resolveSearchDbPath()

        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            Log.error("Search database not found at \(dbPath.path)")
            Log.output("Run 'cupertino save' to build the search index first.")
            throw ExitCode.failure
        }

        // Initialize search index
        let searchIndex = try await Search.Index(dbPath: dbPath)
        defer {
            Task {
                await searchIndex.disconnect()
            }
        }

        // Get document content
        let documentFormat: Search.Index.DocumentFormat = format == .markdown ? .markdown : .json

        guard let content = try await searchIndex.getDocumentContent(uri: uri, format: documentFormat) else {
            Log.error("Document not found: \(uri)")
            throw ExitCode.failure
        }

        Log.output(content)
    }

    // MARK: - Path Resolution

    private func resolveSearchDbPath() -> URL {
        if let searchDb {
            return URL(fileURLWithPath: searchDb).expandingTildeInPath
        }
        return Shared.Constants.defaultSearchDatabase
    }
}

// MARK: - Output Format

extension ReadCommand {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case json
        case markdown
    }
}

// MARK: - URL Extension

private extension URL {
    var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            let expandedPath = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath)
        }
        return self
    }
}

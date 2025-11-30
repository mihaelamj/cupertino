import ArgumentParser
import Foundation
import Search
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
        Filter by source: apple-docs, swift-evolution, swift-org, swift-book, packages, apple-sample-code
        """
    )
    var source: String?

    @Option(
        name: .shortAndLong,
        help: "Filter by framework (e.g., swiftui, foundation, uikit)"
    )
    var framework: String?

    @Option(
        name: .shortAndLong,
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
        // Resolve database path
        let dbPath = resolveSearchDbPath()

        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            print("Error: Search database not found at \(dbPath.path)")
            print("Run 'cupertino save' to build the search index first.")
            throw ExitCode.failure
        }

        // Initialize search index
        let searchIndex = try await Search.Index(dbPath: dbPath)
        defer {
            Task {
                await searchIndex.disconnect()
            }
        }

        // Perform search
        let results = try await searchIndex.search(
            query: query,
            source: source,
            framework: framework,
            limit: limit
        )

        // Output results
        switch format {
        case .text:
            outputText(results)
        case .json:
            outputJSON(results)
        case .markdown:
            outputMarkdown(results)
        }
    }

    // MARK: - Path Resolution

    private func resolveSearchDbPath() -> URL {
        if let searchDb {
            return URL(fileURLWithPath: searchDb).expandingTildeInPath
        }
        return Shared.Constants.defaultSearchDatabase
    }

    // MARK: - Output Formatting

    private func outputText(_ results: [Search.Result]) {
        if results.isEmpty {
            print("No results found for '\(query)'")
            return
        }

        print("Found \(results.count) result(s) for '\(query)':\n")

        for (index, result) in results.enumerated() {
            print("[\(index + 1)] \(result.title)")
            print("    Source: \(result.source) | Framework: \(result.framework)")
            print("    URI: \(result.uri)")

            // Show summary
            if !result.summary.isEmpty {
                print("    \(result.summary)")
                if result.summaryTruncated {
                    print("    ...")
                    print("    [truncated at ~\(result.summary.split(separator: " ").count) words] Full document: \(result.uri)")
                }
            }

            print()
        }
    }

    private func outputJSON(_ results: [Search.Result]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(results)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error encoding JSON: \(error)")
        }
    }

    private func outputMarkdown(_ results: [Search.Result]) {
        if results.isEmpty {
            print("# Search Results\n\nNo results found for '\(query)'")
            return
        }

        print("# Search Results for '\(query)'\n")
        print("Found \(results.count) result(s).\n")

        for (index, result) in results.enumerated() {
            print("## \(index + 1). \(result.title)\n")
            print("- **Source:** \(result.source)")
            print("- **Framework:** \(result.framework)")
            print("- **URI:** `\(result.uri)`")

            if !result.summary.isEmpty {
                print("\n> \(result.summary)")
            }

            print()
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

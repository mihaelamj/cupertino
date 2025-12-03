import ArgumentParser
import Foundation
import Logging
import Search
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

        // Get frameworks
        let frameworks = try await searchIndex.listFrameworks()

        // Output results
        switch format {
        case .text:
            outputText(frameworks)
        case .json:
            outputJSON(frameworks)
        case .markdown:
            outputMarkdown(frameworks)
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

    private func outputText(_ frameworks: [String: Int]) {
        let total = frameworks.values.reduce(0, +)
        let sorted = frameworks.sorted { $0.value > $1.value }

        Log.output("Available Frameworks")
        Log.output("Total: \(frameworks.count) frameworks, \(total) documents")
        Log.output("")

        if frameworks.isEmpty {
            Log.output("No frameworks found. Run 'cupertino save' to build the search index.")
            return
        }

        for (framework, count) in sorted {
            Log.output("  \(framework): \(count) documents")
        }
    }

    private func outputJSON(_ frameworks: [String: Int]) {
        struct Output: Encodable {
            let totalFrameworks: Int
            let totalDocuments: Int
            let frameworks: [FrameworkOutput]
        }

        struct FrameworkOutput: Encodable {
            let name: String
            let documentCount: Int
        }

        let total = frameworks.values.reduce(0, +)
        let sorted = frameworks.sorted { $0.value > $1.value }

        let output = Output(
            totalFrameworks: frameworks.count,
            totalDocuments: total,
            frameworks: sorted.map { FrameworkOutput(name: $0.key, documentCount: $0.value) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(output)
            if let jsonString = String(data: data, encoding: .utf8) {
                Log.output(jsonString)
            }
        } catch {
            Log.error("Error encoding JSON: \(error)")
        }
    }

    private func outputMarkdown(_ frameworks: [String: Int]) {
        let total = frameworks.values.reduce(0, +)
        let sorted = frameworks.sorted { $0.value > $1.value }

        Log.output("# Available Frameworks\n")
        Log.output("Total: **\(frameworks.count)** frameworks, **\(total)** documents\n")

        if frameworks.isEmpty {
            Log.output("_No frameworks found. Run `cupertino save` to build the search index._")
            return
        }

        Log.output("| Framework | Documents |")
        Log.output("|-----------|----------:|")

        for (framework, count) in sorted {
            Log.output("| \(framework) | \(count) |")
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

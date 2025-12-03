import ArgumentParser
import Foundation
import Logging
import SampleIndex
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

        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            Log.error("Sample index not found at \(dbPath.path)")
            Log.output("Run 'cupertino index' to build the sample index first.")
            throw ExitCode.failure
        }

        // Initialize database
        let database = try await SampleIndex.Database(dbPath: dbPath)
        defer {
            Task {
                await database.disconnect()
            }
        }

        // Search projects
        let projects = try await database.searchProjects(query: query, framework: framework, limit: limit)

        // Optionally search files
        var files: [SampleIndex.Database.FileSearchResult] = []
        if searchFiles {
            files = try await database.searchFiles(query: query, projectId: nil, limit: limit)
        }

        // Output results
        switch format {
        case .text:
            outputText(projects, files: files)
        case .json:
            outputJSON(projects, files: files)
        case .markdown:
            outputMarkdown(projects, files: files)
        }
    }

    // MARK: - Path Resolution

    private func resolveSampleDbPath() -> URL {
        if let sampleDb {
            return URL(fileURLWithPath: sampleDb).expandingTildeInPath
        }
        return SampleIndex.defaultDatabasePath
    }

    // MARK: - Output Formatting

    private func outputText(_ projects: [SampleIndex.Project], files: [SampleIndex.Database.FileSearchResult]) {
        if projects.isEmpty, files.isEmpty {
            Log.output("No results found for '\(query)'")
            return
        }

        Log.output("Search Results for '\(query)'")

        if let framework {
            Log.output("Filtered by: \(framework)")
        }

        Log.output("")

        // Projects
        if !projects.isEmpty {
            Log.output("Projects (\(projects.count) found):")
            Log.output("")

            for (index, project) in projects.enumerated() {
                Log.output("[\(index + 1)] \(project.title)")
                Log.output("    ID: \(project.id)")
                Log.output("    Frameworks: \(project.frameworks.joined(separator: ", "))")
                Log.output("    Files: \(project.fileCount)")

                if !project.description.isEmpty {
                    Log.output("    \(project.description.prefix(200))...")
                }

                Log.output("")
            }
        }

        // Files
        if !files.isEmpty {
            Log.output("Matching Files (\(files.count) found):")
            Log.output("")

            for (index, file) in files.prefix(10).enumerated() {
                Log.output("[\(index + 1)] \(file.filename)")
                Log.output("    Project: \(file.projectId)")
                Log.output("    Path: \(file.path)")
                Log.output("    > \(file.snippet)")
                Log.output("")
            }
        }

        Log.output("Tip: Use 'cupertino read-sample <project_id>' to view project details")
    }

    private func outputJSON(_ projects: [SampleIndex.Project], files: [SampleIndex.Database.FileSearchResult]) {
        struct Output: Encodable {
            let query: String
            let framework: String?
            let projects: [ProjectOutput]
            let files: [FileOutput]
        }

        struct ProjectOutput: Encodable {
            let id: String
            let title: String
            let description: String
            let frameworks: [String]
            let fileCount: Int
        }

        struct FileOutput: Encodable {
            let projectId: String
            let path: String
            let filename: String
            let snippet: String
            let rank: Double
        }

        let output = Output(
            query: query,
            framework: framework,
            projects: projects.map {
                ProjectOutput(
                    id: $0.id,
                    title: $0.title,
                    description: $0.description,
                    frameworks: $0.frameworks,
                    fileCount: $0.fileCount
                )
            },
            files: files.map {
                FileOutput(
                    projectId: $0.projectId,
                    path: $0.path,
                    filename: $0.filename,
                    snippet: $0.snippet,
                    rank: $0.rank
                )
            }
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

    private func outputMarkdown(_ projects: [SampleIndex.Project], files: [SampleIndex.Database.FileSearchResult]) {
        Log.output("# Sample Code Search: \"\(query)\"\n")

        if let framework {
            Log.output("_Filtered to framework: **\(framework)**_\n")
        }

        // Projects
        Log.output("## Projects (\(projects.count) found)\n")

        if projects.isEmpty {
            Log.output("_No matching projects found._\n")
        } else {
            for (index, project) in projects.enumerated() {
                Log.output("### \(index + 1). \(project.title)\n")
                Log.output("- **ID:** `\(project.id)`")
                Log.output("- **Frameworks:** \(project.frameworks.joined(separator: ", "))")
                Log.output("- **Files:** \(project.fileCount)\n")

                if !project.description.isEmpty {
                    Log.output("\(project.description)\n")
                }
            }
        }

        // Files
        if !files.isEmpty {
            Log.output("\n## Matching Files (\(files.count) found)\n")

            for (index, file) in files.prefix(10).enumerated() {
                Log.output("### \(index + 1). \(file.filename)\n")
                Log.output("- **Project:** `\(file.projectId)`")
                Log.output("- **Path:** `\(file.path)`\n")
                Log.output("> \(file.snippet)\n")
            }
        }
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

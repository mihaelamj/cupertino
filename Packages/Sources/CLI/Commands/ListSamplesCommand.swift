import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Shared

// MARK: - List Samples Command

/// CLI command for listing sample code projects - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ListSamplesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-samples",
        abstract: "List indexed Apple sample code projects"
    )

    @Option(
        name: .shortAndLong,
        help: "Filter by framework (e.g., swiftui, uikit, appkit)"
    )
    var framework: String?

    @Option(
        name: .long,
        help: "Maximum number of results to return"
    )
    var limit: Int = 50

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

        // List projects
        let projects = try await database.listProjects(framework: framework, limit: limit)
        let totalProjects = try await database.projectCount()
        let totalFiles = try await database.fileCount()

        // Output results
        switch format {
        case .text:
            outputText(projects, totalProjects: totalProjects, totalFiles: totalFiles)
        case .json:
            outputJSON(projects, totalProjects: totalProjects, totalFiles: totalFiles)
        case .markdown:
            outputMarkdown(projects, totalProjects: totalProjects, totalFiles: totalFiles)
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

    private func outputText(_ projects: [SampleIndex.Project], totalProjects: Int, totalFiles: Int) {
        Log.output("Sample Code Projects")
        Log.output("Total: \(totalProjects) projects, \(totalFiles) files")

        if let framework {
            Log.output("Filtered by: \(framework)")
        }

        Log.output("")

        if projects.isEmpty {
            Log.output("No projects found. Run 'cupertino index' to index sample code.")
            return
        }

        for (index, project) in projects.enumerated() {
            Log.output("[\(index + 1)] \(project.title)")
            Log.output("    ID: \(project.id)")
            Log.output("    Frameworks: \(project.frameworks.joined(separator: ", "))")
            Log.output("    Files: \(project.fileCount)")
            Log.output("")
        }
    }

    private func outputJSON(_ projects: [SampleIndex.Project], totalProjects: Int, totalFiles: Int) {
        struct Output: Encodable {
            let totalProjects: Int
            let totalFiles: Int
            let framework: String?
            let projects: [ProjectOutput]
        }

        struct ProjectOutput: Encodable {
            let id: String
            let title: String
            let description: String
            let frameworks: [String]
            let fileCount: Int
        }

        let output = Output(
            totalProjects: totalProjects,
            totalFiles: totalFiles,
            framework: framework,
            projects: projects.map {
                ProjectOutput(
                    id: $0.id,
                    title: $0.title,
                    description: $0.description,
                    frameworks: $0.frameworks,
                    fileCount: $0.fileCount
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

    private func outputMarkdown(_ projects: [SampleIndex.Project], totalProjects: Int, totalFiles: Int) {
        Log.output("# Sample Code Projects\n")
        Log.output("Total: **\(totalProjects)** projects, **\(totalFiles)** files\n")

        if let framework {
            Log.output("_Filtered to framework: **\(framework)**_\n")
        }

        if projects.isEmpty {
            Log.output("_No projects found. Run `cupertino index` to index sample code._")
            return
        }

        Log.output("| Project | Frameworks | Files |")
        Log.output("|---------|-----------|------:|")

        for project in projects {
            let frameworks = project.frameworks.joined(separator: ", ")
            Log.output("| `\(project.id)` | \(frameworks) | \(project.fileCount) |")
        }
    }
}

// MARK: - Output Format

extension ListSamplesCommand {
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

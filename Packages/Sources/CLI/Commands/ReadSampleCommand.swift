import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Shared

// MARK: - Read Sample Command

/// CLI command for reading a sample project's README - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ReadSampleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read-sample",
        abstract: "Read a sample project's README and metadata"
    )

    @Argument(help: "Project ID (e.g., building-a-document-based-app-with-swiftui)")
    var projectId: String

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

        // Get project
        guard let project = try await database.getProject(id: projectId) else {
            Log.error("Project not found: \(projectId)")
            Log.output("Use 'cupertino list-samples' or 'cupertino search-samples' to find valid project IDs.")
            throw ExitCode.failure
        }

        // Get files
        let files = try await database.listFiles(projectId: projectId)

        // Output results
        switch format {
        case .text:
            outputText(project, files: files)
        case .json:
            outputJSON(project, files: files)
        case .markdown:
            outputMarkdown(project, files: files)
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

    private func outputText(_ project: SampleIndex.Project, files: [SampleIndex.File]) {
        Log.output(project.title)
        Log.output(String(repeating: "=", count: project.title.count))
        Log.output("")
        Log.output("Project ID: \(project.id)")
        Log.output("Frameworks: \(project.frameworks.joined(separator: ", "))")
        Log.output("Files: \(project.fileCount)")
        Log.output("Size: \(formatBytes(project.totalSize))")

        if !project.webURL.isEmpty {
            Log.output("Apple Developer: \(project.webURL)")
        }

        Log.output("")

        if !project.description.isEmpty {
            Log.output("Description:")
            Log.output(project.description)
            Log.output("")
        }

        if let readme = project.readme, !readme.isEmpty {
            Log.output("README:")
            Log.output(readme)
            Log.output("")
        }

        if !files.isEmpty {
            Log.output("Files (\(files.count) total):")
            for file in files.prefix(30) {
                Log.output("  - \(file.path)")
            }
            if files.count > 30 {
                Log.output("  ... and \(files.count - 30) more files")
            }
        }

        Log.output("")
        Log.output("Tip: Use 'cupertino read-sample-file \(project.id) <path>' to view source code")
    }

    private func outputJSON(_ project: SampleIndex.Project, files: [SampleIndex.File]) {
        struct Output: Encodable {
            let id: String
            let title: String
            let description: String
            let frameworks: [String]
            let readme: String?
            let webURL: String
            let fileCount: Int
            let totalSize: Int
            let files: [String]
        }

        let output = Output(
            id: project.id,
            title: project.title,
            description: project.description,
            frameworks: project.frameworks,
            readme: project.readme,
            webURL: project.webURL,
            fileCount: project.fileCount,
            totalSize: project.totalSize,
            files: files.map(\.path)
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

    private func outputMarkdown(_ project: SampleIndex.Project, files: [SampleIndex.File]) {
        Log.output("# \(project.title)\n")
        Log.output("**Project ID:** `\(project.id)`\n")

        if !project.description.isEmpty {
            Log.output("## Description\n")
            Log.output("\(project.description)\n")
        }

        Log.output("## Metadata\n")
        Log.output("- **Frameworks:** \(project.frameworks.joined(separator: ", "))")
        Log.output("- **Files:** \(project.fileCount)")
        Log.output("- **Size:** \(formatBytes(project.totalSize))")

        if !project.webURL.isEmpty {
            Log.output("- **Apple Developer:** \(project.webURL)")
        }

        Log.output("")

        if let readme = project.readme, !readme.isEmpty {
            Log.output("## README\n")
            Log.output(readme)
            Log.output("")
        }

        if !files.isEmpty {
            Log.output("## Files (\(files.count) total)\n")
            for file in files.prefix(30) {
                Log.output("- `\(file.path)`")
            }
            if files.count > 30 {
                Log.output("- _... and \(files.count - 30) more files_")
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Output Format

extension ReadSampleCommand {
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

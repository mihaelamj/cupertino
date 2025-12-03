import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Shared

// MARK: - Read Sample File Command

/// CLI command for reading a specific file from a sample project - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ReadSampleFileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read-sample-file",
        abstract: "Read a source file from a sample project"
    )

    @Argument(help: "Project ID (e.g., building-a-document-based-app-with-swiftui)")
    var projectId: String

    @Argument(help: "File path within the project (e.g., ContentView.swift)")
    var filePath: String

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

        // Get file
        guard let file = try await database.getFile(projectId: projectId, path: filePath) else {
            Log.error("File not found: \(filePath) in project \(projectId)")
            Log.output("Use 'cupertino read-sample \(projectId)' to list available files.")
            throw ExitCode.failure
        }

        // Output results
        switch format {
        case .text:
            outputText(file)
        case .json:
            outputJSON(file)
        case .markdown:
            outputMarkdown(file)
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

    private func outputText(_ file: SampleIndex.File) {
        Log.output("// File: \(file.path)")
        Log.output("// Project: \(file.projectId)")
        Log.output("// Size: \(formatBytes(file.size))")
        Log.output("")
        Log.output(file.content)
    }

    private func outputJSON(_ file: SampleIndex.File) {
        struct Output: Encodable {
            let projectId: String
            let path: String
            let filename: String
            let size: Int
            let content: String
        }

        let output = Output(
            projectId: file.projectId,
            path: file.path,
            filename: file.filename,
            size: file.size,
            content: file.content
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

    private func outputMarkdown(_ file: SampleIndex.File) {
        Log.output("# \(file.filename)\n")
        Log.output("**Project:** `\(file.projectId)`")
        Log.output("**Path:** `\(file.path)`")
        Log.output("**Size:** \(formatBytes(file.size))\n")

        let language = languageForExtension(file.fileExtension)
        Log.output("```\(language)")
        Log.output(file.content)
        if !file.content.hasSuffix("\n") {
            Log.output("")
        }
        Log.output("```")
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func languageForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "h", "m", "mm": return "objc"
        case "c": return "c"
        case "cpp", "hpp": return "cpp"
        case "metal": return "metal"
        case "json": return "json"
        case "plist": return "xml"
        case "md": return "markdown"
        case "strings": return "properties"
        default: return ext
        }
    }
}

// MARK: - Output Format

extension ReadSampleFileCommand {
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

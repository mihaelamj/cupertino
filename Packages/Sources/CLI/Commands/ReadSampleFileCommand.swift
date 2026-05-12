import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Services
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Read Sample File Command

/// CLI command for reading a specific file from a sample project - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension Command {
    struct ReadSampleFile: AsyncParsableCommand {
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

            // Use Services.ServiceContainer for managed lifecycle
            let file = try await Services.ServiceContainer.withSampleService(dbPath: dbPath) { service in
                guard let file = try await service.getFile(projectId: projectId, path: filePath) else {
                    Logging.Log.error("File not found: \(filePath) in project \(projectId)")
                    Logging.Log.output("Use 'cupertino read-sample \(projectId)' to list available files.")
                    throw ExitCode.failure
                }
                return file
            }

            // Output results using formatters
            switch format {
            case .text:
                outputText(file)
            case .json:
                let formatter = SampleFileJSONFormatter()
                Logging.Log.output(formatter.format(file))
            case .markdown:
                let formatter = SampleFileMarkdownFormatter()
                Logging.Log.output(formatter.format(file))
            }
        }

        // MARK: - Path Resolution

        private func resolveSampleDbPath() -> URL {
            if let sampleDb {
                return URL(fileURLWithPath: sampleDb).expandingTildeInPath
            }
            return Sample.Index.defaultDatabasePath
        }

        // MARK: - Output Formatting

        private func outputText(_ file: Sample.Index.File) {
            Logging.Log.output("// File: \(file.path)")
            Logging.Log.output("// Project: \(file.projectId)")
            Logging.Log.output("// Size: \(Shared.Utils.Formatting.formatBytes(file.size))")
            Logging.Log.output("")
            Logging.Log.output(file.content)
        }
    }
}

// MARK: - Output Format

extension Command.ReadSampleFile {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

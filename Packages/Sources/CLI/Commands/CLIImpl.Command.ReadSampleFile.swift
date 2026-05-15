import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import Services
import ServicesModels
import SharedConstants

// MARK: - Read Sample File Command

/// CLI command for reading a specific file from a sample project - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
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

            // GoF Factory Method (1994 p. 107): construct concrete factory
            // at the command's composition sub-root.
            let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

            // Use Services.ServiceContainer for managed lifecycle.
            //
            // #620: probe project existence before the file lookup so the
            // error message distinguishes "wrong project id" from "wrong
            // file path inside a valid project". Pre-fix both shapes
            // returned the same `File not found in project <id>` message
            // with a remediation hint pointing at `cupertino read-sample
            // <id>` — that hint runs straight into the same project-not-
            // found wall when the user's typo is in the project id.
            // Post-fix the wrong-project path emits the same wording
            // `cupertino read-sample` uses on its own miss path.
            let file = try await Services.ServiceContainer.withSampleService(samplesDB: dbPath, sampleDatabaseFactory: sampleDatabaseFactory) { service in
                guard try await service.getProject(id: projectId) != nil else {
                    Cupertino.Context.composition.logging.recording.error("Project not found: \(projectId)")
                    Cupertino.Context.composition.logging.recording.output(
                        "Use 'cupertino list-samples' or 'cupertino search --source samples' to find valid project IDs."
                    )
                    throw ExitCode.failure
                }
                guard let file = try await service.getFile(projectId: projectId, path: filePath) else {
                    Cupertino.Context.composition.logging.recording.error("File not found: \(filePath) in project \(projectId)")
                    Cupertino.Context.composition.logging.recording.output("Use 'cupertino read-sample \(projectId)' to list available files.")
                    throw ExitCode.failure
                }
                return file
            }

            // Output results using formatters
            switch format {
            case .text:
                outputText(file)
            case .json:
                let formatter = Sample.Format.JSON.File()
                Cupertino.Context.composition.logging.recording.output(formatter.format(file))
            case .markdown:
                let formatter = Sample.Format.Markdown.File()
                Cupertino.Context.composition.logging.recording.output(formatter.format(file))
            }
        }

        // MARK: - Path Resolution

        private func resolveSampleDbPath() -> URL {
            if let sampleDb {
                return URL(fileURLWithPath: sampleDb).expandingTildeInPath
            }
            // Path-DI composition sub-root (#535).
            return Sample.Index.databasePath(baseDirectory: Shared.Paths.live().baseDirectory)
        }

        // MARK: - Output Formatting

        private func outputText(_ file: Sample.Index.File) {
            Cupertino.Context.composition.logging.recording.output("// File: \(file.path)")
            Cupertino.Context.composition.logging.recording.output("// Project: \(file.projectId)")
            Cupertino.Context.composition.logging.recording.output("// Size: \(Shared.Utils.Formatting.formatBytes(file.size))")
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output(file.content)
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.ReadSampleFile {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

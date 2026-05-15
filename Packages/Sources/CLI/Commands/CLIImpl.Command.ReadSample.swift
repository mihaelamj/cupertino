import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import Services
import ServicesModels
import SharedConstants
// MARK: - Read Sample Command

/// CLI command for reading a sample project's README - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct ReadSample: AsyncParsableCommand {
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

            // GoF Factory Method (1994 p. 107): construct concrete factory
            // at the command's composition sub-root.
            let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

            // Use Services.ServiceContainer for managed lifecycle
            let (project, files) = try await Services.ServiceContainer.withSampleService(samplesDB: dbPath, sampleDatabaseFactory: sampleDatabaseFactory) { service in
                guard let project = try await service.getProject(id: projectId) else {
                    Cupertino.Context.composition.logging.recording.error("Project not found: \(projectId)")
                    Cupertino.Context.composition.logging.recording.output("Use 'cupertino list-samples' or 'cupertino search --source samples' to find valid project IDs.")
                    throw ExitCode.failure
                }

                let files = try await service.listFiles(projectId: projectId, folder: nil)
                return (project, files)
            }

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
            // Path-DI composition sub-root (#535).
            return Sample.Index.databasePath(baseDirectory: Shared.Paths.live().baseDirectory)
        }

        // MARK: - Output Formatting

        private func outputText(_ project: Sample.Index.Project, files: [Sample.Index.File]) {
            Cupertino.Context.composition.logging.recording.output(project.title)
            Cupertino.Context.composition.logging.recording.output(String(repeating: "=", count: project.title.count))
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("Project ID: \(project.id)")
            Cupertino.Context.composition.logging.recording.output("Frameworks: \(project.frameworks.joined(separator: ", "))")
            Cupertino.Context.composition.logging.recording.output("Files: \(project.fileCount)")
            Cupertino.Context.composition.logging.recording.output("Size: \(Shared.Utils.Formatting.formatBytes(project.totalSize))")

            if !project.webURL.isEmpty {
                Cupertino.Context.composition.logging.recording.output("Apple Developer: \(project.webURL)")
            }

            Cupertino.Context.composition.logging.recording.output("")

            if !project.description.isEmpty {
                Cupertino.Context.composition.logging.recording.output("Description:")
                Cupertino.Context.composition.logging.recording.output(project.description)
                Cupertino.Context.composition.logging.recording.output("")
            }

            if let readme = project.readme, !readme.isEmpty {
                Cupertino.Context.composition.logging.recording.output("README:")
                Cupertino.Context.composition.logging.recording.output(readme)
                Cupertino.Context.composition.logging.recording.output("")
            }

            if !files.isEmpty {
                Cupertino.Context.composition.logging.recording.output("Files (\(files.count) total):")
                for file in files.prefix(30) {
                    Cupertino.Context.composition.logging.recording.output("  - \(file.path)")
                }
                if files.count > 30 {
                    Cupertino.Context.composition.logging.recording.output("  ... and \(files.count - 30) more files")
                }
            }

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("Tip: Use 'cupertino read-sample-file \(project.id) <path>' to view source code")
        }

        private func outputJSON(_ project: Sample.Index.Project, files: [Sample.Index.File]) {
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
                    Cupertino.Context.composition.logging.recording.output(jsonString)
                }
            } catch {
                Cupertino.Context.composition.logging.recording.error("Error encoding JSON: \(error)")
            }
        }

        private func outputMarkdown(_ project: Sample.Index.Project, files: [Sample.Index.File]) {
            Cupertino.Context.composition.logging.recording.output("# \(project.title)\n")
            Cupertino.Context.composition.logging.recording.output("**Project ID:** `\(project.id)`\n")

            if !project.description.isEmpty {
                Cupertino.Context.composition.logging.recording.output("## Description\n")
                Cupertino.Context.composition.logging.recording.output("\(project.description)\n")
            }

            Cupertino.Context.composition.logging.recording.output("## Metadata\n")
            Cupertino.Context.composition.logging.recording.output("- **Frameworks:** \(project.frameworks.joined(separator: ", "))")
            Cupertino.Context.composition.logging.recording.output("- **Files:** \(project.fileCount)")
            Cupertino.Context.composition.logging.recording.output("- **Size:** \(Shared.Utils.Formatting.formatBytes(project.totalSize))")

            if !project.webURL.isEmpty {
                Cupertino.Context.composition.logging.recording.output("- **Apple Developer:** \(project.webURL)")
            }

            Cupertino.Context.composition.logging.recording.output("")

            if let readme = project.readme, !readme.isEmpty {
                Cupertino.Context.composition.logging.recording.output("## README\n")
                Cupertino.Context.composition.logging.recording.output(readme)
                Cupertino.Context.composition.logging.recording.output("")
            }

            if !files.isEmpty {
                Cupertino.Context.composition.logging.recording.output("## Files (\(files.count) total)\n")
                for file in files.prefix(30) {
                    Cupertino.Context.composition.logging.recording.output("- `\(file.path)`")
                }
                if files.count > 30 {
                    Cupertino.Context.composition.logging.recording.output("- _... and \(files.count - 30) more files_")
                }
            }
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.ReadSample {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

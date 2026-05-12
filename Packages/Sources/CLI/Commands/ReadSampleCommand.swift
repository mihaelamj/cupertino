import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Services
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Read Sample Command

/// CLI command for reading a sample project's README - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension Command {
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

            // Use ServiceContainer for managed lifecycle
            let (project, files) = try await ServiceContainer.withSampleService(dbPath: dbPath) { service in
                guard let project = try await service.getProject(id: projectId) else {
                    Logging.Log.error("Project not found: \(projectId)")
                    Logging.Log.output("Use 'cupertino list-samples' or 'cupertino search --source samples' to find valid project IDs.")
                    throw ExitCode.failure
                }

                let files = try await service.listFiles(projectId: projectId)
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
            return SampleIndex.defaultDatabasePath
        }

        // MARK: - Output Formatting

        private func outputText(_ project: SampleIndex.Project, files: [SampleIndex.File]) {
            Logging.Log.output(project.title)
            Logging.Log.output(String(repeating: "=", count: project.title.count))
            Logging.Log.output("")
            Logging.Log.output("Project ID: \(project.id)")
            Logging.Log.output("Frameworks: \(project.frameworks.joined(separator: ", "))")
            Logging.Log.output("Files: \(project.fileCount)")
            Logging.Log.output("Size: \(Shared.Utils.Formatting.formatBytes(project.totalSize))")

            if !project.webURL.isEmpty {
                Logging.Log.output("Apple Developer: \(project.webURL)")
            }

            Logging.Log.output("")

            if !project.description.isEmpty {
                Logging.Log.output("Description:")
                Logging.Log.output(project.description)
                Logging.Log.output("")
            }

            if let readme = project.readme, !readme.isEmpty {
                Logging.Log.output("README:")
                Logging.Log.output(readme)
                Logging.Log.output("")
            }

            if !files.isEmpty {
                Logging.Log.output("Files (\(files.count) total):")
                for file in files.prefix(30) {
                    Logging.Log.output("  - \(file.path)")
                }
                if files.count > 30 {
                    Logging.Log.output("  ... and \(files.count - 30) more files")
                }
            }

            Logging.Log.output("")
            Logging.Log.output("Tip: Use 'cupertino read-sample-file \(project.id) <path>' to view source code")
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
                    Logging.Log.output(jsonString)
                }
            } catch {
                Logging.Log.error("Error encoding JSON: \(error)")
            }
        }

        private func outputMarkdown(_ project: SampleIndex.Project, files: [SampleIndex.File]) {
            Logging.Log.output("# \(project.title)\n")
            Logging.Log.output("**Project ID:** `\(project.id)`\n")

            if !project.description.isEmpty {
                Logging.Log.output("## Description\n")
                Logging.Log.output("\(project.description)\n")
            }

            Logging.Log.output("## Metadata\n")
            Logging.Log.output("- **Frameworks:** \(project.frameworks.joined(separator: ", "))")
            Logging.Log.output("- **Files:** \(project.fileCount)")
            Logging.Log.output("- **Size:** \(Shared.Utils.Formatting.formatBytes(project.totalSize))")

            if !project.webURL.isEmpty {
                Logging.Log.output("- **Apple Developer:** \(project.webURL)")
            }

            Logging.Log.output("")

            if let readme = project.readme, !readme.isEmpty {
                Logging.Log.output("## README\n")
                Logging.Log.output(readme)
                Logging.Log.output("")
            }

            if !files.isEmpty {
                Logging.Log.output("## Files (\(files.count) total)\n")
                for file in files.prefix(30) {
                    Logging.Log.output("- `\(file.path)`")
                }
                if files.count > 30 {
                    Logging.Log.output("- _... and \(files.count - 30) more files_")
                }
            }
        }
    }
}

// MARK: - Output Format

extension Command.ReadSample {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}

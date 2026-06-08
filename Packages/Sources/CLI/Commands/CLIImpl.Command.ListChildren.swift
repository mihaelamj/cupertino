import ArgumentParser
import Foundation
import Services
import ServicesModels
import SharedConstants

// MARK: - List Children Command

/// CLI command for direct document-child browsing.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct ListChildren: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-children",
            abstract: "List direct children of a document or topic group"
        )

        @Argument(
            help: "Apple documentation URI or topic-group fragment URI (e.g. apple-docs://swiftui#Essentials)."
        )
        var uri: String

        @Option(
            name: .long,
            help: "Source to browse. Default: apple-docs."
        )
        var source: String = Shared.Constants.SourcePrefix.appleDocs

        @Option(
            name: .long,
            help: CLIImpl.Command.OutputFormatArgument.jsonDefaultHelp
        )
        var format: OutputFormat = .json

        mutating func run() async throws {
            let registry = CLIImpl.makeProductionSourceRegistry()
            guard let provider = registry.provider(for: source) else {
                CLIImpl.printUserFacingDiagnostic(
                    "Unknown --source value: \(source). See `cupertino list-children --help`.",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            guard provider.capabilities.operations.contains(.listChildren) else {
                CLIImpl.printUserFacingDiagnostic(
                    "`\(source)` does not support list-children. Try `--source apple-docs`.",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            let paths = Shared.Paths.live()
            let dbURL = paths.baseDirectory.appendingPathComponent(provider.destinationDB.filename)
            guard FileManager.default.fileExists(atPath: dbURL.path) else {
                CLIImpl.printUserFacingDiagnostic(
                    CLIImpl.perSourceDBMissingMessage(url: dbURL),
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            let page = try await Services.ServiceContainer.withDocsService(
                dbURL: dbURL,
                searchDatabaseFactory: LiveSearchDatabaseFactory()
            ) { service in
                try await service.listChildren(
                    source: provider.definition.id,
                    uri: uri
                )
            }

            let output = switch format {
            case .text:
                Services.Formatter.DocumentChildren.Text().format(page)
            case .json:
                Services.Formatter.DocumentChildren.JSON().format(page)
            case .markdown:
                Services.Formatter.DocumentChildren.Markdown().format(page)
            }
            CLIImpl.writeStdout(output)
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.ListChildren {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }
}

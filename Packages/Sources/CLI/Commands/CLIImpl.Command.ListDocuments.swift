import ArgumentParser
import Foundation
import Services
import ServicesModels
import SharedConstants

// MARK: - List Documents Command

/// CLI command for paged framework document browsing.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct ListDocuments: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-documents",
            abstract: "List documents in a framework"
        )

        @Option(
            name: .long,
            help: "Framework identifier, import name, or display name (e.g. swiftui, SwiftUI, Swift UI)."
        )
        var framework: String

        @Option(
            name: .long,
            help: "Source to browse. Default: apple-docs."
        )
        var source: String = Shared.Constants.SourcePrefix.appleDocs

        @Option(
            name: .long,
            help: "Zero-based result offset. Default: 0."
        )
        var offset: Int = 0

        @Option(
            name: .long,
            help: "Maximum documents to return. Default: 100, maximum: 500."
        )
        var limit: Int = Shared.Constants.Limit.defaultDocumentListLimit

        @Option(
            name: .long,
            help: CLIImpl.Command.OutputFormatArgument.jsonDefaultHelp
        )
        var format: OutputFormat = .json

        mutating func run() async throws {
            let registry = CLIImpl.makeProductionSourceRegistry()
            guard let provider = registry.provider(for: source) else {
                CLIImpl.printUserFacingDiagnostic(
                    "Unknown --source value: \(source). See `cupertino list-documents --help`.",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            guard provider.capabilities.operations.contains(.listDocuments) else {
                CLIImpl.printUserFacingDiagnostic(
                    "`\(source)` does not support list-documents. Try `--source apple-docs`.",
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
                try await service.listDocuments(
                    source: provider.definition.id,
                    framework: framework,
                    offset: offset,
                    limit: limit
                )
            }

            let output = switch format {
            case .text:
                Services.Formatter.Documents.Text().format(page)
            case .json:
                Services.Formatter.Documents.JSON().format(page)
            case .markdown:
                Services.Formatter.Documents.Markdown().format(page)
            }
            CLIImpl.writeStdout(output)
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.ListDocuments {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }
}

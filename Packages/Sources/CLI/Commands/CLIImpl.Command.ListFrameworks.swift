import ArgumentParser
import Foundation
import Logging
import LoggingModels
import Services
import ServicesModels
import SharedConstants

// MARK: - List Frameworks Command

/// CLI command for listing available frameworks - mirrors MCP tool functionality.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct ListFrameworks: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-frameworks",
            abstract: "List available frameworks with document counts"
        )

        @Option(
            name: .long,
            help: CLIImpl.Command.OutputFormatArgument.textDefaultHelp
        )
        var format: OutputFormat = .text

        mutating func run() async throws {
            // GoF Factory Method (1994 p. 107): construct the concrete
            // Creator at the command's composition sub-root. Stateless
            // structs need no singleton handle per GoF p. 127.
            let searchDatabaseFactory: any SearchModule.DatabaseFactory = LiveSearchDatabaseFactory()

            // Path-DI composition sub-root (#535). Source Independence
            // Day pattern: iterate the production source registry and
            // open every source whose `capabilities.operations`
            // contains `.listFrameworks`. Today: apple-docs +
            // apple-archive. Adding a new source that declares
            // `.listFrameworks` adds it to this fan-out with zero
            // edits here (the "2-file PR" standard).
            //
            // Each framework-scoped source resolves through its own
            // per-source DB filename declared by
            // `SourceProvider.destinationDB.filename`.
            let baseDirectory = Shared.Paths.live().baseDirectory
            let registry = CLIImpl.makeProductionSourceRegistry()
            let frameworkSources = registry.allEnabled.filter {
                $0.capabilities.operations.contains(.listFrameworks)
            }
            let appleDocsURL = CLIImpl.resolveAppleDocsDBURL()

            // Fail-fast: surface the apple-docs missing-DB diagnostic
            // before opening any other DB. Pre-#1037 the user was
            // either set up or not; the apple-docs DB is the canonical
            // floor for whether this command can run at all.
            guard FileManager.default.fileExists(atPath: appleDocsURL.path) else {
                CLIImpl.printUserFacingDiagnostic(
                    CLIImpl.perSourceDBMissingMessage(url: appleDocsURL),
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            var frameworks: [String: Int] = [:]
            var totalDocs = 0

            for provider in frameworkSources {
                let dbURL: URL
                if provider.definition.id == Shared.Constants.SourcePrefix.appleDocs {
                    dbURL = appleDocsURL
                } else {
                    dbURL = baseDirectory.appendingPathComponent(provider.destinationDB.filename)
                }
                guard FileManager.default.fileExists(atPath: dbURL.path) else {
                    // Missing non-apple-docs DB is non-fatal: a user
                    // who never set up the bundle's archive DB still
                    // sees apple-docs frameworks.
                    continue
                }
                let perDB = try await Services.ServiceContainer.withDocsService(
                    dbURL: dbURL,
                    searchDatabaseFactory: searchDatabaseFactory
                ) { service in
                    let perDBFrameworks = try await service.listFrameworks()
                    let perDBCount = try await service.documentCount()
                    return (perDBFrameworks, perDBCount)
                }
                frameworks.merge(perDB.0, uniquingKeysWith: +)
                totalDocs += perDB.1
            }

            // Output results using formatters.
            // #1045 Gap 2 wiring: registry-derived source-id list for
            // the footer's "all sources" discovery block.
            let frameworksRegisteredSources = CLIImpl.makeFormatterAvailableSources(
                registry: CLIImpl.makeProductionSourceRegistry()
            )
            // #1041: the source IDs that actually contributed to totalDocs,
            // so the formatter can caveat the count's scope without
            // hardcoding which sources expose frameworks.
            let scopedSourceIDs = frameworkSources.map(\.definition.id)
            switch format {
            case .text:
                let formatter = Services.Formatter.Frameworks.Text(
                    totalDocs: totalDocs,
                    availableSources: frameworksRegisteredSources,
                    frameworkScopedSources: scopedSourceIDs
                )
                Cupertino.Context.composition.logging.recording.output(formatter.format(frameworks))
            case .json:
                let formatter = Services.Formatter.Frameworks.JSON()
                Cupertino.Context.composition.logging.recording.output(formatter.format(frameworks))
            case .markdown:
                let formatter = Services.Formatter.Frameworks.Markdown(
                    totalDocs: totalDocs,
                    availableSources: frameworksRegisteredSources,
                    frameworkScopedSources: scopedSourceIDs
                )
                Cupertino.Context.composition.logging.recording.output(formatter.format(frameworks))
            }
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.ListFrameworks {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }
}

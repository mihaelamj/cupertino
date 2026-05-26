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
            help: "Output format: text (default), json, markdown"
        )
        var format: OutputFormat = .text

        @Option(
            name: .long,
            help: """
            Override the apple-docs database path. Default: \
            apple-documentation.db (resolved through the production source \
            registry). Override applies to apple-docs only; apple-archive \
            still resolves through its own per-source DB.
            """
        )
        var searchDb: String?

        mutating func run() async throws {
            // GoF Factory Method (1994 p. 107): construct the concrete
            // Creator at the command's composition sub-root. Stateless
            // structs need no singleton handle per GoF p. 127.
            let searchDatabaseFactory: any SearchModule.DatabaseFactory = LiveSearchDatabaseFactory()

            // Path-DI composition sub-root (#535). Apple framework
            // partitioning lives in apple-docs AND apple-archive (the
            // two sources whose pages carry a meaningful `framework`
            // column; HIG / swift-evolution / swift-org / swift-book
            // emit framework=""). Pre per-source DB split, this
            // command's `SELECT framework FROM docs_metadata` against
            // the unified search.db pulled both source's frameworks
            // in one query; post-split it fans out across the two
            // per-source DBs that contribute. Other sources (whose
            // framework column is always "") are not opened.
            let appleDocsURL = CLIImpl.resolveAppleDocsDBURL(override: searchDb)
            let appleArchiveURL = Shared.Paths.live().baseDirectory.appendingPathComponent(
                Shared.Models.DatabaseDescriptor.appleArchive.filename
            )

            var frameworks: [String: Int] = [:]
            var totalDocs = 0

            for dbURL in [appleDocsURL, appleArchiveURL] {
                guard FileManager.default.fileExists(atPath: dbURL.path) else {
                    // Missing apple-archive.db is non-fatal: a user who
                    // never set up the bundle's archive DB still sees
                    // apple-docs frameworks.
                    continue
                }
                let perDB = try await Services.ServiceContainer.withDocsService(
                    searchDB: dbURL,
                    searchDatabaseFactory: searchDatabaseFactory
                ) { service in
                    let perDBFrameworks = try await service.listFrameworks()
                    let perDBCount = try await service.documentCount()
                    return (perDBFrameworks, perDBCount)
                }
                frameworks.merge(perDB.0, uniquingKeysWith: +)
                totalDocs += perDB.1
            }

            // apple-docs.db is the required floor. apple-archive.db is
            // optional. If apple-docs.db itself is missing the user is
            // pre-setup; surface the same diagnostic as the AST
            // commands do.
            guard FileManager.default.fileExists(atPath: appleDocsURL.path) else {
                CLIImpl.printUserFacingDiagnostic(
                    CLIImpl.appleDocsDBMissingMessage(url: appleDocsURL),
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            // Output results using formatters
            switch format {
            case .text:
                let formatter = Services.Formatter.Frameworks.Text(totalDocs: totalDocs)
                Cupertino.Context.composition.logging.recording.output(formatter.format(frameworks))
            case .json:
                let formatter = Services.Formatter.Frameworks.JSON()
                Cupertino.Context.composition.logging.recording.output(formatter.format(frameworks))
            case .markdown:
                let formatter = Services.Formatter.Frameworks.Markdown(totalDocs: totalDocs)
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
    }
}

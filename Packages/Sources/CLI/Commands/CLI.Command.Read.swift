import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import SampleIndexModels
import Search
import SearchModels
import Services
import ServicesModels
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Read Command (unified, #239 follow-up)

/// Thin CLI wrapper around `Services.ReadService`. The dispatch + per-source
/// reads live there so the MCP layer (and any future agent-shell adapter)
/// can share one implementation.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLI.Command {
    struct Read: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Read a document from any indexed source (docs, samples, packages)"
        )

        @Argument(
            help: """
            Identifier. Docs URIs (\"apple-docs://swiftui/...\") look up search.db; \
            sample IDs and `<projectId>/<path>` look up samples.db; \
            `<owner>/<repo>/<path>` is read from the on-disk packages tree.
            """
        )
        var identifier: String

        @Option(
            name: .long,
            help: """
            Disambiguator for non-URI identifiers: apple-docs, apple-archive, hig, \
            swift-evolution, swift-org, swift-book, samples, packages. \
            Auto-detected when omitted.
            """
        )
        var source: String?

        @Option(
            name: .long,
            help: "Output format: json (default), markdown"
        )
        var format: OutputFormat = .json

        @Option(
            name: .long,
            help: "Path to search database (search.db)"
        )
        var searchDb: String?

        @Option(
            name: .long,
            help: "Path to sample index database (samples.db)"
        )
        var sampleDb: String?

        @Option(
            name: .long,
            help: "Path to packages database (packages.db)"
        )
        var packagesDb: String?

        mutating func run() async throws {
            // GoF Factory Method (1994 p. 107) / Strategy (p. 315):
            // construct concrete factories + strategy at the command's
            // composition sub-root. Each Live struct is stateless, so
            // per-call construction is free and avoids the Service
            // Locator anti-pattern (Seemann 2011 ch. 5) of file-scope
            // shared instances.
            let searchDatabaseFactory: any SearchModule.DatabaseFactory = LiveSearchDatabaseFactory()
            let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

            let documentFormat: SearchModels.Search.DocumentFormat = format == .markdown
                ? .markdown
                : .json

            let explicit: Services.ReadService.Source?
            do {
                explicit = try Services.ReadService.resolveSource(source)
            } catch Services.ReadService.ReadError.unknownSource(let raw) {
                Logging.LiveRecording().error("Unknown --source value: \(raw). See `cupertino read --help`.")
                throw ExitCode.failure
            }

            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let searchDBURL = searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? paths.searchDatabase
            let samplesDBURL = sampleDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Sample.Index.databasePath(baseDirectory: paths.baseDirectory)
            let packagesDBURL = packagesDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? paths.packagesDatabase

            let result: Services.ReadService.Result
            do {
                result = try await Services.ReadService.read(
                    identifier: identifier,
                    explicit: explicit,
                    format: documentFormat,
                    searchDB: searchDBURL,
                    samplesDB: samplesDBURL,
                    packagesDB: packagesDBURL,
                    searchDatabaseFactory: searchDatabaseFactory,
                    sampleDatabaseFactory: sampleDatabaseFactory,
                    packageFileLookup: LivePackageFileLookupStrategy()
                )
            } catch Services.ReadService.ReadError.docsNotFound(let id) {
                Logging.LiveRecording().error("Document not found in search.db: \(id)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.samplesNotFound(let id) {
                Logging.LiveRecording().error("Not found in samples.db: \(id)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.packagesNotFound(let id) {
                Logging.LiveRecording().error("Not found in packages.db: \(id)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.packagesIdentifierInvalid(let id) {
                Logging.LiveRecording().error(
                    "Invalid package identifier: \(id) — expected `<owner>/<repo>/<relpath>`."
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.backendFailed(let msg) {
                Logging.LiveRecording().error("Read failed: \(msg)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.notFoundAnywhere(let id) {
                Logging.LiveRecording().error(
                    "Tried docs, samples, and packages — no source matched. Identifier: \(id)"
                )
                throw ExitCode.failure
            }

            Logging.LiveRecording().output(result.content)
        }
    }
}

// MARK: - Output Format

extension CLI.Command.Read {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case json
        case markdown
    }
}

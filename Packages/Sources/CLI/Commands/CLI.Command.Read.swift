import ServicesModels
import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Search
import Services
import SharedCore
import SharedUtils
import SearchModels

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
            let documentFormat: SearchModels.Search.DocumentFormat = format == .markdown
                ? .markdown
                : .json

            let explicit: Services.ReadService.Source?
            do {
                explicit = try Services.ReadService.resolveSource(source)
            } catch Services.ReadService.ReadError.unknownSource(let raw) {
                Logging.Log.error("Unknown --source value: \(raw). See `cupertino read --help`.")
                throw ExitCode.failure
            }

            let result: Services.ReadService.Result
            do {
                result = try await Services.ReadService.read(
                    identifier: identifier,
                    explicit: explicit,
                    format: documentFormat,
                    searchDB: searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath },
                    samplesDB: sampleDb.map { URL(fileURLWithPath: $0).expandingTildeInPath },
                    packagesDB: packagesDb.map { URL(fileURLWithPath: $0).expandingTildeInPath },
                    makeSearchDatabase: makeSearchDatabase,
                    packageFileLookup: { dbURL, owner, repo, relpath in
                        // The Search.PackageQuery actor is the production
                        // packages.db reader. CLI wires it in here so
                        // Services.ReadService doesn't need to import the
                        // Search target.
                        let query = try await SearchModule.PackageQuery(dbPath: dbURL)
                        defer { Task { await query.disconnect() } }
                        return try await query.fileContent(owner: owner, repo: repo, relpath: relpath)
                    }
                )
            } catch Services.ReadService.ReadError.docsNotFound(let id) {
                Logging.Log.error("Document not found in search.db: \(id)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.samplesNotFound(let id) {
                Logging.Log.error("Not found in samples.db: \(id)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.packagesNotFound(let id) {
                Logging.Log.error("Not found in packages.db: \(id)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.packagesIdentifierInvalid(let id) {
                Logging.Log.error(
                    "Invalid package identifier: \(id) — expected `<owner>/<repo>/<relpath>`."
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.backendFailed(let msg) {
                Logging.Log.error("Read failed: \(msg)")
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.notFoundAnywhere(let id) {
                Logging.Log.error(
                    "Tried docs, samples, and packages — no source matched. Identifier: \(id)"
                )
                throw ExitCode.failure
            }

            Logging.Log.output(result.content)
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

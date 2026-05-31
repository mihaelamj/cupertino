import ArgumentParser
import CupertinoComposition
import Foundation
import Logging
import LoggingModels
import SampleIndex
import SampleIndexModels
import SearchAPI
import SearchModels
import Services
import ServicesModels
import SharedConstants

// MARK: - Read Command (unified, #239 follow-up)

/// Thin CLI wrapper around `Services.ReadService`. The dispatch + per-source
/// reads live there so the MCP layer (and any future agent-shell adapter)
/// can share one implementation.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct Read: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Read a document from any indexed source (docs, samples, packages)"
        )

        @Argument(
            help: """
            Identifier. Post-#1037 every docs source owns its own SQLite \
            file: docs URIs route by scheme (`apple-docs://swiftui/...` -> \
            apple-documentation.db; `hig://buttons/...` -> hig.db; \
            same shape for apple-archive / swift-evolution / swift-org / \
            swift-book). Sample IDs and `<projectId>/<path>` look up \
            apple-sample-code.db; `<owner>/<repo>/<path>` is read from \
            the on-disk packages tree.
            """
        )
        var identifier: String

        @Option(
            name: .long,
            help: """
            Disambiguator for non-URI identifiers: apple-docs, apple-archive, hig, \
            swift-evolution, swift-org, swift-book, samples (alias: \
            apple-sample-code), packages. Auto-detected when omitted. For URI \
            identifiers the scheme is the disambiguator; if `--source` is also \
            given it must match the URI's scheme.
            """
        )
        var source: String?

        @Option(
            name: .long,
            help: CLIImpl.Command.OutputFormatArgument.jsonDefaultHelp
        )
        var format: OutputFormat = .json

        @Option(
            name: .long,
            help: """
            Override the docs database path. Post-#1037 each docs source \
            owns its own file (apple-documentation.db, hig.db, ...); when \
            this flag is set, EVERY docs source-id routes to the override \
            URL (legacy single-DB debug semantic). Mostly useful for tests \
            + custom-database workflows.
            """
        )
        var searchDb: String?

        @Option(
            name: .long,
            help: "Path to the sample index database (apple-sample-code.db)"
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

            // 2026-05-26 audit Finding 14.3: registry-derived
            // destinationsByID dict drives ReadService's bucket
            // classification. Adding a new source flows through here
            // automatically; pre-fix the resolver enumerated every
            // shipped source-id in a hardcoded 9-arm switch.
            let readDestinationsByID = CLIImpl.makeDestinationsByID(
                registry: CLIImpl.makeProductionSourceRegistry()
            )
            let explicit: Services.ReadService.Source?
            do {
                explicit = try Services.ReadService.resolveSource(
                    source,
                    destinationsByID: readDestinationsByID
                )
            } catch Services.ReadService.ReadError.unknownSource(let raw) {
                CLIImpl.printUserFacingDiagnostic(
                    "Unknown --source value: \(raw). See `cupertino read --help`.",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            // Round-18 critic finding #1 (#1039 follow-up): when both
            // the identifier carries a URI scheme AND `--source` is
            // given, the two must agree. Pre-fix `cupertino read
            // 'hig://...' --source apple-docs` silently routed to
            // apple-documentation.db (resolveDocsDBURL short-circuits
            // on explicit source-id before checking the URI scheme),
            // then returned `docsNotFound` against the wrong DB. Now
            // we reject the mismatch with a clear diagnostic before
            // opening any file. The samples / apple-sample-code alias
            // is allowed when the URI scheme is `samples` (both
            // narrow to the same backend).
            if let rawSource = source, let schemeEnd = identifier.range(of: "://") {
                let scheme = String(identifier[..<schemeEnd.lowerBound])
                let normalised = (rawSource == Shared.Constants.SourcePrefix.appleSampleCode)
                    ? Shared.Constants.SourcePrefix.samples
                    : rawSource
                let normalisedScheme = (scheme == Shared.Constants.SourcePrefix.appleSampleCode)
                    ? Shared.Constants.SourcePrefix.samples
                    : scheme
                if normalised != normalisedScheme {
                    CLIImpl.printUserFacingDiagnostic(
                        "❌ --source '\(rawSource)' disagrees with URI scheme '\(scheme)'. Drop --source (the URI is unambiguous) or change one to match the other.",
                        recording: Cupertino.Context.composition.logging.recording
                    )
                    throw ExitCode.failure
                }
            }

            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let searchDBURL = searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? paths.searchDatabase
            let samplesDBURL = sampleDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Sample.Index.databasePath(baseDirectory: paths.baseDirectory)
            let packagesDBURL = packagesDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? paths.packagesDatabase

            // #1039: build the per-source docs DB map so a URI like
            // `hig://buttons/standard-button` routes to hig.db
            // (post-#1037 per-source DB world). Pre-#1037 every docs
            // URI resolved through one search.db; post-#1037 each docs
            // source owns its own SQLite file. ReadService falls back
            // to `searchDB` (above) when the URI's scheme isn't in the
            // map, preserving back-compat for tests + the migration
            // window.
            //
            // `--search-db` override (when set): every docs source-id
            // maps to the override URL, so the legacy single-DB debug
            // workflow ("redirect every read to /tmp/my.db") still
            // works post-per-source-split. Without this branch the
            // map would shadow the override silently (the helper
            // checks the map first).
            let docsDBURLs: [String: URL]
            if let override = searchDb.map({ URL(fileURLWithPath: $0).expandingTildeInPath }) {
                docsDBURLs = CLIImpl.makeProductionSourceRegistry()
                    .allEnabled
                    .filter { $0.destinationDB != .packages && $0.destinationDB != .appleSampleCode }
                    .reduce(into: [:]) { dict, provider in
                        dict[provider.definition.id] = override
                    }
            } else {
                docsDBURLs = CLIImpl.makeProductionSourceRegistry()
                    .allEnabled
                    .filter { $0.destinationDB != .packages && $0.destinationDB != .appleSampleCode }
                    .reduce(into: [:]) { dict, provider in
                        dict[provider.definition.id] = paths.baseDirectory
                            .appendingPathComponent(provider.destinationDB.filename)
                    }
            }

            let result: Services.ReadService.Result
            do {
                // 2026-05-26 audit #1055: pass the production source
                // registry so ReadService dispatches via each provider's
                // `Search.SourceReadStrategy` instead of the legacy
                // 3-arm bucket switch.
                let registry = CupertinoComposition.makeProductionSourceRegistry()
                result = try await Services.ReadService.read(
                    identifier: identifier,
                    explicit: explicit,
                    format: documentFormat,
                    searchDB: searchDBURL,
                    samplesDB: samplesDBURL,
                    packagesDB: packagesDBURL,
                    searchDatabaseFactory: searchDatabaseFactory,
                    sampleDatabaseFactory: sampleDatabaseFactory,
                    packageFileLookup: LivePackageFileLookupStrategy(),
                    docsDBURLs: docsDBURLs,
                    explicitDocsSourceID: source,
                    providers: registry.allEnabled
                )
            } catch Services.ReadService.ReadError.docsNotFound(let id) {
                // Round-18 critic finding #2: name the resolved DB
                // filename so the user knows which per-source file to
                // inspect. Re-resolve here (same inputs the read
                // pipeline used) instead of plumbing the URL through
                // the ReadError enum, which would be a breaking
                // enum-shape change for non-CLI consumers.
                let resolved = Services.ReadService.resolveDocsDBURL(
                    identifier: id,
                    explicitSourceID: source,
                    fallback: searchDBURL,
                    docsDBURLs: docsDBURLs
                )
                CLIImpl.printUserFacingDiagnostic(
                    "Document not found in \(resolved.lastPathComponent): \(id)",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.samplesNotFound(let id) {
                CLIImpl.printUserFacingDiagnostic(
                    "Not found in samples.db: \(id)",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.packagesNotFound(let id) {
                CLIImpl.printUserFacingDiagnostic(
                    "Not found in packages.db: \(id)",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.packagesIdentifierInvalid(let id) {
                // Honest user-facing phrasing per each error case
                // (iter-2 critic finding #1). The Phase 4 harness's
                // marker list was extended to recognise these phrases
                // alongside the original 'not found' / 'no such'
                // markers, rather than forcing every diagnostic into
                // a 'Document not found' lexical bucket that would
                // misdirect user remediation when the actual cause
                // is a malformed identifier / backend failure / etc.
                CLIImpl.printUserFacingDiagnostic(
                    "Invalid package identifier `\(id)`. Expected shape: `<owner>/<repo>/<relpath>`.",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.backendFailed(let msg) {
                CLIImpl.printUserFacingDiagnostic(
                    "Read failed: \(msg)",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            } catch Services.ReadService.ReadError.notFoundAnywhere(let id) {
                CLIImpl.printUserFacingDiagnostic(
                    "Document not found in any source (docs, samples, packages). Identifier: \(id)",
                    recording: Cupertino.Context.composition.logging.recording
                )
                throw ExitCode.failure
            }

            Cupertino.Context.composition.logging.recording.output(result.content)
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.Read {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case json
        case markdown

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }
}

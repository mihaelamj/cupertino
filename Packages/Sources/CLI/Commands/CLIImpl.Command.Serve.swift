import ArgumentParser
import Core
import CoreProtocols
import Darwin
import Foundation
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SearchAPI
import SearchModels
import SearchToolProvider
import Services
import ServicesModels
import SharedConstants

// MARK: - Serve Command

extension CLIImpl.Command {
    struct Serve: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "serve",
            abstract: "Start MCP server for documentation access",
            discussion: """
            Starts the Model Context Protocol (MCP) server that provides documentation
            search and access capabilities for AI assistants.

            The server communicates via stdio using JSON-RPC and provides:

            Unified Search (requires 'cupertino save' or 'cupertino save --source samples'):
            • search - Smart query fanned out across every available source
                       (apple-docs, samples, swift-evolution, swift-org, swift-book,
                       packages, hig, apple-archive), reciprocal-rank fused.

            Documentation Tools (requires 'cupertino save'):
            • list_frameworks - List available frameworks with document counts
            • read_document   - Read full document content by URI

            Sample Code Tools (requires 'cupertino save --source samples'):
            • list_samples     - List all indexed sample projects
            • read_sample      - Read sample project README and metadata
            • read_sample_file - Read a specific source file from a sample

            Semantic Search Tools (requires 'cupertino save', AST-indexed):
            • search_symbols           - Find Swift symbols by name + kind
            • search_property_wrappers - Find @PropertyWrapper usage in indexed sources
            • search_concurrency       - Find concurrency patterns (@MainActor, async, …)
            • search_conformances      - Find protocol conformances by protocol name

            The server runs indefinitely until terminated.
            """
        )

        @Flag(
            name: .long,
            help: """
            Don't reap sibling `cupertino serve` processes on startup. \
            Useful for clients that legitimately spawn a fresh server per tool \
            call or keep multiple servers alive (e.g. OpenAI Codex CLI), where \
            the default reaping behaviour from #242 produces a 'Transport closed' \
            error on every tool call. Default off — Claude Desktop / Cursor \
            users want the reap. (#280)
            """
        )
        var noReap: Bool = false

        mutating func run() async throws {
            // #280: reap is opt-out via `--no-reap` or the
            // `CUPERTINO_DISABLE_REAPER=1` env var. Codex CLI and any
            // per-call-spawn MCP client must disable the reaper; Claude
            // Desktop / Cursor users keep it on so stale orphans don't
            // pile up. The flag wins if the user passed it; otherwise
            // the env var decides.
            let envOptOut = ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.disableReaper] == "1"
            if !noReap, !envOptOut {
                // Reap any sibling `cupertino serve` processes of the same binary
                // before we bind stdio. MCP host config reloads (Claude Desktop,
                // Cursor, etc.) leave orphan servers behind otherwise — they pin
                // SQLite read locks and stack RAM usage. (#242)
                ServeReaper.reapSiblings()
            }

            if isatty(STDOUT_FILENO) == 0 {
                // Silence stdout on the actor backing this binary's
                // `LiveRecording` so the JSON-RPC stream stays parseable.
                // Post-#548 Phase B, the recording sources from the
                // binary's `Cupertino.Composition` (TaskLocal-bound at
                // `Cupertino.main()`), not from the global
                // `Logging.Unified.shared` singleton — disabling console
                // on `.shared` after Phase B would silence the wrong
                // actor.
                await Cupertino.Context.composition.logging.disableConsole()
            }

            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let config = Shared.Configuration(
                crawler: Shared.Configuration.Crawler(
                    outputDirectory: paths.docsDirectory
                ),
                changeDetection: Shared.Configuration.ChangeDetection(
                    outputDirectory: paths.docsDirectory
                )
            )

            let evolutionURL = paths.swiftEvolutionDirectory
            let archiveURL = paths.archiveDirectory
            let searchDBURL = paths.searchDatabase
            let sampleDBURL = Sample.Index.databasePath(baseDirectory: paths.baseDirectory)
            let packagesDBURL = paths.packagesDatabase

            // Check if there's anything to serve
            let hasData = checkForData(
                docsDir: config.crawler.outputDirectory,
                evolutionDir: evolutionURL,
                searchDB: searchDBURL,
                sampleDB: sampleDBURL
            )

            if !hasData {
                printGettingStartedGuide()
                throw ExitCode.failure
            }

            // Advertise the embedded cupertino icon to MCP clients that speak
            // the 2025-11-25 protocol. Older clients ignore the field.
            let icon = MCP.Core.Protocols.Icon(
                src: MCP.Core.Protocols.CupertinoIcon.dataURI,
                mimeType: "image/png",
                sizes: ["64x64"]
            )
            let server = MCP.Core.Server(
                name: Shared.Constants.App.mcpServerName,
                version: Shared.Constants.App.version,
                icons: [icon]
            )

            await registerProviders(
                server: server,
                config: config,
                paths: paths,
                evolutionURL: evolutionURL,
                archiveURL: archiveURL,
                searchDBURL: searchDBURL,
                sampleDBURL: sampleDBURL,
                packagesDBURL: packagesDBURL
            )

            printStartupMessages(
                config: config,
                evolutionURL: evolutionURL,
                searchDBURL: searchDBURL,
                sampleDBURL: sampleDBURL
            )

            let transport = MCP.Core.Transport.Stdio()
            try await server.connect(transport)

            // #618: park on the server's message-processing task — which
            // unwinds when the transport's `messages` stream finishes —
            // instead of the pre-fix `while true { sleep 60 }` parking
            // loop. AI-agent MCP clients (Claude Desktop, Cursor, Codex
            // MCP) shut the server down by closing stdin: the Stdio
            // transport's `input.bytes` async sequence terminates,
            // `messagesContinuation.finish()` propagates to the server's
            // `for await message in messageStream`, the message task
            // exits, and this `await` returns so the process exits
            // cleanly. Pre-#618 the CLI never noticed EOF and stayed
            // alive forever (caught during main's retest of the v1.1.0
            // shipped binary; explained why stray `cupertino serve`
            // procs accumulated on every test machine).
            await server.waitForCompletion()
        }

        // swiftlint:disable:next function_parameter_count
        private func registerProviders(
            server: MCP.Core.Server,
            config: Shared.Configuration,
            paths: Shared.Paths,
            evolutionURL: URL,
            archiveURL: URL,
            searchDBURL: URL,
            sampleDBURL: URL,
            packagesDBURL: URL
        ) async {
            // Initialize search index if available. #645: when the file
            // exists but can't be opened (schema mismatch, etc.) we keep
            // the reason string so the tool provider can still advertise
            // search tools and fail loudly on call, rather than silently
            // dropping them from `tools/list`.
            let searchLoadResult = await loadSearchIndex(searchDBURL: searchDBURL)
            let searchIndex: SearchModule.Index? = searchLoadResult.index
            let searchIndexDisabledReason: String? = searchLoadResult.disabledReason

            // Register resource provider with optional search-index markdown
            // lookup. The provider doesn't see the SearchAPI target; it just
            // gets a strategy that returns markdown for a URI, or nil if the
            // URI isn't indexed. This keeps MCPSupport free of the SearchAPI
            // import per the DI epic (#406).
            let markdownLookup: (any MCP.Support.MarkdownLookupStrategy)?
            if let searchIndex {
                markdownLookup = LiveMarkdownLookupStrategy(searchIndex: searchIndex)
            } else {
                markdownLookup = nil
            }
            // 2026-05-26 audit Cluster 12 follow-up: collect each
            // registered provider's `Search.URIResourceStrategy` (the
            // 3 source-specific MCP-resource concretes today —
            // apple-docs / swift-evolution / apple-archive; nil for
            // every other source by the protocol's default extension)
            // and the matching on-disk corpus directory per scheme.
            // The dispatcher in `MCP.Support.DocsResourceProvider`
            // iterates the strategy list; adding a new MCP-resource
            // source is one `makeURIResourceStrategy()` override on
            // the provider, no edits to Serve or the dispatcher.
            //
            // Directory resolution: apple-docs honours the `--docs-dir`
            // override (paths.docsDirectory at construction time);
            // swift-evolution honours `--evolution-dir`; other schemes
            // resolve via `Shared.Paths.directory(named:)` keyed by
            // the source's `fetchInfo.defaultOutputDirKey.rawValue`.
            let resourceRegistry = CLIImpl.makeProductionSourceRegistry()
            var resourceStrategies: [any SearchModels.Search.URIResourceStrategy] = []
            var directoriesByScheme: [String: URL] = [:]
            for provider in resourceRegistry.allEnabled {
                guard let strategy = provider.makeURIResourceStrategy() else { continue }
                resourceStrategies.append(strategy)
                let dirKey = provider.fetchInfo?.defaultOutputDirKey.rawValue
                let directory: URL = switch provider.definition.id {
                case Shared.Constants.SourcePrefix.appleDocs: paths.docsDirectory
                case Shared.Constants.SourcePrefix.swiftEvolution: evolutionURL
                case Shared.Constants.SourcePrefix.appleArchive: archiveURL
                default: paths.directory(named: dirKey ?? provider.definition.id)
                }
                directoriesByScheme[strategy.scheme] = directory
            }
            let resourceProvider = MCP.Support.DocsResourceProvider(
                configuration: config,
                resourceStrategies: resourceStrategies,
                directoriesByScheme: directoriesByScheme,
                markdownLookup: markdownLookup,
                logger: Cupertino.Context.composition.logging.recording
            )
            await server.registerResourceProvider(resourceProvider)

            // Initialize sample code index if available
            let sampleIndex = await loadSampleIndex(sampleDBURL: sampleDBURL)

            // `#789`-style architectural gap fix: load packages.db as
            // its own searcher so the MCP layer can route
            // `source=packages` against the rich `packages.db` schema
            // instead of the no-op `search.db` source filter that
            // every query pre-PR-2 fell through.
            let packagesSearcher = await loadPackagesSearcher(packagesDBURL: packagesDBURL)

            // Register composite tool provider with both indexes. The
            // service-layer wrappers are constructed here at the
            // composition root and passed across the protocol seam so
            // SearchToolProvider doesn't have to construct them itself.
            let docsService: (any Services.DocsSearcher)? = searchIndex.map(Services.DocsSearchService.init(database:))
            let sampleService: (any Sample.Search.Searcher)? = sampleIndex.map(Sample.Search.Service.init(database:))
            let teaserService: (any Services.Teaser)? =
                (searchIndex == nil && sampleIndex == nil)
                    ? nil
                    : Services.TeaserService(searchIndex: searchIndex, sampleDatabase: sampleIndex)
            let unifiedService: (any Services.UnifiedSearcher)? =
                (searchIndex == nil && sampleIndex == nil && packagesSearcher == nil)
                    ? nil
                    : Services.UnifiedSearchService(
                        searchIndex: searchIndex,
                        sampleDatabase: sampleIndex,
                        packagesSearcher: packagesSearcher
                    )
            // #582: pass the same `DocsResourceProvider` instance into the
            // tool provider so `read_document` falls back through the
            // identical filesystem path `resources/read` uses. Without
            // this, the search-index direct lookup in `handleReadDocument`
            // returned "Document not found" for URIs that
            // `resources/read` successfully read off disk (typical with
            // bundles whose indexer-written URIs use the pre-#293
            // `.lastPathComponent` shape).
            // #1042 Cluster 7: derive the search tool's `source` enum
            // schema from the production source registry. Adding a new
            // source (one `.register(<X>Source())` call below) extends
            // the MCP schema automatically. `"all"` + the appleSampleCode
            // alias join the registered IDs to keep the existing
            // dispatch contract (samples is the canonical id; clients
            // historically also pass `apple-sample-code`).
            let registry = CLIImpl.makeProductionSourceRegistry()
            var searchToolSourceEnumValues = ["all"]
            searchToolSourceEnumValues.append(contentsOf: registry.allEnabled.map(\.definition.id))
            if !searchToolSourceEnumValues.contains(Shared.Constants.SourcePrefix.appleSampleCode) {
                searchToolSourceEnumValues.append(Shared.Constants.SourcePrefix.appleSampleCode)
            }

            // 2026-05-26 audit Finding 14.4: derive source-id →
            // searchRoute dispatch map from the production source
            // registry. CompositeToolProvider.handleSearch consults
            // this dict instead of switching on source-id literals
            // (pre-fix the switch hardcoded 9 source ids).
            var searchToolRoutesByID: [String: SearchModels.Search.SearchRoute] = [:]
            for provider in registry.allEnabled {
                searchToolRoutesByID[provider.definition.id] = provider.searchRoute
            }

            let toolProvider = CompositeToolProvider(
                searchIndex: searchIndex,
                sampleDatabase: sampleIndex,
                docsService: docsService,
                sampleService: sampleService,
                teaserService: teaserService,
                unifiedService: unifiedService,
                packagesSearcher: packagesSearcher,
                documentResourceProvider: resourceProvider,
                searchIndexDisabledReason: searchIndexDisabledReason,
                searchToolSourceEnumValues: searchToolSourceEnumValues,
                searchToolRoutesByID: searchToolRoutesByID
            )
            await server.registerToolProvider(toolProvider)

            // Log availability of each index
            if searchIndex != nil {
                let message = "✅ Documentation search enabled (index found)"
                Cupertino.Context.composition.logging.recording.info(message, category: .mcp)
            }
            if sampleIndex != nil {
                let message = "✅ Sample code search enabled (index found)"
                Cupertino.Context.composition.logging.recording.info(message, category: .mcp)
            }
        }

        /// Open `packages.db` for the MCP server when it's present.
        /// Mirrors `loadSampleIndex`'s "missing-is-fine" semantic: the
        /// fan-out search + MCP source dispatch both tolerate a nil
        /// searcher by emitting an empty packages bucket / explicit
        /// "Packages index not available" error frame.
        private func loadPackagesSearcher(packagesDBURL: URL) async -> (any SearchModule.PackagesSearcher)? {
            guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
                let infoMsg = "ℹ️  Packages index not found at: \(packagesDBURL.path)"
                let cmd = "\(Shared.Constants.App.commandName) save --packages"
                let hintMsg = "   Packages MCP search will not be available. Run '\(cmd)' to enable."
                Cupertino.Context.composition.logging.recording.info("\(infoMsg) \(hintMsg)", category: .mcp)
                return nil
            }
            do {
                return try await SearchModule.PackageQuery(dbPath: packagesDBURL)
            } catch {
                let errorMsg = "⚠️  Failed to open packages.db: \(error)"
                let cmd = "\(Shared.Constants.App.commandName) save --packages"
                let hintMsg = "   Packages MCP search will not be available. Run '\(cmd)' to rebuild."
                Cupertino.Context.composition.logging.recording.warning("\(errorMsg) \(hintMsg)", category: .mcp)
                return nil
            }
        }

        private func loadSampleIndex(sampleDBURL: URL) async -> Sample.Index.Database? {
            guard FileManager.default.fileExists(atPath: sampleDBURL.path) else {
                let infoMsg = "ℹ️  Sample code index not found at: \(sampleDBURL.path)"
                let cmd = "\(Shared.Constants.App.commandName) save --samples"
                let hintMsg = "   Sample tools will not be available. Run '\(cmd)' to enable."
                Cupertino.Context.composition.logging.recording.info("\(infoMsg) \(hintMsg)", category: .mcp)
                return nil
            }

            do {
                return try await Sample.Index.Database(dbPath: sampleDBURL, logger: Cupertino.Context.composition.logging.recording)
            } catch {
                let errorMsg = "⚠️  Failed to load sample index: \(error)"
                let cmd = "\(Shared.Constants.App.commandName) save --samples"
                let hintMsg = "   Sample tools will not be available. Run '\(cmd)' to create the index."
                Cupertino.Context.composition.logging.recording.warning("\(errorMsg) \(hintMsg)", category: .mcp)
                return nil
            }
        }

        /// Result of attempting to load the search index for the MCP server.
        ///
        /// Distinguishes the two `nil` cases so `CompositeToolProvider` can
        /// decide whether to hide the search.db-dependent tools (file missing,
        /// legitimately samples-only) or advertise them with a per-call
        /// error path (file present but unopenable, a configuration error).
        /// Pre-#645 both states collapsed to a bare `Search.Index?` and
        /// `tools/list` silently dropped 6 tools when the DB was unopenable.
        struct SearchIndexLoadResult {
            let index: SearchModule.Index?
            let disabledReason: String?
        }

        private func loadSearchIndex(searchDBURL: URL) async -> SearchIndexLoadResult {
            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                let infoMsg = "ℹ️  Search index not found at: \(searchDBURL.path)"
                let cmd = "\(Shared.Constants.App.commandName) save"
                let hintMsg = "   Tools will not be available. Run '\(cmd)' to enable search."
                Cupertino.Context.composition.logging.recording.info("\(infoMsg) \(hintMsg)", category: .mcp)
                // No file → legitimately no search index; the tool provider
                // hides the 6 search.db-dependent tools to keep `tools/list`
                // honest about what's actually callable.
                return SearchIndexLoadResult(index: nil, disabledReason: nil)
            }

            do {
                // #932: MCP serve opens the index for READ. Indexing
                // happens via `cupertino save` (a separate process); the
                // server never calls `indexItem`. Pass an empty indexer
                // dict explicitly to reflect that.
                let index = try await SearchModule.Index(
                    dbPath: searchDBURL,
                    logger: Cupertino.Context.composition.logging.recording,
                    indexers: [:],
                    sourceLookup: .empty
                )
                return SearchIndexLoadResult(index: index, disabledReason: nil)
            } catch {
                let errorString = "\(error)"
                let reason: String
                let lowercased = errorString.lowercased()
                if lowercased.contains("schema version") {
                    reason = "schema mismatch; run `cupertino setup` to redownload a matching bundle"
                } else if lowercased.contains("unable to open database") || lowercased.contains("file is not a database") {
                    reason = "database unopenable; check the `--search-db` path"
                } else {
                    reason = "search index initialisation failed: \(errorString)"
                }
                let errorMsg = "⚠️  Failed to load search index: \(error)"
                let cmd = "\(Shared.Constants.App.commandName) setup"
                let hintMsg = "   Tools advertised but will return an error on call until you run '\(cmd)' or rebuild the index."
                Cupertino.Context.composition.logging.recording.warning("\(errorMsg) \(hintMsg)", category: .mcp)
                // File present + open failed → configuration error. Expose
                // the tools in `tools/list` so AI agents see the full
                // capability set; per-call handlers throw a clear error
                // frame naming the reason (the same one the user can act
                // on).
                return SearchIndexLoadResult(index: nil, disabledReason: reason)
            }
        }

        private func printStartupMessages(
            config _: Shared.Configuration,
            evolutionURL _: URL,
            searchDBURL: URL,
            sampleDBURL: URL
        ) {
            var messages = ["🚀 Cupertino MCP Server starting..."]

            // Add search DB path if it exists
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                messages.append("   Search DB: \(searchDBURL.path)")
            }

            // Add samples DB path if it exists
            if FileManager.default.fileExists(atPath: sampleDBURL.path) {
                messages.append("   Samples DB: \(sampleDBURL.path)")
            }

            messages.append("   Waiting for client connection...")

            for message in messages {
                Cupertino.Context.composition.logging.recording.info(message, category: .mcp)
            }
        }

        private func checkForData(docsDir _: URL, evolutionDir _: URL, searchDB: URL, sampleDB: URL) -> Bool {
            let fileManager = FileManager.default

            // Check if either database exists
            let hasSearchDB = fileManager.fileExists(atPath: searchDB.path)
            let hasSamplesDB = fileManager.fileExists(atPath: sampleDB.path)

            return hasSearchDB || hasSamplesDB
        }

        private func printGettingStartedGuide() {
            let cmd = Shared.Constants.App.commandName
            let guide = """

            ╭─────────────────────────────────────────────────────────────────────────╮
            │                                                                         │
            │  👋 Welcome to Cupertino MCP Server!                                    │
            │                                                                         │
            │  No documentation found to serve. Let's get you started!                │
            │                                                                         │
            ╰─────────────────────────────────────────────────────────────────────────╯

            📦 OPTION A: Download pre-built databases (fastest)
            ───────────────────────────────────────────────────────────────────────────
              $ \(cmd) setup

            📚 OPTION B: Build from source
            ───────────────────────────────────────────────────────────────────────────
            Step 1 — Fetch documentation:

            • Apple Developer Documentation (recommended):
              $ \(cmd) fetch --source apple-docs

            • Swift Evolution Proposals:
              $ \(cmd) fetch --source swift-evolution

            • Swift.org Documentation:
              $ \(cmd) fetch --source swift-org

            • Swift Packages (priority packages):
              $ \(cmd) fetch --source packages

            ⏱️  Fetching takes 10-30 minutes depending on content type.
               If interrupted, just re-run the same command — fetch resumes by default.

            Step 2 — Build search index:
            ───────────────────────────────────────────────────────────────────────────
              $ \(cmd) save

            ⏱️  Indexing typically takes 2-5 minutes.

            🚀 STEP 3: Start the Server
            ───────────────────────────────────────────────────────────────────────────
            Once you have data, start the MCP server:

              $ \(cmd)

            The server will provide documentation access to AI assistants like Claude.

            ───────────────────────────────────────────────────────────────────────────
            💡 TIP: Run '\(cmd) doctor' to check your setup anytime.

            📖 For more information, see the README or run '\(cmd) --help'

            """

            // Use stderr for getting started guide (stdout is for MCP protocol)
            fputs(guide, stderr)
        }
    }
}

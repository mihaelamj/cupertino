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
    // swiftlint:disable:next type_body_length
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
            • list_documents  - List paged documents in a framework
            • list_children   - List direct children of a document or topic group
            • read_document   - Read full document content by URI

            Sample Code Tools (requires 'cupertino save --source samples'):
            • list_samples     - List all indexed sample projects (format=json for typed output)
            • read_sample      - Read sample project README, metadata, and files
                                  (format=json for typed output)
            • read_sample_file - Read a specific source file from a sample
                                  (format=json for typed output)

            Semantic Search Tools (requires 'cupertino save', AST-indexed):
            • search_symbols           - Find Swift symbols by name + kind
            • search_property_wrappers - Find @PropertyWrapper usage in indexed sources
            • search_concurrency       - Find concurrency patterns (@MainActor, async, …)
            • search_conformances      - Find protocol conformances by protocol name
            • search_generics          - Find generic-parameter constraints
            • get_inheritance          - Walk class inheritance chains

            The sample and semantic MCP tools default to markdown. Pass
            format=json for typed, GUI-decodable payloads.

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

        @Option(
            name: .customLong("base-dir"),
            help: """
            Serve the indexes from this base directory instead of the configured \
            default (`baseDirectory` in cupertino.config.json, else ~/.cupertino). \
            The per-source DBs (apple-documentation.db, packages.db, sample-code, …) \
            are resolved as siblings under this directory. Lets a host point the MCP \
            server at a specific bundle without a config file.
            """
        )
        var baseDir: String?

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

            // Path-DI composition sub-root (#535). `--base-dir` overrides the
            // configured/default base directory so a host can aim the MCP
            // server at a specific bundle without a config file.
            let paths = baseDir
                .map { Shared.Paths(baseDirectory: URL(fileURLWithPath: $0).expandingTildeInPath) }
                ?? Shared.Paths.live()
            let config = Shared.Configuration(
                crawler: Shared.Configuration.Crawler(
                    outputDirectory: paths.docsDirectory
                ),
                changeDetection: Shared.Configuration.ChangeDetection(
                    outputDirectory: paths.docsDirectory
                )
            )

            let evolutionURL = paths.swiftEvolutionDirectory
            // Post-#1036 the monolithic `search.db` is no longer built; the
            // apple-docs primary search index is the per-source DB the apple-docs
            // provider declares. Resolve it through the production source registry
            // (NOT a hardcoded filename) so the DB name lives in one place — the
            // source's `destinationDB` descriptor. Resolving to the legacy
            // `search.db` (paths.searchDatabase) opened an empty stub on a
            // per-source bundle, so search / list_frameworks returned zero
            // results (#1071 family). Falls back to the legacy path if the
            // apple-docs provider is somehow absent.
            let dbURL = CLIImpl.makeProductionSourceRegistry().allEnabled
                .first { $0.definition.id == Shared.Constants.SourcePrefix.appleDocs }
                .map { paths.baseDirectory.appendingPathComponent($0.destinationDB.filename) }
                ?? paths.searchDatabase
            let sampleDBURL = Sample.Index.databasePath(baseDirectory: paths.baseDirectory)
            let packagesDBURL = paths.packagesDatabase

            // Check if there's anything to serve
            let hasData = checkForData(
                docsDir: config.crawler.outputDirectory,
                evolutionDir: evolutionURL,
                dbURL: dbURL,
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
                paths: paths,
                dbURL: dbURL,
                sampleDBURL: sampleDBURL,
                packagesDBURL: packagesDBURL
            )

            printStartupMessages(
                config: config,
                evolutionURL: evolutionURL,
                dbURL: dbURL,
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

        private func registerProviders(
            server: MCP.Core.Server,
            paths: Shared.Paths,
            dbURL: URL,
            sampleDBURL: URL,
            packagesDBURL: URL
        ) async {
            // Initialize search index if available. #645: when the file
            // exists but can't be opened (schema mismatch, etc.) we keep
            // the reason string so the tool provider can still advertise
            // search tools and fail loudly on call, rather than silently
            // dropping them from `tools/list`.
            let searchLoadResult = await loadSearchIndex(dbURL: dbURL)
            let searchIndex: SearchModule.Index? = searchLoadResult.index
            let searchIndexDisabledReason: String? = searchLoadResult.disabledReason

            // #1277 / #1162: the registry-derived active-source inventory,
            // computed once and reused both for the `list_sources` tool and
            // the stderr startup health banner below.
            let sourceInventory = CLIImpl.activeSourceInventory()

            // 2026-05-28 (Principle 7): the MCP `resources/{list,read}`
            // path is served PURELY from the per-source SQLite DBs, the
            // same read path the MCP search/read TOOLS use
            // (`Services.ReadService` + the production source registry).
            // No filesystem is consulted; the legacy monolithic
            // `search.db` is no longer built post-#1036, so the previous
            // single-`Search.Index`-over-`search.db` wrapper resolved
            // nil in production.
            //
            // The composition root assembles the per-source docs DB map
            // + the docs-tier providers and hands them to
            // `LiveMarkdownLookupStrategy`. Adding a new docs source is
            // still a 2-file PR: the new source's provider declares its
            // `resourceListMode` and the registry append wires it here
            // automatically — no edit to Serve or the MCP dispatcher.
            let resourceRegistry = CLIImpl.makeProductionSourceRegistry()
            let resourceProviders = resourceRegistry.allEnabled
            let dbURLs: [String: URL] = resourceProviders
                .filter { $0.destinationDB != .packages && $0.destinationDB != .appleSampleCode }
                .reduce(into: [:]) { dict, provider in
                    dict[provider.definition.id] = paths.baseDirectory
                        .appendingPathComponent(provider.destinationDB.filename)
                }
            // Schemes the provider advertises: `<sourceID>://` for every
            // docs source whose DB can enumerate MCP-resource URIs.
            let knownURISchemes = Set(
                resourceProviders
                    .filter { $0.resourceListMode != .none }
                    .map { "\($0.definition.id)://" }
            )
            let markdownLookup = LiveMarkdownLookupStrategy(
                providers: resourceProviders,
                dbURLs: dbURLs,
                samplesDBURL: sampleDBURL,
                packagesDBURL: packagesDBURL,
                searchDatabaseFactory: LiveSearchDatabaseFactory(),
                sampleDatabaseFactory: LiveSampleIndexDatabaseFactory(),
                packageFileLookup: LivePackageFileLookupStrategy(),
                logger: Cupertino.Context.composition.logging.recording
            )
            let resourceProvider = MCP.Support.DocsResourceProvider(
                knownURISchemes: knownURISchemes,
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

            // #1286: open EVERY per-source docs DB (not just the apple-docs
            // primary) so the MCP unified fan-out searches all of them, the
            // way the CLI's `buildFetchers` does. Pre-#1286 the serve
            // composition wired only the single apple-docs `searchIndex`, so
            // the MCP / desktop search returned hig / apple-archive /
            // swift-evolution / swift-org / swift-book as empty even though
            // their per-source DBs are installed (the desktop searched 3 of 8
            // sources). `dbURLs` is the registry-derived per-source docs DB
            // map (keyed by source id); reuse the already-open `searchIndex`
            // for apple-docs and open the rest read-only. A missing or
            // schema-mismatched per-source DB is skipped (that source simply
            // contributes nothing), matching the single-index degradation.
            var docsIndexBySource: [String: any SearchModule.Database] = [:]
            for (sourceID, url) in dbURLs {
                if url == dbURL, let searchIndex {
                    docsIndexBySource[sourceID] = searchIndex
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if let perSourceIndex = try? await SearchModule.Index(
                    dbPath: url,
                    logger: Cupertino.Context.composition.logging.recording,
                    indexers: [:],
                    sourceLookup: .empty,
                    readOnly: true
                ) {
                    docsIndexBySource[sourceID] = perSourceIndex
                }
            }

            // Register composite tool provider with both indexes. The
            // service-layer wrappers are constructed here at the
            // composition root and passed across the protocol seam so
            // SearchToolProvider doesn't have to construct them itself.
            // #1286: route source-scoped docs operations (specific-source
            // search, list_documents, list_children) to per-source DBs too.
            let docsService: (any Services.DocsSearcher)? = searchIndex.map {
                Services.DocsSearchService(database: $0, docsIndexBySource: docsIndexBySource)
            }
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
                        packagesSearcher: packagesSearcher,
                        docsIndexBySource: docsIndexBySource
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
                searchToolRoutesByID: searchToolRoutesByID,
                // #1277: the registry-derived active-source inventory (presence + schema version),
                // so the `list_sources` tool can report which per-source databases are installed
                // and clients can detect a missing/partial corpus and guide setup.
                sourceInventory: sourceInventory
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

            // #1162: mirror the database-health summary + the actionable
            // "run `cupertino setup`" diagnostic to STDERR. The same lines
            // already go through `Recording` (os.log), but the console sink
            // is disabled to keep stdout a clean JSON-RPC channel, so an
            // operator watching stderr (their server-output panel) never
            // sees why search returns nothing. stdout is the protocol
            // channel, not stderr, so this cannot corrupt the stream.
            for line in CLIImpl.serveDatabaseHealthBanner(
                inventory: sourceInventory,
                searchIndexDisabledReason: searchIndexDisabledReason
            ) {
                fputs(line + "\n", stderr)
                Cupertino.Context.composition.logging.recording.info(line, category: .mcp)
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
                // #1194: MCP serve is a read path; open read-only.
                return try await Sample.Index.Database(dbPath: sampleDBURL, logger: Cupertino.Context.composition.logging.recording, readOnly: true)
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

        private func loadSearchIndex(dbURL: URL) async -> SearchIndexLoadResult {
            guard FileManager.default.fileExists(atPath: dbURL.path) else {
                let infoMsg = "ℹ️  Search index not found at: \(dbURL.path)"
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
                // #1194: MCP serve is a read path; open read-only so a query
                // connection cannot write or delete rows.
                let index = try await SearchModule.Index(
                    dbPath: dbURL,
                    logger: Cupertino.Context.composition.logging.recording,
                    indexers: [:],
                    sourceLookup: .empty,
                    readOnly: true
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
            dbURL: URL,
            sampleDBURL: URL
        ) {
            var messages = ["🚀 Cupertino MCP Server starting..."]

            // Add search DB path if it exists
            if FileManager.default.fileExists(atPath: dbURL.path) {
                messages.append("   Search DB: \(dbURL.path)")
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

        private func checkForData(docsDir _: URL, evolutionDir _: URL, dbURL: URL, sampleDB: URL) -> Bool {
            let fileManager = FileManager.default

            // Check if either database exists
            let hasSearchDB = fileManager.fileExists(atPath: dbURL.path)
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

import ArgumentParser
import Core
import CoreProtocols
import Darwin
import Foundation
import LoggingModels
import Logging
import MCPCore
import MCPSupport
import SampleIndex
import SampleIndexModels
import Search
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

            Unified Search (requires 'cupertino save' or 'cupertino save --samples'):
            • search - Smart query fanned out across every available source
                       (apple-docs, samples, swift-evolution, swift-org, swift-book,
                       packages, hig, apple-archive), reciprocal-rank fused.

            Documentation Tools (requires 'cupertino save'):
            • list_frameworks - List available frameworks with document counts
            • read_document   - Read full document content by URI

            Sample Code Tools (requires 'cupertino save --samples'):
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

        mutating func run() async throws {
            // Reap any sibling `cupertino serve` processes of the same binary
            // before we bind stdio. MCP host config reloads (Claude Desktop,
            // Cursor, etc.) leave orphan servers behind otherwise — they pin
            // SQLite read locks and stack RAM usage. (#242)
            ServeReaper.reapSiblings()

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
                evolutionURL: evolutionURL,
                archiveURL: archiveURL,
                searchDBURL: searchDBURL,
                sampleDBURL: sampleDBURL
            )

            printStartupMessages(
                config: config,
                evolutionURL: evolutionURL,
                searchDBURL: searchDBURL,
                sampleDBURL: sampleDBURL
            )

            let transport = MCP.Core.Transport.Stdio()
            try await server.connect(transport)

            // Keep running indefinitely
            while true {
                try await Task.sleep(for: .seconds(60))
            }
        }

        private func registerProviders(
            server: MCP.Core.Server,
            config: Shared.Configuration,
            evolutionURL: URL,
            archiveURL: URL,
            searchDBURL: URL,
            sampleDBURL: URL
        ) async {
            // Initialize search index if available
            let searchIndex: SearchModule.Index? = await loadSearchIndex(searchDBURL: searchDBURL)

            // Register resource provider with optional search-index markdown
            // lookup. The provider doesn't see the Search target — it just
            // gets a strategy that returns markdown for a URI, or nil if the
            // URI isn't indexed. This keeps MCPSupport free of the Search
            // import per the DI epic (#406).
            let markdownLookup: (any MCP.Support.MarkdownLookupStrategy)?
            if let searchIndex {
                markdownLookup = LiveMarkdownLookupStrategy(searchIndex: searchIndex)
            } else {
                markdownLookup = nil
            }
            let resourceProvider = MCP.Support.DocsResourceProvider(
                configuration: config,
                evolutionDirectory: evolutionURL,
                archiveDirectory: archiveURL,
                markdownLookup: markdownLookup,
                logger: Cupertino.Context.composition.logging.recording
            )
            await server.registerResourceProvider(resourceProvider)

            // Initialize sample code index if available
            let sampleIndex = await loadSampleIndex(sampleDBURL: sampleDBURL)

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
                (searchIndex == nil && sampleIndex == nil)
                    ? nil
                    : Services.UnifiedSearchService(searchIndex: searchIndex, sampleDatabase: sampleIndex)
            let toolProvider = CompositeToolProvider(
                searchIndex: searchIndex,
                sampleDatabase: sampleIndex,
                docsService: docsService,
                sampleService: sampleService,
                teaserService: teaserService,
                unifiedService: unifiedService
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

        private func loadSearchIndex(searchDBURL: URL) async -> SearchModule.Index? {
            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                let infoMsg = "ℹ️  Search index not found at: \(searchDBURL.path)"
                let cmd = "\(Shared.Constants.App.commandName) save"
                let hintMsg = "   Tools will not be available. Run '\(cmd)' to enable search."
                Cupertino.Context.composition.logging.recording.info("\(infoMsg) \(hintMsg)", category: .mcp)
                return nil
            }

            do {
                return try await SearchModule.Index(dbPath: searchDBURL, logger: Cupertino.Context.composition.logging.recording)
            } catch {
                let errorMsg = "⚠️  Failed to load search index: \(error)"
                let cmd = "\(Shared.Constants.App.commandName) save"
                let hintMsg = "   Tools will not be available. Run '\(cmd)' to create the index."
                Cupertino.Context.composition.logging.recording.warning("\(errorMsg) \(hintMsg)", category: .mcp)
                return nil
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
              $ \(cmd) fetch --type docs

            • Swift Evolution Proposals:
              $ \(cmd) fetch --type evolution

            • Swift.org Documentation:
              $ \(cmd) fetch --type swift

            • Swift Packages (priority packages):
              $ \(cmd) fetch --type packages

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

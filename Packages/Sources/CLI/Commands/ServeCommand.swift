import ArgumentParser
import Core
import Foundation
import Logging
import MCP
import MCPSupport
import Search
import SearchToolProvider
import Shared

// MARK: - Serve Command

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start MCP server for documentation access",
        discussion: """
        Starts the Model Context Protocol (MCP) server that provides documentation
        search and access capabilities for AI assistants.

        The server communicates via stdio using JSON-RPC and provides:
        • Resource providers for documentation access
        • Search tools for querying indexed documentation

        The server runs indefinitely until terminated.
        """
    )

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.docsDir))
    var docsDir: String = Shared.Constants.defaultDocsDirectory.path

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.evolutionDir))
    var evolutionDir: String = Shared.Constants.defaultSwiftEvolutionDirectory.path

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.searchDB))
    var searchDB: String = Shared.Constants.defaultSearchDatabase.path

    mutating func run() async throws {
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                outputDirectory: URL(fileURLWithPath: docsDir).expandingTildeInPath
            )
        )

        let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
        let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

        // Check if there's anything to serve
        let hasData = checkForData(
            docsDir: config.crawler.outputDirectory,
            evolutionDir: evolutionURL,
            searchDB: searchDBURL
        )

        if !hasData {
            printGettingStartedGuide()
            throw ExitCode.failure
        }

        let server = MCPServer(name: Shared.Constants.App.mcpServerName, version: Shared.Constants.App.version)

        await registerProviders(
            server: server,
            config: config,
            evolutionURL: evolutionURL,
            searchDBURL: searchDBURL
        )

        printStartupMessages(config: config, evolutionURL: evolutionURL, searchDBURL: searchDBURL)

        let transport = StdioTransport()
        try await server.connect(transport)

        // Keep running indefinitely
        while true {
            try await Task.sleep(for: .seconds(60))
        }
    }

    private func registerProviders(
        server: MCPServer,
        config: Shared.Configuration,
        evolutionURL: URL,
        searchDBURL: URL
    ) async {
        let resourceProvider = DocsResourceProvider(
            configuration: config,
            evolutionDirectory: evolutionURL
        )
        await server.registerResourceProvider(resourceProvider)

        await registerSearchProvider(server: server, searchDBURL: searchDBURL)
    }

    private func registerSearchProvider(server: MCPServer, searchDBURL: URL) async {
        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            let infoMsg = "ℹ️  Search index not found at: \(searchDBURL.path)"
            let cmd = "\(Shared.Constants.App.commandName) data index"
            let hintMsg = "   Tools will not be available. Run '\(cmd)' to enable search."
            Logging.Logger.mcp.info("\(infoMsg) \(hintMsg)")
            fputs("\(infoMsg)\n", stderr)
            fputs("\(hintMsg)\n", stderr)
            return
        }

        do {
            let searchIndex = try await Search.Index(dbPath: searchDBURL)
            let toolProvider = CupertinoSearchToolProvider(searchIndex: searchIndex)
            await server.registerToolProvider(toolProvider)
            let message = "✅ Search enabled (index found)"
            Logging.Logger.mcp.info(message)
            fputs("\(message)\n", stderr)
        } catch {
            let errorMsg = "⚠️  Failed to load search index: \(error)"
            let cmd = "\(Shared.Constants.App.commandName) data index"
            let hintMsg = "   Tools will not be available. Run '\(cmd)' to create the index."
            Logging.Logger.mcp.warning("\(errorMsg) \(hintMsg)")
            fputs("\(errorMsg)\n", stderr)
            fputs("\(hintMsg)\n", stderr)
        }
    }

    private func printStartupMessages(config: Shared.Configuration, evolutionURL: URL, searchDBURL: URL) {
        let messages = [
            "🚀 Cupertino MCP Server starting...",
            "   Apple docs: \(config.crawler.outputDirectory.path)",
            "   Evolution: \(evolutionURL.path)",
            "   Search DB: \(searchDBURL.path)",
            "   Waiting for client connection...",
        ]

        for message in messages {
            Logging.Logger.mcp.info(message)
            fputs("\(message)\n", stderr)
        }
        fputs("\n", stderr)
    }

    private func checkForData(docsDir: URL, evolutionDir: URL, searchDB: URL) -> Bool {
        let fm = FileManager.default

        // Check if any data directories exist and contain files
        let hasAppleDocs = fm.fileExists(atPath: docsDir.path) &&
            (try? fm.contentsOfDirectory(atPath: docsDir.path).filter { !$0.hasPrefix(".") })?.isEmpty == false

        let hasEvolution = fm.fileExists(atPath: evolutionDir.path) &&
            (try? fm.contentsOfDirectory(atPath: evolutionDir.path).filter { !$0.hasPrefix(".") })?.isEmpty == false

        let hasSearchDB = fm.fileExists(atPath: searchDB.path)

        return hasAppleDocs || hasEvolution || hasSearchDB
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

        📚 STEP 1: Crawl Documentation
        ───────────────────────────────────────────────────────────────────────────
        First, download the documentation you want to serve:

        • Apple Developer Documentation (recommended):
          $ \(cmd) crawl --type docs

        • Swift Evolution Proposals:
          $ \(cmd) crawl --type evolution

        • Swift.org Documentation:
          $ \(cmd) crawl --type swift

        • Swift Packages (priority packages):
          $ \(cmd) fetch --type packages

        ⏱️  Crawling takes 10-30 minutes depending on content type.
           You can resume if interrupted with --resume flag.

        🔍 STEP 2: Build Search Index
        ───────────────────────────────────────────────────────────────────────────
        After crawling, create a search index for fast lookups:

          $ \(cmd) index

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

        fputs(guide, stderr)
    }
}

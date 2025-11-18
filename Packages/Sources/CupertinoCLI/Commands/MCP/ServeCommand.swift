import ArgumentParser
import CupertinoCore
import CupertinoLogging
import CupertinoMCPSupport
import CupertinoSearch
import CupertinoSearchToolProvider
import CupertinoShared
import Foundation
import MCPServer
import MCPTransport

// MARK: - Serve Command

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: CupertinoConstants.HelpText.mcpAbstract,
        discussion: """
        Starts the Model Context Protocol (MCP) server that provides documentation
        search and access capabilities for AI assistants.

        The server communicates via stdio using JSON-RPC and provides:
        • Resource providers for documentation access
        • Search tools for querying indexed documentation

        The server runs indefinitely until terminated.
        """
    )

    @Option(name: .long, help: ArgumentHelp(CupertinoConstants.HelpText.docsDir))
    var docsDir: String = CupertinoConstants.defaultDocsDirectory.path

    @Option(name: .long, help: ArgumentHelp(CupertinoConstants.HelpText.evolutionDir))
    var evolutionDir: String = CupertinoConstants.defaultSwiftEvolutionDirectory.path

    @Option(name: .long, help: ArgumentHelp(CupertinoConstants.HelpText.searchDB))
    var searchDB: String = CupertinoConstants.defaultSearchDatabase.path

    mutating func run() async throws {
        let config = CupertinoConfiguration(
            crawler: CrawlerConfiguration(
                outputDirectory: URL(fileURLWithPath: docsDir).expandingTildeInPath
            )
        )

        let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
        let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

        let server = MCPServer(name: CupertinoConstants.App.mcpServerName, version: CupertinoConstants.App.version)

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
        config: CupertinoConfiguration,
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
            let cmd = "\(CupertinoConstants.App.commandName) data index"
            let hintMsg = "   Tools will not be available. Run '\(cmd)' to enable search."
            CupertinoLogger.mcp.info("\(infoMsg) \(hintMsg)")
            fputs("\(infoMsg)\n", stderr)
            fputs("\(hintMsg)\n", stderr)
            return
        }

        do {
            let searchIndex = try await SearchIndex(dbPath: searchDBURL)
            let toolProvider = CupertinoSearchToolProvider(searchIndex: searchIndex)
            await server.registerToolProvider(toolProvider)
            let message = "✅ Search enabled (index found)"
            CupertinoLogger.mcp.info(message)
            fputs("\(message)\n", stderr)
        } catch {
            let errorMsg = "⚠️  Failed to load search index: \(error)"
            let cmd = "\(CupertinoConstants.App.commandName) data index"
            let hintMsg = "   Tools will not be available. Run '\(cmd)' to create the index."
            CupertinoLogger.mcp.warning("\(errorMsg) \(hintMsg)")
            fputs("\(errorMsg)\n", stderr)
            fputs("\(hintMsg)\n", stderr)
        }
    }

    private func printStartupMessages(config: CupertinoConfiguration, evolutionURL: URL, searchDBURL: URL) {
        let messages = [
            "🚀 Cupertino MCP Server starting...",
            "   Apple docs: \(config.crawler.outputDirectory.path)",
            "   Evolution: \(evolutionURL.path)",
            "   Search DB: \(searchDBURL.path)",
            "   Waiting for client connection...",
        ]

        for message in messages {
            CupertinoLogger.mcp.info(message)
            fputs("\(message)\n", stderr)
        }
        fputs("\n", stderr)
    }
}

import ArgumentParser
import Core
import Foundation
import Logging
import MCP
import MCPSupport
import SampleIndex
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

        Documentation Tools (requires 'cupertino save'):
        • search_docs - Full-text search across all documentation
        • list_frameworks - List available frameworks with document counts
        • read_document - Read full document content by URI

        Sample Code Tools (requires 'cupertino index'):
        • search_samples - Search sample code projects and files
        • list_samples - List all indexed sample projects
        • read_sample - Read sample project README
        • read_sample_file - Read specific source file from a sample

        The server runs indefinitely until terminated.
        """
    )

    mutating func run() async throws {
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                outputDirectory: Shared.Constants.defaultDocsDirectory
            )
        )

        let evolutionURL = Shared.Constants.defaultSwiftEvolutionDirectory
        let searchDBURL = Shared.Constants.defaultSearchDatabase

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
        // Initialize search index if available
        let searchIndex: Search.Index? = await loadSearchIndex(searchDBURL: searchDBURL)

        // Register resource provider with optional search index
        let resourceProvider = DocsResourceProvider(
            configuration: config,
            evolutionDirectory: evolutionURL,
            searchIndex: searchIndex
        )
        await server.registerResourceProvider(resourceProvider)

        // Register search tool provider if index is available
        if let searchIndex {
            let toolProvider = CupertinoSearchToolProvider(searchIndex: searchIndex)
            await server.registerToolProvider(toolProvider)
            let message = "✅ Search enabled (index found)"
            Log.info(message, category: .mcp)
        }

        // Register sample code tool provider if index is available
        let sampleIndex = await loadSampleIndex()
        if let sampleIndex {
            let sampleToolProvider = SampleToolProvider(database: sampleIndex)
            await server.registerToolProvider(sampleToolProvider)
            let message = "✅ Sample code search enabled (index found)"
            Log.info(message, category: .mcp)
        }
    }

    private func loadSampleIndex() async -> SampleIndex.Database? {
        let sampleDBURL = SampleIndex.defaultDatabasePath
        guard FileManager.default.fileExists(atPath: sampleDBURL.path) else {
            let infoMsg = "ℹ️  Sample code index not found at: \(sampleDBURL.path)"
            let cmd = "\(Shared.Constants.App.commandName) index"
            let hintMsg = "   Sample tools will not be available. Run '\(cmd)' to enable."
            Log.info("\(infoMsg) \(hintMsg)", category: .mcp)
            return nil
        }

        do {
            let sampleIndex = try await SampleIndex.Database(dbPath: sampleDBURL)
            return sampleIndex
        } catch {
            let errorMsg = "⚠️  Failed to load sample index: \(error)"
            let cmd = "\(Shared.Constants.App.commandName) index"
            let hintMsg = "   Sample tools will not be available. Run '\(cmd)' to create the index."
            Log.warning("\(errorMsg) \(hintMsg)", category: .mcp)
            return nil
        }
    }

    private func loadSearchIndex(searchDBURL: URL) async -> Search.Index? {
        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            let infoMsg = "ℹ️  Search index not found at: \(searchDBURL.path)"
            let cmd = "\(Shared.Constants.App.commandName) data index"
            let hintMsg = "   Tools will not be available. Run '\(cmd)' to enable search."
            Log.info("\(infoMsg) \(hintMsg)", category: .mcp)
            return nil
        }

        do {
            let searchIndex = try await Search.Index(dbPath: searchDBURL)
            return searchIndex
        } catch {
            let errorMsg = "⚠️  Failed to load search index: \(error)"
            let cmd = "\(Shared.Constants.App.commandName) data index"
            let hintMsg = "   Tools will not be available. Run '\(cmd)' to create the index."
            Log.warning("\(errorMsg) \(hintMsg)", category: .mcp)
            return nil
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
            Log.info(message, category: .mcp)
        }
    }

    private func checkForData(docsDir: URL, evolutionDir: URL, searchDB: URL) -> Bool {
        let fileManager = FileManager.default

        // Check if any data directories exist and contain files
        let hasAppleDocs = fileManager.fileExists(atPath: docsDir.path) &&
            (try? fileManager.contentsOfDirectory(atPath: docsDir.path).filter { !$0.hasPrefix(".") })?.isEmpty == false

        let evolutionContents = try? fileManager.contentsOfDirectory(atPath: evolutionDir.path)
            .filter { !$0.hasPrefix(".") }
        let hasEvolution = fileManager.fileExists(atPath: evolutionDir.path) && evolutionContents?.isEmpty == false

        let hasSearchDB = fileManager.fileExists(atPath: searchDB.path)

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

        // Use stderr for getting started guide (stdout is for MCP protocol)
        fputs(guide, stderr)
    }
}

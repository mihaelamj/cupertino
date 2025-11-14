import ArgumentParser
import DocsSearchToolProvider
import DocsuckerCore
import DocsuckerLogging
import DocsuckerMCPSupport
import DocsuckerSearch
import DocsuckerShared
import Foundation
import MCPServer
import MCPTransport

// MARK: - Docsucker MCP Server CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AppleDocsuckerMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appledocsucker-mcp",
        abstract: "MCP Server for Apple Documentation and Swift Evolution",
        version: "0.1.0",
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Serve Command

extension AppleDocsuckerMCP {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Serve: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start MCP server (serves docs to AI agents like Claude)"
        )

        @Option(name: .long, help: "Apple documentation directory")
        var docsDir: String = "~/.docsucker/docs"

        @Option(name: .long, help: "Swift Evolution proposals directory")
        var evolutionDir: String = "~/.docsucker/swift-evolution"

        @Option(name: .long, help: "Search database path")
        var searchDB: String = "~/.docsucker/search.db"

        mutating func run() async throws {
            let config = DocsuckerConfiguration(
                crawler: CrawlerConfiguration(
                    outputDirectory: URL(fileURLWithPath: docsDir).expandingTildeInPath
                )
            )

            let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

            let server = MCPServer(name: "docsucker", version: "0.1.0")

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
            config: DocsuckerConfiguration,
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
                let hintMsg = "   Tools will not be available. Run 'appledocsucker build-index' to enable search."
                DocsuckerLogger.mcp.info("\(infoMsg) \(hintMsg)")
                fputs("\(infoMsg)\n", stderr)
                fputs("\(hintMsg)\n", stderr)
                return
            }

            do {
                let searchIndex = try await SearchIndex(dbPath: searchDBURL)
                let toolProvider = DocsSearchToolProvider(searchIndex: searchIndex)
                await server.registerToolProvider(toolProvider)
                let message = "✅ Search enabled (index found)"
                DocsuckerLogger.mcp.info(message)
                fputs("\(message)\n", stderr)
            } catch {
                let errorMsg = "⚠️  Failed to load search index: \(error)"
                let hintMsg = "   Tools will not be available. Run 'appledocsucker build-index' to create the index."
                DocsuckerLogger.mcp.warning("\(errorMsg) \(hintMsg)")
                fputs("\(errorMsg)\n", stderr)
                fputs("\(hintMsg)\n", stderr)
            }
        }

        private func printStartupMessages(config: DocsuckerConfiguration, evolutionURL: URL, searchDBURL: URL) {
            let messages = [
                "🚀 AppleDocsucker MCP Server starting...",
                "   Apple docs: \(config.crawler.outputDirectory.path)",
                "   Evolution: \(evolutionURL.path)",
                "   Search DB: \(searchDBURL.path)",
                "   Waiting for client connection...",
            ]

            for message in messages {
                DocsuckerLogger.mcp.info(message)
                fputs("\(message)\n", stderr)
            }
            fputs("\n", stderr)
        }
    }
}

import Foundation
import ArgumentParser
import MCPServer
import MCPTransport
import DocsuckerShared
import DocsuckerCore
import DocsuckerMCPSupport
import DocsuckerSearch
import DocsSearchToolProvider
import DocsuckerLogging

// MARK: - Docsucker MCP Server CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AppleDocsuckerMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appledocsucker-mcp",
        abstract: "MCP Server for Apple Documentation and Swift Evolution",
        version: "1.0.0",
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
            // Create configuration
            let config = DocsuckerConfiguration(
                crawler: CrawlerConfiguration(
                    outputDirectory: URL(fileURLWithPath: docsDir).expandingTildeInPath
                )
            )

            let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

            // Create MCP server
            let server = MCPServer(name: "docsucker", version: "1.0.0")

            // Register resource provider
            let resourceProvider = DocsResourceProvider(
                configuration: config,
                evolutionDirectory: evolutionURL
            )
            await server.registerResourceProvider(resourceProvider)

            // Register tool provider (search functionality)
            let hasSearchDB = FileManager.default.fileExists(atPath: searchDBURL.path)
            if hasSearchDB {
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
            } else {
                let infoMsg = "ℹ️  Search index not found at: \(searchDBURL.path)"
                let hintMsg = "   Tools will not be available. Run 'appledocsucker build-index' to enable search."
                DocsuckerLogger.mcp.info("\(infoMsg) \(hintMsg)")
                fputs("\(infoMsg)\n", stderr)
                fputs("\(hintMsg)\n", stderr)
            }

            // Connect to stdio transport
            let transport = StdioTransport()

            let startupMessages = [
                "🚀 AppleDocsucker MCP Server starting...",
                "   Apple docs: \(config.crawler.outputDirectory.path)",
                "   Evolution: \(evolutionURL.path)",
                "   Search DB: \(searchDBURL.path)",
                "   Waiting for client connection...",
            ]

            for message in startupMessages {
                DocsuckerLogger.mcp.info(message)
                fputs("\(message)\n", stderr)
            }
            fputs("\n", stderr)

            try await server.connect(transport)

            // Keep running indefinitely
            try await Task.sleep(for: .seconds(TimeInterval.infinity))
        }
    }
}

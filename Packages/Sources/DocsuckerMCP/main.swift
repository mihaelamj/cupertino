import Foundation
import ArgumentParser
import MCPServer
import MCPTransport
import DocsuckerShared
import DocsuckerCore
import DocsuckerMCPSupport

// MARK: - Docsucker MCP Server CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct DocsuckerMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "MCP Server for Apple Documentation and Swift Evolution",
        version: "1.0.0",
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Serve Command

extension DocsuckerMCP {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Serve: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start MCP server (serves docs to AI agents like Claude)"
        )

        @Option(name: .long, help: "Apple documentation directory")
        var docsDir: String = "~/.docsucker/docs"

        @Option(name: .long, help: "Swift Evolution proposals directory")
        var evolutionDir: String = "~/.docsucker/swift-evolution"

        mutating func run() async throws {
            // Create configuration
            let config = DocsuckerConfiguration(
                crawler: CrawlerConfiguration(
                    outputDirectory: URL(fileURLWithPath: docsDir).expandingTildeInPath
                )
            )

            let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath

            // Create MCP server
            let server = MCPServer(name: "docsucker", version: "1.0.0")

            // Register resource provider
            let resourceProvider = DocsResourceProvider(
                configuration: config,
                evolutionDirectory: evolutionURL
            )
            await server.registerResourceProvider(resourceProvider)

            // Connect to stdio transport
            let transport = StdioTransport()

            fputs("🚀 Docsucker MCP Server starting...\n", stderr)
            fputs("   Apple docs: \(config.crawler.outputDirectory.path)\n", stderr)
            fputs("   Evolution: \(evolutionURL.path)\n", stderr)
            fputs("   Waiting for client connection...\n\n", stderr)

            try await server.connect(transport)

            // Keep running indefinitely
            try await Task.sleep(for: .seconds(TimeInterval.infinity))
        }
    }
}

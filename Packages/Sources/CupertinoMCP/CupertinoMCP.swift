import ArgumentParser
import CupertinoShared

// MARK: - Cupertino MCP Server CLI

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct CupertinoMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: CupertinoConstants.App.mcpCommandName,
        abstract: "MCP Server for Apple Documentation, Swift Evolution, Swift Packages, and Code Samples",
        version: CupertinoConstants.App.version,
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

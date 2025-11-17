import ArgumentParser
import CupertinoShared

// MARK: - Cupertino MCP Server CLI

@available(macOS 15.0, *)
struct CupertinoMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: CupertinoConstants.App.mcpCommandName,
        abstract: CupertinoConstants.HelpText.mcpAbstract,
        version: CupertinoConstants.App.version,
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

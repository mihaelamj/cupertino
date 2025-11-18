import ArgumentParser

// MARK: - MCP Command

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP server operations",
        discussion: """
        Commands for running and managing the Model Context Protocol (MCP) server.

        The MCP server provides documentation search and access capabilities
        for AI assistants like Claude.
        """,
        subcommands: [
            ServeCommand.self,
            MCPDoctorCommand.self,
        ],
        defaultSubcommand: ServeCommand.self
    )
}

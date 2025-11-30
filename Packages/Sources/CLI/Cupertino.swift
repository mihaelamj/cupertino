import ArgumentParser
import Shared

// MARK: - Cupertino CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct Cupertino: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: Shared.Constants.App.commandName,
        abstract: "MCP Server for Apple Documentation, Swift Evolution, and Swift Packages",
        version: Shared.Constants.App.version,
        subcommands: [
            FetchCommand.self,
            SaveCommand.self,
            ServeCommand.self,
            SearchCommand.self,
            ReadCommand.self,
            DoctorCommand.self,
        ],
        defaultSubcommand: ServeCommand.self
    )
}

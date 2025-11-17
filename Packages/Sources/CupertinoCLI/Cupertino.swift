import ArgumentParser
import CupertinoShared

// MARK: - Cupertino CLI

@available(macOS 15.0, *)
struct Cupertino: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: CupertinoConstants.App.commandName,
        abstract: "Apple Documentation Crawler and Indexer",
        version: CupertinoConstants.App.version,
        subcommands: [Crawl.self, Fetch.self, Index.self],
        defaultSubcommand: Crawl.self
    )
}

import ArgumentParser
import CupertinoShared

// MARK: - Cupertino CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct Cupertino: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: CupertinoConstants.App.commandName,
        abstract: "Apple Documentation Crawler and Indexer",
        version: CupertinoConstants.App.version,
        subcommands: [Crawl.self, Fetch.self, Index.self],
        defaultSubcommand: Crawl.self
    )
}

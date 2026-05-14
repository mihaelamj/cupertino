import ArgumentParser
import Darwin
import SharedConstants
import SharedCore

// MARK: - Cupertino CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct Cupertino: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: Shared.Constants.App.commandName,
        abstract: "MCP Server for Apple Documentation, Swift Evolution, and Swift Packages",
        discussion: """
        SETUP
          setup            Download pre-built databases (search.db, samples.db, packages.db)

        DATA COLLECTION
          fetch            Download documentation, packages, and sample code from Apple / GitHub
          cleanup          Remove downloaded sample-code archives after indexing

        INDEXING
          save             Index fetched content into search.db, packages.db, and samples.db

        SERVER
          serve            Start the MCP server (default when no subcommand is given)

        QUERY
          search           Search across all documentation sources
          read             Read a full document by URI
          list-frameworks  List indexed frameworks with document counts

        SAMPLE CODE
          list-samples     List indexed Apple sample projects
          read-sample      Read a sample project README and metadata
          read-sample-file Read a source file from a sample project

        DIAGNOSTICS
          doctor           Check server health, database state, and save readiness
          resolve-refs     Rewrite unresolved doc:// markers in saved page content

        Run 'cupertino <command> --help' for per-command options.
        """,
        version: Shared.Constants.App.version,
        subcommands: [
            CLI.Command.Setup.self,
            CLI.Command.Fetch.self,
            CLI.Command.Save.self,
            CLI.Command.Serve.self,
            CLI.Command.Search.self,
            CLI.Command.Read.self,
            CLI.Command.ListFrameworks.self,
            CLI.Command.ListSamples.self,
            CLI.Command.ReadSample.self,
            CLI.Command.ReadSampleFile.self,
            CLI.Command.Doctor.self,
            CLI.Command.Cleanup.self,
            CLI.Command.PackageSearch.self,
            CLI.Command.ResolveRefs.self,
        ],
        defaultSubcommand: CLI.Command.Serve.self
    )

    /// Force stdout to line-buffered mode before any subcommand runs. By
    /// default, libc switches stdout to block-buffered (4–8 KB) when it
    /// detects a non-tty (i.e. piped to `tee`, redirected to a file). That
    /// makes long-running fetches appear hung — output piles up inside the
    /// process for minutes before flushing. Line-buffered means every `\n`
    /// flushes immediately, which is what the user expects.
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)

        // Replicates the default `AsyncParsableCommand.main()` body so the
        // override doesn't lose any behaviour.
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}

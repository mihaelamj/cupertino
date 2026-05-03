import ArgumentParser
import Darwin
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
            SetupCommand.self,
            FetchCommand.self,
            SaveCommand.self,
            ServeCommand.self,
            SearchCommand.self,
            ReadCommand.self,
            ListFrameworksCommand.self,
            ListSamplesCommand.self,
            ReadSampleCommand.self,
            ReadSampleFileCommand.self,
            DoctorCommand.self,
            CleanupCommand.self,
            PackageSearchCommand.self,
            ResolveRefsCommand.self,
        ],
        defaultSubcommand: ServeCommand.self
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

import ArgumentParser
import SearchModels

// MARK: - Shared platform-floor options (#962 MCP/CLI parity)

extension CLIImpl {
    /// The five `min_<platform>` version floors that the AST search MCP tools
    /// (`search_symbols`, `search_property_wrappers`, `search_concurrency`,
    /// `search_conformances`, `search_generics`) expose via their shared
    /// `platformFilterProperties` schema fragment. Lifted into one
    /// `@OptionGroup` so every AST CLI subcommand mirrors that fragment exactly
    /// instead of redeclaring five options per command.
    struct PlatformFloorOptions: ParsableArguments {
        @Option(name: .long, help: "Minimum iOS version filter (e.g. 17.0).")
        var minIos: String?

        @Option(name: .long, help: "Minimum macOS version filter (e.g. 14.0).")
        var minMacos: String?

        @Option(name: .long, help: "Minimum tvOS version filter (e.g. 17.0).")
        var minTvos: String?

        @Option(name: .long, help: "Minimum watchOS version filter (e.g. 10.0).")
        var minWatchos: String?

        @Option(name: .long, help: "Minimum visionOS version filter (e.g. 1.0).")
        var minVisionos: String?

        /// Build the validated value type the shared
        /// `Search.Database.applyingPlatformFloors` consumes.
        /// - Throws: `Search.Error.invalidQuery` on a malformed version string.
        func floors() throws -> Search.PlatformFloors {
            try Search.PlatformFloors(
                minIOS: minIos,
                minMacOS: minMacos,
                minTvOS: minTvos,
                minWatchOS: minWatchos,
                minVisionOS: minVisionos
            )
        }
    }
}

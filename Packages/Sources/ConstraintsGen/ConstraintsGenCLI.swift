import ArgumentParser

/// Root command for the `cupertino-constraints-gen` binary.
///
/// Standalone `AsyncParsableCommand` (not nested under
/// `ConstraintsGen.Command`) because ArgumentParser requires the
/// `@main`-annotated type to be at file scope. Mirrors the
/// `ReleaseCLI` pattern in the `cupertino-rel` binary.
@main
struct ConstraintsGenCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cupertino-constraints-gen",
        abstract: "Generate the authoritative Apple-type generic-constraints table from `swift symbolgraph-extract` output (#759 iteration 3).",
        subcommands: [
            ConstraintsGen.Command.Generate.self,
        ]
    )
}

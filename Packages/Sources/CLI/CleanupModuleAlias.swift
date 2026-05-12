import Cleanup

// MARK: - Cleanup Module Disambiguator

// `Command.Cleanup` (the subcommand struct under `Sources/CLI/Commands/`)
// and the `Cleanup` SPM target share a name. From inside any
// `extension Command` scope, bare `Cleanup.<Type>` resolves to the nested
// subcommand struct, not the SPM target — Swift's name lookup checks
// enclosing types before imported modules.
//
// `CleanupModule` pins the SPM target so callers in the CLI target can
// write `CleanupModule.SampleCodeCleaner` and reach the actual module type.
// One declaration covers every file in the CLI target.

typealias CleanupModule = Cleanup

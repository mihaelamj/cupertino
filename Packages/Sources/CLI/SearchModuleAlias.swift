import Search

// MARK: - Search Module Disambiguator

// `CLI.Command.Search` (the subcommand struct under `Sources/CLI/Commands/`) and
// the `Search` SPM target share a name. From inside any `extension CLI.Command`
// scope, bare `Search.<Type>` resolves to the nested subcommand struct, not
// the SPM target — Swift's name lookup checks enclosing types before
// imported modules, so the local match wins.
//
// `SearchModule` pins the SPM target at module-internal scope so callers in
// the CLI target can write `SearchModule.Index`, `SearchModule.SmartQuery`,
// etc. and reach the actual module types. One declaration covers every file
// in the CLI target.

typealias SearchModule = Search

import SearchAPI
import SearchModels

// MARK: - Search Module Disambiguator

// `CLIImpl.Command.Search` (the subcommand struct under `Sources/CLI/Commands/`) and
// the `Search` SPM target share a name. From inside any `extension CLIImpl.Command`
// scope, bare `Search.<Type>` resolves to the nested subcommand struct, not
// the SPM target — Swift's name lookup checks enclosing types before
// imported modules, so the local match wins.
//
// `SearchModule` pins the SPM target at module-internal scope so callers in
// the CLI target can write `SearchModule.Index`, `SearchModule.SmartQuery`,
// etc. and reach the actual module types. One declaration covers every file
// in the CLI target.
//
// #974: this file used to also carry 8 `Live*` factory / strategy
// structs. They were split into their own files under
// `Packages/Sources/CLI/` per the code-style "one non-private type
// per file" rule. The typealias is the only declaration here.

typealias SearchModule = Search

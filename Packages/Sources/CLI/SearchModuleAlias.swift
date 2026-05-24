import SearchAPI
import SearchModels

// MARK: - Search Module Disambiguator

// `SearchModule` aliases the `Search` namespace enum (declared in
// `SearchModels`). The disambiguation matters because
// `CLIImpl.Command.Search` (the subcommand struct under
// `Sources/CLI/Commands/`) shadows the namespace inside any
// `extension CLIImpl.Command` scope: bare `Search.<Type>` resolves
// to the nested subcommand struct, not the namespace, because
// Swift's name lookup checks enclosing types before imported modules.
//
// Callers needing to reach types like `Search.Index` (extension in
// `SearchSQLite`) or `Search.SmartQuery` (extension in `SearchAPI`)
// from inside an `extension CLIImpl.Command` block write
// `SearchModule.Index` / `SearchModule.SmartQuery` and get the
// intended namespace-extension types. One declaration covers every
// file in the CLI target.
//
// #974: this file used to also carry 8 `Live*` factory / strategy
// structs. They were split into their own files under
// `Packages/Sources/CLI/` per the code-style "one non-private type
// per file" rule. The typealias is the only declaration here.

typealias SearchModule = Search

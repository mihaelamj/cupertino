import Foundation
import MCPCore
import MCPSupport
import Search
import SearchModels
import Services
import ServicesModels

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

// MARK: - Production Search.DatabaseFactory

// Concrete `Search.DatabaseFactory` (GoF Factory Method) wired into every
// `Services.ServiceContainer.with*Service` and `Services.ReadService` call.
// Production wiring opens a `SearchModule.Index` at the resolved path —
// `Search.Index` conforms to `Search.Database` (the protocol in SearchModels)
// so the concrete actor flows through Services' protocol-typed inits
// unchanged. One declaration covers every callsite in CLI; tests substitute a
// mock conforming to `Search.DatabaseFactory`.

struct LiveSearchDatabaseFactory: Search.DatabaseFactory {
    func openDatabase(at url: URL) async throws -> any Search.Database {
        try await SearchModule.Index(dbPath: url)
    }
}

let searchDatabaseFactory: any Search.DatabaseFactory = LiveSearchDatabaseFactory()

// MARK: - Production MarkdownLookupStrategy

// Concrete `MCP.Support.DocsResourceProvider.MarkdownLookupStrategy`
// wrapping a `SearchModule.Index` actor's `getDocumentContent(uri:format:)`.
// Wired by `cupertino serve` when a search.db is available so the MCP
// resource provider can fall back to indexed markdown before going to
// the filesystem. MCPSupport stays free of `import Search`; only the
// CLI composition root reaches the actor.

struct LiveMarkdownLookupStrategy: MCP.Support.MarkdownLookupStrategy {
    let searchIndex: SearchModule.Index

    func lookup(uri: String) async throws -> String? {
        try await searchIndex.getDocumentContent(uri: uri, format: .markdown)
    }
}

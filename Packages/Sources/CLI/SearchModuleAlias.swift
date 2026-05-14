import Foundation
import MCPCore
import MCPSupport
import SampleIndex
import SampleIndexModels
import Search
import SearchModels
import Services
import ServicesModels
import SharedConstants

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

// MARK: - Production PackageFileLookupStrategy

// Concrete `Services.ReadService.PackageFileLookupStrategy` (GoF Strategy)
// wrapping the `SearchModule.PackageQuery` actor. Lives at the CLI
// composition root so `Services` doesn't need `import Search`.
// `cupertino read` wires one of these into every `Services.ReadService.read`
// call.

struct LivePackageFileLookupStrategy: Services.ReadService.PackageFileLookupStrategy {
    func fileContent(
        dbURL: URL,
        owner: String,
        repo: String,
        relpath: String
    ) async throws -> String? {
        let query = try await SearchModule.PackageQuery(dbPath: dbURL)
        defer { Task { await query.disconnect() } }
        return try await query.fileContent(owner: owner, repo: repo, relpath: relpath)
    }
}

// MARK: - Production Sample.Index.DatabaseFactory

// Concrete `Sample.Index.DatabaseFactory` (GoF Factory Method) wired
// into every `Services.ServiceContainer.with*SampleService` /
// `withTeaserService` / `withUnifiedSearchService` call. Parallel to
// `LiveSearchDatabaseFactory` on the docs side: opens a real
// `Sample.Index.Database` at the resolved path. `Services` builds the
// `Sample.Search.Service` wrapper internally — the composition root
// only knows about the low-level DB factory. `Services` no longer
// imports `SampleIndex`; the concrete actor is reached only here.

struct LiveSampleIndexDatabaseFactory: Sample.Index.DatabaseFactory {
    func openDatabase(at url: URL) async throws -> any Sample.Index.Reader {
        try await Sample.Index.Database(dbPath: url)
    }
}

let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

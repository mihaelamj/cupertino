import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
import Crawler
import CrawlerModels
import Foundation
import Logging
import LoggingModels
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

typealias SearchModule = Search

// MARK: - Production Search.DatabaseFactory

// Concrete `Search.DatabaseFactory` (GoF Factory Method, 1994 p. 107)
// wired into every `Services.ServiceContainer.with*Service` and
// `Services.ReadService` call. Production wiring opens a
// `SearchModule.Index` at the resolved path — `Search.Index` conforms
// to `Search.Database` (the protocol in SearchModels) so the concrete
// actor flows through Services' protocol-typed inits unchanged.
//
// Each command's `run()` method constructs a fresh instance at its
// own composition sub-root rather than reaching for a shared
// module-scope handle. The struct is stateless, so multiple instances
// are equivalent and a Singleton (p. 127) would add no value while
// pulling in the global-access drawback (Seemann, *Dependency
// Injection*, 2011, ch. 5: Service Locator anti-pattern).

struct LiveSearchDatabaseFactory: Search.DatabaseFactory {
    func openDatabase(at url: URL) async throws -> any Search.Database {
        try await SearchModule.Index(dbPath: url, logger: Logging.LiveRecording())
    }
}

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
        try await Sample.Index.Database(dbPath: url, logger: Logging.LiveRecording())
    }
}

// MARK: - Production Crawler Strategies (#505)

// Concrete `Crawler.HTMLParserStrategy` (GoF Strategy) — wraps
// `Core.Parser.HTML` pure static methods. Crawler doesn't import
// `Core`; only this composition root does. Same shape as
// `LiveMarkdownToStructuredPageStrategy` (#496).

struct LiveHTMLParserStrategy: Crawler.HTMLParserStrategy {
    func convert(html: String, url: URL) -> String {
        Core.Parser.HTML.convert(html, url: url)
    }

    func toStructuredPage(
        html: String,
        url: URL,
        source: Shared.Models.StructuredDocumentationPage.Source,
        depth: Int?
    ) -> Shared.Models.StructuredDocumentationPage? {
        Core.Parser.HTML.toStructuredPage(html, url: url, source: source, depth: depth)
    }

    func looksLikeHTTPErrorPage(html: String) -> Bool {
        Core.Parser.HTML.looksLikeHTTPErrorPage(html: html)
    }

    func looksLikeJavaScriptFallback(html: String) -> Bool {
        Core.Parser.HTML.looksLikeJavaScriptFallback(html: html)
    }
}

// Concrete `Crawler.AppleJSONParserStrategy` — wraps
// `Core.JSONParser.AppleJSONToMarkdown` pure static methods.

struct LiveAppleJSONParserStrategy: Crawler.AppleJSONParserStrategy {
    func convert(json: Data, url: URL) -> String? {
        Core.JSONParser.AppleJSONToMarkdown.convert(json, url: url)
    }

    func toStructuredPage(
        json: Data,
        url: URL,
        depth: Int?
    ) -> Shared.Models.StructuredDocumentationPage? {
        Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(json, url: url, depth: depth)
    }

    func jsonAPIURL(from documentationURL: URL) -> URL? {
        Core.JSONParser.AppleJSONToMarkdown.jsonAPIURL(from: documentationURL)
    }

    func documentationURL(from jsonAPIURL: URL) -> URL? {
        Core.JSONParser.AppleJSONToMarkdown.documentationURL(from: jsonAPIURL)
    }

    func extractLinks(from json: Data) -> [URL] {
        Core.JSONParser.AppleJSONToMarkdown.extractLinks(from: json)
    }
}

// Concrete `Crawler.PriorityPackageStrategy` — wraps
// `Core.PackageIndexing.PriorityPackageGenerator` (an actor). Used
// only when a Swift.org crawl completes and the priority-package
// catalog needs regenerating.

struct LivePriorityPackageStrategy: Crawler.PriorityPackageStrategy {
    func generate(
        swiftOrgDocsPath: URL,
        outputPath: URL
    ) async throws -> Crawler.PriorityPackageOutcome {
        let generator = Core.PackageIndexing.PriorityPackageGenerator(
            swiftOrgDocsPath: swiftOrgDocsPath,
            outputPath: outputPath,
            logger: Logging.LiveRecording()
        )
        let list = try await generator.generate()
        return Crawler.PriorityPackageOutcome(
            totalUniqueReposFound: list.stats.totalUniqueReposFound
        )
    }
}

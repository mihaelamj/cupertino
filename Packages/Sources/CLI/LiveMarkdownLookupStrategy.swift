import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
import CrawlerModels
import Foundation
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SearchAPI
import SearchModels
import SearchSQLite
import Services
import ServicesModels
import SharedConstants

// MARK: - Production MarkdownLookupStrategy

// Concrete `MCP.Support.MarkdownLookupStrategy` backing the MCP
// `resources/{list,read}` path with the SAME per-source DB read path
// the MCP search/read TOOLS use (`Services.ReadService` +
// `CLIImpl.makeProductionSourceRegistry()`). Principle 7
// (`docs/PRINCIPLES.md`): both methods resolve content / enumeration
// from the per-source SQLite DBs alone; no filesystem is consulted.
//
// Post-#1036 the legacy monolithic `search.db` is no longer built, so
// the previous single-`Search.Index`-over-`search.db` wrapper always
// resolved nil in production. This concrete opens each per-source docs
// DB (apple-documentation.db / hig.db / swift-org.db / swift-book.db /
// swift-evolution.db / apple-archive.db) and routes by URI scheme.
//
// MCPSupport stays free of `import SearchAPI`; only this CLI
// composition-root concrete reaches the per-source databases.
struct LiveMarkdownLookupStrategy: MCP.Support.MarkdownLookupStrategy {
    /// Docs-tier source providers (apple-docs / hig / swift-org /
    /// swift-book / swift-evolution / apple-archive). Drives both the
    /// read dispatch (`ReadService`) and the list enumeration (one DB
    /// open per provider, keyed by `resourceListMode`).
    let providers: [any Search.SourceProvider]
    /// Per-source docs DB URLs keyed by `SourceProvider.definition.id`.
    let dbURLs: [String: URL]
    let samplesDBURL: URL
    let packagesDBURL: URL
    let searchDatabaseFactory: any Search.DatabaseFactory
    let sampleDatabaseFactory: any Sample.Index.DatabaseFactory
    let packageFileLookup: any Search.PackageFileLookupStrategy
    let logger: any LoggingModels.Logging.Recording

    // MARK: - read

    func lookup(uri: String) async throws -> String? {
        do {
            let result = try await Services.ReadService.read(
                identifier: uri,
                explicit: nil,
                format: .markdown,
                dbURL: docsFallbackDB,
                samplesDB: samplesDBURL,
                packagesDB: packagesDBURL,
                searchDatabaseFactory: searchDatabaseFactory,
                sampleDatabaseFactory: sampleDatabaseFactory,
                packageFileLookup: packageFileLookup,
                dbURLs: dbURLs,
                explicitDocsSourceID: nil,
                providers: providers
            )
            return result.content
        } catch is Services.ReadService.ReadError {
            // Any not-found / not-found-anywhere maps to "URI absent from
            // the DBs"; the provider turns nil into `notFound(uri)`.
            return nil
        }
    }

    /// Fallback DB URL for `ReadService` when a URI's scheme isn't in
    /// `dbURLs`. Prefer apple-docs' DB (the largest docs corpus);
    /// fall back to any docs DB if apple-docs isn't wired.
    private var docsFallbackDB: URL {
        dbURLs[Shared.Constants.SourcePrefix.appleDocs]
            ?? dbURLs.values.first
            ?? packagesDBURL
    }

    // MARK: - list

    func listResources() async throws -> [Search.URIResource] {
        var entries: [Search.URIResource] = []
        for provider in providers {
            let mode = provider.resourceListMode
            if mode == .none { continue }
            guard let dbURL = dbURLs[provider.definition.id] else { continue }
            guard FileManager.default.fileExists(atPath: dbURL.path) else {
                logger.warning(
                    "LiveMarkdownLookupStrategy: \(provider.definition.id) DB absent at "
                        + "\(dbURL.path); skipping its resources/list slice",
                    category: .mcp
                )
                continue
            }
            do {
                let database = try await searchDatabaseFactory.openDatabase(at: dbURL)
                let slice = try await database.listResourceEntries(mode: mode)
                await database.disconnect()
                entries.append(contentsOf: slice)
            } catch {
                // Per-source enumeration errors are non-fatal: log + skip
                // this slice so the other sources' entries still list.
                logger.warning(
                    "LiveMarkdownLookupStrategy: \(provider.definition.id) resources/list "
                        + "enumeration failed: \(error)",
                    category: .mcp
                )
            }
        }
        return entries
    }
}

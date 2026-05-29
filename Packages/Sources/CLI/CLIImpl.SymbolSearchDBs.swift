import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

// MARK: - Multi-DB symbol search resolution (#1154 / #1155)

extension CLIImpl {
    /// Resolve the per-source DBs the AST search commands should query.
    ///
    /// Pre-#1154 the 5 AST commands (`search-symbols` et al.) opened only
    /// `apple-documentation.db` via `resolveAppleDocsDBURL`, so symbols
    /// indexed into any other per-source DB were invisible. Post per-source
    /// split, `doc_symbols` is populated by every docs-tier indexer that
    /// runs `ASTIndexer.Extractor`, so the rows live across several DBs.
    ///
    /// The participating set is derived from the production source registry:
    /// a source participates when its `Search.Capabilities.searchers`
    /// advertises `searcher`. The DBs are siblings in `baseDir` (the same
    /// folder `save` / `setup` operate on). `source`, when supplied, scopes
    /// the search to a single source id. Non-existent DB files are skipped
    /// so a partial install still answers from what is present.
    static func resolveSymbolSearchDBURLs(
        searcher: Search.Capabilities.Searcher,
        source: String?,
        baseDir: String?
    ) throws -> [URL] {
        let baseDirectory = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Paths.live().baseDirectory
        let registry = makeProductionSourceRegistry()
        var providers = registry.allEnabled.filter { $0.capabilities.searchers.contains(searcher) }
        if let source {
            let wanted = source.lowercased()
            let matched = providers.filter { $0.definition.id.lowercased() == wanted }
            guard !matched.isEmpty else {
                throw SymbolSearchDBError.unknownOrUnsupportedSource(
                    requested: source,
                    searcher: searcher,
                    supported: providers.map(\.definition.id).sorted()
                )
            }
            providers = matched
        }
        return providers
            .map { baseDirectory.appendingPathComponent($0.destinationDB.filename) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Open each resolved per-source DB, run `query` against it, and merge
    /// the results capped to `limit`. Each DB is opened read-only and
    /// disconnected before the next. Per-DB results arrive already ranked +
    /// capped by the underlying query; the merged list keeps registry order
    /// then per-DB rank and takes the first `limit`.
    static func fanOutSymbolSearch(
        dbURLs: [URL],
        logger: any LoggingModels.Logging.Recording,
        limit: Int,
        query: (SearchModule.Index) async throws -> [Search.SymbolSearchResult]
    ) async throws -> [Search.SymbolSearchResult] {
        var merged: [Search.SymbolSearchResult] = []
        for url in dbURLs {
            let index = try await SearchModule.Index(
                dbPath: url,
                logger: logger,
                indexers: [:],
                sourceLookup: .empty
            )
            merged += try await query(index)
            await index.disconnect()
        }
        return Array(merged.prefix(limit))
    }

    enum SymbolSearchDBError: Error, CustomStringConvertible {
        case unknownOrUnsupportedSource(requested: String, searcher: Search.Capabilities.Searcher, supported: [String])

        var description: String {
            switch self {
            case let .unknownOrUnsupportedSource(requested, searcher, supported):
                let list = supported.isEmpty ? "(none)" : supported.joined(separator: ", ")
                return "Unknown or unsupported --source '\(requested)' for \(searcher.rawValue) search. "
                    + "Sources that support it: \(list)."
            }
        }
    }
}

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

    /// Open each resolved per-source DB, run `query` against it, and merge the
    /// per-DB result lists capped to `limit`.
    ///
    /// `SymbolSearchResult` carries no cross-DB score, so a naive
    /// concat-then-`prefix(limit)` would let the first (largest) DB fill the
    /// cap and bury every later DB's matches. Instead the per-DB lists are
    /// **round-robin interleaved** (each DB's rank-0 row, then each DB's rank-1
    /// row, ...) so every DB contributes to the top `limit` and a swift-book /
    /// swift-org match still surfaces alongside apple-docs.
    ///
    /// Resilience: each DB is opened read-only and always disconnected, even
    /// when its query throws; a DB that fails to open or query is logged and
    /// skipped (matching the partial-install tolerance of
    /// `resolveSymbolSearchDBURLs`) so one bad DB cannot nuke results from the
    /// healthy ones.
    static func fanOutSymbolSearch(
        dbURLs: [URL],
        logger: any LoggingModels.Logging.Recording,
        limit: Int,
        query: (SearchModule.Index) async throws -> [Search.SymbolSearchResult]
    ) async -> [Search.SymbolSearchResult] {
        var perDB: [[Search.SymbolSearchResult]] = []
        for url in dbURLs {
            let index: SearchModule.Index
            do {
                index = try await SearchModule.Index(
                    dbPath: url,
                    logger: logger,
                    indexers: [:],
                    sourceLookup: .empty
                )
            } catch {
                logger.info("⚠️  Skipping \(url.lastPathComponent) (could not open): \(error)")
                continue
            }
            do {
                try await perDB.append(query(index))
            } catch {
                logger.info("⚠️  Skipping \(url.lastPathComponent) (query failed): \(error)")
            }
            await index.disconnect()
        }

        // Round-robin interleave so every DB contributes to the top `limit`.
        var merged: [Search.SymbolSearchResult] = []
        var rank = 0
        outer: while merged.count < limit {
            var advanced = false
            for results in perDB where rank < results.count {
                merged.append(results[rank])
                advanced = true
                if merged.count == limit { break outer }
            }
            if !advanced { break }
            rank += 1
        }
        return merged
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

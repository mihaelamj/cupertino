import Foundation
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants

// MARK: - Unified Search Service

/// Service for searching across all documentation sources.
/// Consolidates search logic previously duplicated between CLI and MCP.
extension Services {
    public actor UnifiedSearchService {
        private let searchIndex: (any Search.Database)?
        private let sampleDatabase: (any Sample.Index.Reader)?

        /// Initialize with existing database connections. The concrete
        /// `Search.Index?` form continues to compile because `Search.Index`
        /// conforms to `Search.Database`; same for `Sample.Index.Database`
        /// conforming to `Sample.Index.Reader`.
        public init(searchIndex: (any Search.Database)?, sampleDatabase: (any Sample.Index.Reader)?) {
            self.searchIndex = searchIndex
            self.sampleDatabase = sampleDatabase
        }

        // MARK: - Unified Search

        /// Search all 8 sources and return combined results.
        ///
        /// #640 — per-source errors are classified as either
        /// `degradationReason` (configuration: schema mismatch / DB
        /// unopenable) or silently swallowed (transient: network blip,
        /// lock contention, plain "no results"). Configuration errors
        /// bubble into `Input.degradedSources` so the formatter can
        /// prepend a `⚠ Schema mismatch` warning at the top of MCP
        /// response bodies. AI agents reading the response can then
        /// distinguish "no apple-docs match for the query" (return
        /// empty + no warning) from "apple-docs.db is unopenable"
        /// (return empty + warning).
        // swiftlint:disable:next function_body_length
        public func searchAll(
            query: String,
            framework: String?,
            limit: Int,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil,
            minSwift: String? = nil
        ) async -> Services.Formatter.Unified.Input {
            async let docs = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: framework,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            async let archive = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.appleArchive,
                framework: framework,
                limit: limit,
                includeArchive: true,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            // #732: samples now apply the 5-field platform filter in
            // the fan-out path too. `Sample.Index.Database.searchProjects`
            // grew the args natively; this fan-out call threads them
            // through. Multiple `min_*` values AND-combine — a sample
            // must satisfy every requested minimum.
            async let sampleResults = searchSamples(
                query: query,
                framework: framework,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS
            )

            async let hig = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.hig,
                framework: nil,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            async let swiftEvolution = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftEvolution,
                framework: nil,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            async let swiftOrg = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftOrg,
                framework: nil,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            async let swiftBook = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.swiftBook,
                framework: nil,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            async let packages = searchSource(
                query: query,
                source: Shared.Constants.SourcePrefix.packages,
                framework: nil,
                limit: limit,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )

            let outcomes = await [docs, archive, hig, swiftEvolution, swiftOrg, swiftBook, packages]
            // Same `searchIndex` actor underlies every source above — a
            // schema mismatch will surface on each one in turn — so the
            // degradation set is typically all-or-none for apple-docs-
            // style sources. We still preserve the per-source label so
            // the warning lists exactly what failed.
            let degraded: [Search.DegradedSource] = outcomes.compactMap { outcome in
                guard let reason = outcome.degradationReason else { return nil }
                return Search.DegradedSource(name: outcome.sourceName, reason: reason)
            }

            return await Services.Formatter.Unified.Input(
                docResults: docs.results,
                archiveResults: archive.results,
                sampleResults: sampleResults,
                higResults: hig.results,
                swiftEvolutionResults: swiftEvolution.results,
                swiftOrgResults: swiftOrg.results,
                swiftBookResults: swiftBook.results,
                packagesResults: packages.results,
                limit: limit,
                degradedSources: degraded
            )
        }

        // MARK: - Individual Source Search

        /// Per-source search outcome (#640). Carries results plus an
        /// optional `degradationReason` set when the source threw a
        /// configuration error (schema mismatch / DB unopenable). The
        /// `sourceName` echoes the prefix back so the caller can label
        /// the degradation entry without re-passing the source string.
        struct SourceOutcome {
            let sourceName: String
            let results: [Search.Result]
            let degradationReason: String?
        }

        /// Search a specific documentation source
        ///
        /// #226 expansion: threads the 5 `min_*` platform filters +
        /// `minSwift` into `Search.Database.search`. Each platform arg
        /// flows independently through the IS-NOT-NULL gate in the
        /// index's WHERE clause, so a source whose data carries
        /// `min_<platform>` populated (apple-docs, apple-archive,
        /// packages) ends up filtered; article sources (hig, swift-
        /// evolution, swift-org, swift-book) typically have NULL columns
        /// and end up returning zero rows when the filter is set — which
        /// is the structurally correct behaviour (the filter is "applied"
        /// in the sense that no row passing the WHERE clause comes out).
        private func searchSource(
            query: String,
            source: String,
            framework: String?,
            limit: Int,
            includeArchive: Bool = false,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil,
            minSwift: String? = nil
        ) async -> SourceOutcome {
            guard let searchIndex else {
                return SourceOutcome(sourceName: source, results: [], degradationReason: nil)
            }

            do {
                let results = try await searchIndex.search(
                    query: query,
                    source: source,
                    framework: framework,
                    language: nil,
                    limit: limit,
                    includeArchive: includeArchive,
                    minIOS: minIOS,
                    minMacOS: minMacOS,
                    minTvOS: minTvOS,
                    minWatchOS: minWatchOS,
                    minVisionOS: minVisionOS,
                    minSwift: minSwift
                )
                return SourceOutcome(sourceName: source, results: results, degradationReason: nil)
            } catch {
                return SourceOutcome(
                    sourceName: source,
                    results: [],
                    degradationReason: Self.classifyDegradation(error)
                )
            }
        }

        /// Mirror of `Search.SmartQuery.classifyDegradation`. Distinguishes
        /// schema-mismatch / DB-unopenable errors (configuration; needs user
        /// action) from transient errors (network, lock, etc.).
        static func classifyDegradation(_ error: any Swift.Error) -> String? {
            let message = "\(error)".lowercased()
            if message.contains("schema version") {
                return "schema mismatch — run `cupertino setup` to redownload a matching bundle"
            }
            if message.contains("unable to open database") || message.contains("file is not a database") {
                return "database unopenable — check the `--search-db` path"
            }
            return nil
        }

        /// Search sample code projects.
        ///
        /// #732: threads the 5-field platform filter through to
        /// `Sample.Index.Database.searchProjects`. Multiple `min<Platform>`
        /// values AND-combine inside the SQL.
        private func searchSamples(
            query: String,
            framework: String?,
            limit: Int,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) async -> [Sample.Index.Project] {
            guard let sampleDatabase else { return [] }

            do {
                return try await sampleDatabase.searchProjects(
                    query: query,
                    framework: framework,
                    limit: limit,
                    minIOS: minIOS,
                    minMacOS: minMacOS,
                    minTvOS: minTvOS,
                    minWatchOS: minWatchOS,
                    minVisionOS: minVisionOS
                )
            } catch {
                return []
            }
        }

        // MARK: - Lifecycle

        /// Disconnect database connections
        public func disconnect() async {
            // Note: In actor-based design, we don't explicitly close
            // connections - they are cleaned up when the actor is deallocated
        }
    }
}

// The `withUnifiedSearchService` factory lives in
// `Services.ServiceContainer.swift` alongside the other `with*Service`
// factories — that file keeps `import Search` for the Search.Index
// instantiation; this file no longer needs it.

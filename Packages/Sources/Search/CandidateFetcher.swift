import Foundation
import SearchModels
import SharedConstants
// MARK: - Smart-query abstraction (#192 section E)

//
// A `CandidateFetcher` turns a natural-language question into a ranked list
// of `SmartCandidate` results pulled from one data source (packages.db, the
// apple-docs half of search.db, swift-evolution, swift-org, etc.).
// `Search.SmartQuery` fans several fetchers out in parallel and cross-ranks
// their candidates via reciprocal rank fusion so the final ordering is
// source-agnostic.
//
// The protocol is intentionally narrow: each fetcher knows how to query its
// own store, produce a chunk, and return a raw score. Score normalization is
// the ranker's job, not the fetcher's — this keeps implementations trivial
// to add for new sources (WWDC transcripts #58, Swift Forums #89, etc.).

// MARK: - Package FTS fetcher (wraps Search.PackageQuery)

extension Search {
    /// Adapter from `Search.PackageQuery.answer(_:maxResults:)` to the
    /// `CandidateFetcher` contract. Delegates the heavy lifting (intent
    /// classification, column-weighted BM25, chunk extraction) to the
    /// existing actor.
    public struct PackageFTSCandidateFetcher: CandidateFetcher {
        public let sourceName = Shared.Constants.SourcePrefix.packages

        private let dbPath: URL
        private let availability: Search.AvailabilityFilter?

        public init(
            dbPath: URL,
            availability: Search.AvailabilityFilter? = nil
        ) {
            self.dbPath = dbPath
            self.availability = availability
        }

        public func fetch(question: String, limit: Int) async throws -> [SmartCandidate] {
            let query = try await Search.PackageQuery(dbPath: dbPath)
            defer { Task { await query.disconnect() } }

            let results = try await query.answer(
                question,
                maxResults: limit,
                availability: availability
            )
            return results.map { row in
                SmartCandidate(
                    source: sourceName,
                    identifier: "\(row.owner)/\(row.repo)/\(row.relpath)",
                    title: row.title,
                    chunk: row.chunk,
                    rawScore: row.score,
                    kind: row.kind,
                    metadata: [
                        "owner": row.owner,
                        "repo": row.repo,
                        "relpath": row.relpath,
                        "module": row.module ?? "",
                    ]
                )
            }
        }
    }
}

// MARK: - Docs source fetcher (wraps Search.Index.search for any apple-docs-style source)

extension Search {
    /// Adapter from `Search.Index.search` to the `CandidateFetcher` contract,
    /// scoped to a single source (apple-docs, apple-archive, swift-evolution,
    /// swift-org, swift-book, hig, packages).
    ///
    /// Uses the `summary` field as the chunk — it's already a 500-char-ish
    /// first-sentence extract populated by `indexDocument.extractSummary`.
    public struct DocsSourceCandidateFetcher: CandidateFetcher {
        public let sourceName: String

        private let searchIndex: Search.Index
        private let includeArchive: Bool
        private let availability: Search.AvailabilityFilter?

        /// Sources whose content uses a different availability axis from
        /// iOS / macOS / etc. — Swift language version (#225). When the
        /// fetcher is constructed for one of these, the availability
        /// filter is silently dropped at fetch time so a query like
        /// `--platform iOS --min-version 16` doesn't accidentally
        /// nuke the entire swift-evolution result set.
        private static let swiftVersionSources: Set<String> = [
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ]

        /// - Parameters:
        ///   - searchIndex: shared Search.Index instance (fetchers inherit
        ///     connection lifecycle; callers manage `disconnect()`).
        ///   - source: the `Shared.Constants.SourcePrefix.*` value to scope to.
        ///   - includeArchive: pass `true` when `source` is `apple-archive`.
        ///     Default `false` matches `search()`'s archive-exclusion behaviour.
        ///   - availability: optional `--platform` / `--min-version` filter
        ///     (#233). Honoured for apple-docs / apple-archive / hig — the
        ///     sources whose pages actually carry `min_*` columns.
        ///     Silently dropped for swift-evolution / swift-org / swift-book
        ///     because those use the Swift-language-version axis (see #225).
        public init(
            searchIndex: Search.Index,
            source: String,
            includeArchive: Bool = false,
            availability: Search.AvailabilityFilter? = nil
        ) {
            self.searchIndex = searchIndex
            sourceName = source
            self.includeArchive = includeArchive
            self.availability = availability
        }

        public func fetch(question: String, limit: Int) async throws -> [SmartCandidate] {
            // Apply availability params only for OS-versioned sources.
            let effective = Self.swiftVersionSources.contains(sourceName)
                ? nil
                : availability
            let rows = try await searchIndex.search(
                query: question,
                source: sourceName,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: includeArchive,
                minIOS: effective?.platform.lowercased() == "ios" ? effective?.minVersion : nil,
                minMacOS: ["macos", "osx", "mac"].contains(effective?.platform.lowercased() ?? "") ? effective?.minVersion : nil,
                minTvOS: effective?.platform.lowercased() == "tvos" ? effective?.minVersion : nil,
                minWatchOS: effective?.platform.lowercased() == "watchos" ? effective?.minVersion : nil,
                minVisionOS: effective?.platform.lowercased() == "visionos" ? effective?.minVersion : nil
            )

            return rows.map { row in
                // `Search.Result.rank` is negative BM25 (lower = better).
                // Invert so higher is better, consistent with PackageQuery.
                let score = -row.rank
                return SmartCandidate(
                    source: sourceName,
                    identifier: row.uri,
                    title: row.title,
                    chunk: row.summary,
                    rawScore: score,
                    kind: nil,
                    metadata: [
                        "framework": row.framework,
                        "filePath": row.filePath,
                    ]
                )
            }
        }
    }
}

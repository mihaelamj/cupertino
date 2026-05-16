import Foundation
import SearchModels
import SharedConstants

// MARK: - Smart cross-source query (#192 section E)

//
// Fans a natural-language question across every configured `CandidateFetcher`
// in parallel, then merges the per-source rankings into a single top-N list
// via reciprocal rank fusion (RRF).
//
// Why RRF: fetchers produce scores on incompatible scales (inverted BM25
// from packages.db, adjusted BM25 from search.db, etc.). Ranking each
// fetcher locally, then fusing on 1/(k + rank), gives a robust combined
// order without per-source coefficient tuning. k=60 is the widely-used
// default from the Cormack / Clarke / Büttcher paper.
//
// Intent routing (#254): RRF treats every source equally, which buries
// canonical apple-docs hits for symbol-name queries (e.g. `Task`,
// `URLSession`) under prose-heavy sources whose rank-1 result fuses to
// the same 1/(k+1) score. For queries that look like a Swift identifier
// we prune the fetcher set to the sources where a symbol is the canonical
// answer (apple-docs, swift-evolution, packages) before fan-out. Prose
// queries keep the full all-source path.

extension Search {
    /// Cross-source smart query. Runs every configured `CandidateFetcher`
    /// concurrently, then fuses their ranked outputs.
    public struct SmartQuery: Sendable {
        /// Rank fusion constant. 60 is the Cormack et al. default and is not
        /// especially sensitive — anything in [10, 100] produces similar
        /// orderings. Exposed for experimentation / tests.
        public static let defaultRRFK: Double = 60

        /// Sources where a symbol-name query has a canonical answer. Used
        /// by intent routing (#254) to prune the fetcher set when the
        /// question looks like a Swift identifier.
        public static let symbolPreferredSources: Set<String> = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.packages,
        ]

        /// Per-source weights for reciprocal rank fusion (#254 Option B).
        ///
        /// Plain RRF gives every source's rank-1 the same fused score
        /// (1/(k+1) ≈ 0.0164 with k=60), so when two sources both have a
        /// rank-1 hit they tie and the dictionary-order tiebreak picks
        /// arbitrarily. For Apple platform queries the user almost always
        /// wants the canonical apple-docs answer at #1; weighting the
        /// fused increment by source authority breaks the tie cleanly:
        ///
        /// - apple-docs gets 3.0: rank-1 contributes 3.0/61 ≈ 0.0492.
        /// - swift-evolution / packages get 1.5: rank-1 ≈ 0.0246.
        /// - apple-archive / hig get 0.5: rank-1 ≈ 0.0082 (kept available
        ///   for prose fan-out but cannot displace a canonical Apple hit).
        ///
        /// Weights are applied to the increment, not the rank; the math is
        /// still RRF, just authority-weighted.
        public static let sourceWeights: [String: Double] = [
            Shared.Constants.SourcePrefix.appleDocs: 3.0,
            Shared.Constants.SourcePrefix.swiftEvolution: 1.5,
            Shared.Constants.SourcePrefix.packages: 1.5,
            Shared.Constants.SourcePrefix.swiftBook: 1.0,
            Shared.Constants.SourcePrefix.swiftOrg: 1.0,
            Shared.Constants.SourcePrefix.samples: 1.0,
            Shared.Constants.SourcePrefix.appleSampleCode: 1.0,
            Shared.Constants.SourcePrefix.appleArchive: 0.5,
            Shared.Constants.SourcePrefix.hig: 0.5,
        ]

        private let fetchers: [any CandidateFetcher]
        private let rrfK: Double

        public init(fetchers: [any CandidateFetcher], rrfK: Double = Self.defaultRRFK) {
            self.fetchers = fetchers
            self.rrfK = rrfK
        }

        /// Returns true when `query` looks like a single Swift identifier:
        /// one whitespace-free token, ASCII letters / digits / underscore,
        /// starting with an uppercase letter, length >= 2.
        ///
        /// Designed to fire on canonical type-name lookups (`Task`, `View`,
        /// `URLSession`, `Result`) and stay quiet on prose questions
        /// ("how do I cancel an async operation"). Lowercase single tokens
        /// like `view` are intentionally excluded — they are ambiguous
        /// between symbol and prose intent and prose fan-out is the safer
        /// default.
        public static func isLikelySymbolQuery(_ query: String) -> Bool {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return false }
            guard let first = trimmed.unicodeScalars.first,
                  CharacterSet.uppercaseLetters.contains(first) else { return false }
            let allowed = CharacterSet(
                charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
            )
            return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        }

        /// Apply intent routing to a fetcher list. Symbol-name questions
        /// keep only the sources where a symbol is the canonical answer
        /// (apple-docs / swift-evolution / packages); prose questions
        /// pass through untouched. Falls back to the original list when
        /// pruning would empty it, so callers that scope to a single
        /// non-allowlisted source (e.g. `--source apple-archive`) still
        /// get results.
        static func routeFetchers(
            _ fetchers: [any CandidateFetcher],
            for question: String
        ) -> [any CandidateFetcher] {
            guard isLikelySymbolQuery(question) else { return fetchers }
            let filtered = fetchers.filter {
                symbolPreferredSources.contains($0.sourceName)
            }
            return filtered.isEmpty ? fetchers : filtered
        }

        /// Run `question` against every fetcher and return the top-N fused
        /// results. `perFetcherLimit` caps each fetcher's contribution before
        /// fusion (so a source with tons of marginal matches can't crowd out
        /// a strong single hit from another).
        ///
        /// Fetchers that throw are silently skipped — a dead DB or network
        /// error on one source must not take down the rest of the query. The
        /// returned `sources` array lists which fetchers actually contributed.
        // swiftlint:disable:next function_body_length
        public func answer(
            question: String,
            limit: Int = 10,
            perFetcherLimit: Int = 20
        ) async -> SmartResult {
            // Snapshot into locals so the closures don't capture `self` (which
            // would also require unnecessary marker imports).
            let rrfK = rrfK
            let perFetcherLimit = perFetcherLimit
            let question = question
            let fetchers = Self.routeFetchers(fetchers, for: question)

            // Fan out: one task per fetcher. Failures collapse to empty
            // lists so one dead source can't take down the whole query.
            // #640 — but we distinguish CONFIGURATION errors (schema
            // mismatch / DB unopenable) from transient FETCH errors
            // (network blip, lock contention). Configuration errors get
            // promoted into the result's `degradedSources` so AI agents
            // reading the MCP response can see "apple-docs returned 0"
            // and know it's a setup problem, not "we have no apple-docs
            // content for your query". Pre-fix the silent collapse made
            // both states indistinguishable in the response body.
            struct Contribution: Sendable {
                let name: String
                let candidates: [SmartCandidate]
                let degradationReason: String?
            }
            let contributions: [Contribution] = await withTaskGroup(of: Contribution.self) { group in
                for fetcher in fetchers {
                    group.addTask {
                        do {
                            let batch = try await fetcher.fetch(
                                question: question,
                                limit: perFetcherLimit
                            )
                            return Contribution(
                                name: fetcher.sourceName,
                                candidates: batch,
                                degradationReason: nil
                            )
                        } catch {
                            return Contribution(
                                name: fetcher.sourceName,
                                candidates: [],
                                degradationReason: Self.classifyDegradation(error)
                            )
                        }
                    }
                }
                var collected: [Contribution] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            // Reciprocal rank fusion (authority-weighted, #254 Option B).
            // Candidates are keyed by identifier + source because cross-source
            // duplicates are vanishingly rare and we want to preserve both
            // variants if they somehow appear. The fused increment scales by
            // `sourceWeights[candidate.source]` so apple-docs' rank-1 hit
            // beats lower-authority rank-1 hits on the cross-source tiebreak.
            var fused: [String: (candidate: SmartCandidate, score: Double)] = [:]
            for contribution in contributions {
                let batch = contribution.candidates
                for (rank, candidate) in batch.enumerated() {
                    let key = "\(candidate.source)\u{1F}\(candidate.identifier)"
                    let weight = Self.sourceWeights[candidate.source] ?? 1.0
                    let increment = weight / (rrfK + Double(rank + 1))
                    if let existing = fused[key] {
                        fused[key] = (existing.candidate, existing.score + increment)
                    } else {
                        fused[key] = (candidate, increment)
                    }
                }
            }

            let ranked = fused.values
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map { FusedCandidate(candidate: $0.candidate, score: $0.score) }

            let activeSources = contributions
                .filter { !$0.candidates.isEmpty }
                .map(\.name)
            // #640 — configuration-error sources (schema mismatch /
            // DB unopenable) bubble into a separate channel so the
            // SmartReport formatter can prepend a `⚠ Schema mismatch`
            // warning instead of letting the empty result read like
            // "no content on this source for the query".
            let degradedSources = contributions
                .compactMap { contribution -> DegradedSource? in
                    guard let reason = contribution.degradationReason else { return nil }
                    return DegradedSource(name: contribution.name, reason: reason)
                }

            return SmartResult(
                question: question,
                candidates: Array(ranked),
                contributingSources: activeSources,
                degradedSources: degradedSources
            )
        }

        // MARK: - Degradation classification

        /// Distinguish configuration errors (schema mismatch, missing /
        /// unopenable DB) from transient fetch errors. Returns a
        /// human-readable reason string when the error is the kind of
        /// thing the user has to act on — schema mismatch, "database
        /// is locked" exceeding the timeout, file-not-found — vs `nil`
        /// for plain "no results" or other transient throws that the
        /// caller can safely swallow per the original skip-on-error
        /// policy.
        ///
        /// The match is on the message text rather than the type
        /// because `Search.Error.sqliteError` is the same Swift type
        /// regardless of cause; the message is what tells us what
        /// happened. We err on the side of reporting too few rather
        /// than too many to keep the warning signal strong.
        /// #648 (CLI JSON path) — bumped to `public` so the CLI (not a
        /// `@testable` consumer of Search) can call it from
        /// `openDocsFetchers` to convert a search.db open-failure into
        /// the same string a per-fetcher classifier would have produced,
        /// then synthesise `Search.DegradedSource` entries for the
        /// open-time path. Same internal callers + tests; the surface
        /// is pure.
        public static func classifyDegradation(_ error: any Swift.Error) -> String? {
            let message = "\(error)".lowercased()
            if message.contains("schema version") {
                return "schema mismatch; run `cupertino setup` to redownload a matching bundle"
            }
            if message.contains("unable to open database") || message.contains("file is not a database") {
                return "database unopenable; check the `--search-db` / `--packages-db` / `--sample-db` paths"
            }
            return nil
        }
    }

    /// A `SmartCandidate` plus its fused score after cross-source ranking.
    public struct FusedCandidate: Sendable, Hashable {
        public let candidate: SmartCandidate
        public let score: Double

        public init(candidate: SmartCandidate, score: Double) {
            self.candidate = candidate
            self.score = score
        }
    }

    /// Result of a `SmartQuery.answer` call.
    public struct SmartResult: Sendable {
        /// Echoes the input so consumers can log the pair.
        public let question: String
        /// Top-N fused candidates, best-first.
        public let candidates: [FusedCandidate]
        /// Source names that produced at least one candidate this run. Useful
        /// for telling the user "searched: apple-docs, packages, swift-org".
        public let contributingSources: [String]
        /// Sources that returned empty due to a configuration error (schema
        /// mismatch / DB unopenable) rather than legitimate "no content"
        /// for the query (#640). Empty when every fetcher either
        /// contributed or threw a transient error. Pre-#640 the fan-out
        /// silently collapsed configuration errors into empty results,
        /// leaving AI agents unable to distinguish "no apple-docs match
        /// for `URLSession`" from "apple-docs.db is unopenable".
        public let degradedSources: [DegradedSource]

        public init(
            question: String,
            candidates: [FusedCandidate],
            contributingSources: [String],
            degradedSources: [DegradedSource] = []
        ) {
            self.question = question
            self.candidates = candidates
            self.contributingSources = contributingSources
            self.degradedSources = degradedSources
        }
    }

    // `Search.DegradedSource` lives in the `SearchModels` target (#640)
    // so consumers like `Services.Formatter.Unified.Input` can reference
    // it without pulling the concrete `Search` target into their import
    // graph.
}

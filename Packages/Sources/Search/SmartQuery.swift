import Foundation

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

extension Search {
    /// Cross-source smart query. Runs every configured `CandidateFetcher`
    /// concurrently, then fuses their ranked outputs.
    public struct SmartQuery: Sendable {
        /// Rank fusion constant. 60 is the Cormack et al. default and is not
        /// especially sensitive — anything in [10, 100] produces similar
        /// orderings. Exposed for experimentation / tests.
        public static let defaultRRFK: Double = 60

        private let fetchers: [any CandidateFetcher]
        private let rrfK: Double

        public init(fetchers: [any CandidateFetcher], rrfK: Double = Self.defaultRRFK) {
            self.fetchers = fetchers
            self.rrfK = rrfK
        }

        /// Run `question` against every fetcher and return the top-N fused
        /// results. `perFetcherLimit` caps each fetcher's contribution before
        /// fusion (so a source with tons of marginal matches can't crowd out
        /// a strong single hit from another).
        ///
        /// Fetchers that throw are silently skipped — a dead DB or network
        /// error on one source must not take down the rest of the query. The
        /// returned `sources` array lists which fetchers actually contributed.
        public func answer(
            question: String,
            limit: Int = 10,
            perFetcherLimit: Int = 20
        ) async -> SmartResult {
            // Snapshot into locals so the closures don't capture `self` (which
            // would also require unnecessary marker imports).
            let fetchers = fetchers
            let rrfK = rrfK
            let perFetcherLimit = perFetcherLimit
            let question = question

            // Fan out: one task per fetcher. Failures collapse to empty lists.
            let contributions: [(name: String, candidates: [SmartCandidate])] = await withTaskGroup(
                of: (String, [SmartCandidate]).self
            ) { group in
                for fetcher in fetchers {
                    group.addTask {
                        do {
                            let batch = try await fetcher.fetch(
                                question: question,
                                limit: perFetcherLimit
                            )
                            return (fetcher.sourceName, batch)
                        } catch {
                            return (fetcher.sourceName, [])
                        }
                    }
                }
                var collected: [(String, [SmartCandidate])] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            // Reciprocal rank fusion. Candidates are keyed by identifier + source
            // because cross-source duplicates are vanishingly rare and we want
            // to preserve both variants if they somehow appear.
            var fused: [String: (candidate: SmartCandidate, score: Double)] = [:]
            for (_, batch) in contributions {
                for (rank, candidate) in batch.enumerated() {
                    let key = "\(candidate.source)\u{1F}\(candidate.identifier)"
                    let increment = 1.0 / (rrfK + Double(rank + 1))
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

            return SmartResult(
                question: question,
                candidates: Array(ranked),
                contributingSources: activeSources
            )
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

        public init(
            question: String,
            candidates: [FusedCandidate],
            contributingSources: [String]
        ) {
            self.question = question
            self.candidates = candidates
            self.contributingSources = contributingSources
        }
    }
}

import Foundation

/// A single candidate surfaced by a `Search.CandidateFetcher`.
///
/// Lifted out of the Search target into SearchModels so consumers
/// (Services-side adapters that bridge the cupertino-internal stores
/// into the smart-query fan-out) can construct + return candidates
/// without taking a behavioural dependency on the Search target.
///
/// Scores are source-local and not comparable across fetchers —
/// `Search.SmartQuery` does the cross-source ranking via rank fusion
/// (#192 section E).
extension Search {
    public struct SmartCandidate: Sendable, Hashable {
        /// Source identifier, e.g. `"packages"`, `"apple-docs"`, `"swift-evolution"`.
        public let source: String
        /// Canonical identifier for the candidate. Format is source-dependent:
        /// `owner/repo/relpath` for packages, the URI for docs rows.
        public let identifier: String
        /// Display title — what a UI should surface as the heading.
        public let title: String
        /// Excerpt to show the user. Expected to be already chunked / truncated.
        public let chunk: String
        /// Source-local score. Higher is better, but scales differ between
        /// fetchers; only useful for within-source ordering.
        public let rawScore: Double
        /// Optional tag — DocKind raw value for docs, PackageFileKind raw value
        /// for packages. Nil for sources without a kind taxonomy.
        public let kind: String?
        /// Free-form attribution metadata (framework, owner/repo, language, etc.).
        public let metadata: [String: String]

        public init(
            source: String,
            identifier: String,
            title: String,
            chunk: String,
            rawScore: Double,
            kind: String? = nil,
            metadata: [String: String] = [:]
        ) {
            self.source = source
            self.identifier = identifier
            self.title = title
            self.chunk = chunk
            self.rawScore = rawScore
            self.kind = kind
            self.metadata = metadata
        }
    }
}

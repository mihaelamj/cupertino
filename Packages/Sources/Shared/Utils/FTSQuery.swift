import Foundation
import SharedConstants

extension Shared.Utils {
    /// Pure string helpers for building SQLite FTS5 MATCH queries from
    /// natural-language input. Lifted out of `Search.PackageQuery` (#192 E)
    /// in #238 so `SampleIndex` can reuse the exact same tokenization +
    /// OR-join behaviour without the previous AND-everything bug.
    public enum FTSQuery {
        /// Stopwords stripped from natural-language queries before
        /// building the FTS5 expression. Matches the set
        /// `Search.PackageQuery` originally shipped with — keeps both
        /// search paths behaviourally identical.
        public static let defaultStopwords: Set<String> = [
            "how", "to", "do", "i", "can", "you", "please", "show", "me", "give",
            "a", "an", "the", "is", "are", "of", "for", "in", "on", "with", "and",
            "or", "what", "where", "who", "why", "when", "does", "using", "use",
            "find", "example", "examples", "sample", "my", "some", "any",
        ]

        /// Tokenize a natural-language question into FTS5-friendly terms.
        /// Allowed characters: alphanumerics + `_` + `.` (so dotted
        /// identifiers like `swift-nio.EventLoop` survive). Drops
        /// 1-character tokens and `defaultStopwords`.
        public static func tokens(
            from question: String,
            stopwords: Set<String> = defaultStopwords
        ) -> [String] {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
            var current = ""
            var tokens: [String] = []
            for scalar in question.unicodeScalars {
                if allowed.contains(scalar) {
                    current.append(Character(scalar))
                } else if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { tokens.append(current) }
            return tokens
                .filter { $0.count >= 2 }
                .filter { !stopwords.contains($0.lowercased()) }
        }

        /// Build an FTS5 MATCH expression from a natural-language
        /// question: tokenize, drop stopwords, OR the remainder with
        /// each token wrapped in quotes (so punctuated identifiers
        /// don't trigger FTS5 operator parsing). Returns empty string
        /// when no usable tokens — caller treats that as "skip the
        /// search, return empty result set".
        ///
        /// Same shape as the FTS5 query Search.PackageQuery has been
        /// using since #192 E — uniform behaviour across the
        /// packages.db and samples.db search paths after #238.
        public static func build(question: String) -> String {
            let tokens = tokens(from: question)
            guard !tokens.isEmpty else { return "" }
            return tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
        }
    }
}

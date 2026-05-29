import Foundation

// MARK: - HIG platform-inference rules

//
// Single source of truth for the topic-aware platform inference
// applied across the HIG pipeline. Consumed by:
//
//   1. `Crawler.HIG.extractPlatforms(forURL:)` — writes the
//      `platforms: [...]` frontmatter + `> **Platforms:** ...` body
//      line in each crawled `.md` file.
//
//   2. `Search.Strategies.HIG` — supplies `overrideMin<Platform>` at
//      index time. Pre-#1078 the strategy stamped every HIG row with
//      the universal baseline (iOS 2.0, macOS 10.0, tvOS 9.0,
//      watchOS 2.0, visionOS 1.0); now it stamps only the platforms
//      the URL slug declares applicable, leaving the others NULL.
//
//   3. `Search.Index.applyHIGPlatformInference` (SearchSQLite SQL
//      pass) — backfills the same NULL state on rows that were
//      indexed pre-#1078. Idempotent on freshly-indexed data.
//
// Living in the foundation-only `SearchModels` seam (post-#536 PR 1.1,
// moved here from the `HIGPlatformInferencePass` producer) is what
// makes the "honest platform availability per HIG topic" promise work
// end-to-end (frontmatter + body + Availability schema all derived
// from one table; no place can drift independently) without a
// producer importing a peer producer just to read the rules.

public enum HIGPlatformRules {
    /// Canonical platform identifiers (lowercased — matching the
    /// `min_<platform>` column suffixes in `docs_metadata` schema).
    public static let allPlatforms: [String] = ["ios", "macos", "tvos", "watchos", "visionos"]

    /// Earliest supported version per platform. Apple's HIG doesn't
    /// version individual topics; these are platform-introduction
    /// baselines (iOS 2.0 = 2008, macOS 10.0 = 2001 Mac OS X, tvOS 9.0
    /// = 2015 Apple TV 4, watchOS 2.0 = 2015 native apps, visionOS 1.0
    /// = 2024 Vision Pro).
    public static let baseline: [String: String] = [
        "ios": "2.0",
        "macos": "10.0",
        "tvos": "9.0",
        "watchos": "2.0",
        "visionos": "1.0",
    ]

    public struct Rule: Sendable {
        public let urlSubstring: String
        public let keep: Set<String>

        public init(urlSubstring: String, keep: Set<String>) {
            self.urlSubstring = urlSubstring
            self.keep = keep
        }
    }

    /// Order matters when two rules' substrings overlap: the FIRST
    /// match wins. Patterns are intentionally narrow enough that
    /// today's HIG corpus has no overlap (verified by the test
    /// suite); the ordering rule is the contract for a future Apple
    /// URL slug that combines keywords.
    public static let rules: [Rule] = [
        Rule(urlSubstring: "designing-for-watchos", keep: ["watchos"]),
        Rule(urlSubstring: "watch-faces", keep: ["watchos"]),
        Rule(urlSubstring: "designing-for-tvos", keep: ["tvos"]),
        Rule(urlSubstring: "designing-for-visionos", keep: ["visionos"]),
        Rule(urlSubstring: "spatial-layout", keep: ["visionos"]),
        Rule(urlSubstring: "designing-for-macos", keep: ["macos"]),
        Rule(urlSubstring: "mac-catalyst", keep: ["ios", "macos"]),
        Rule(urlSubstring: "carplay", keep: ["ios"]),
        Rule(urlSubstring: "designing-for-ipados", keep: ["ios"]),
        Rule(urlSubstring: "designing-for-ios", keep: ["ios"]),
    ]

    /// Returns the set of platforms applicable to the given URI or
    /// URL. Matches against the input's lowercased form. Rows whose
    /// URI doesn't match any rule are treated as cross-platform (all
    /// five platforms applicable).
    public static func applicablePlatforms(for input: String) -> Set<String> {
        let lower = input.lowercased()
        for rule in rules where lower.contains(rule.urlSubstring) {
            return rule.keep
        }
        return Set(allPlatforms)
    }

    /// Returns the per-platform minimum-version tuple for the given
    /// URI. Non-applicable platforms get `nil` (consumers pass `nil`
    /// through to `Search.IndexWriter.indexStructuredDocument`'s
    /// `overrideMin<X>` parameters, or write them as NULL columns).
    public static func minimumVersions(for input: String) -> PlatformVersions {
        let keep = applicablePlatforms(for: input)
        return PlatformVersions(
            iOS: keep.contains("ios") ? baseline["ios"] : nil,
            macOS: keep.contains("macos") ? baseline["macos"] : nil,
            tvOS: keep.contains("tvos") ? baseline["tvos"] : nil,
            watchOS: keep.contains("watchos") ? baseline["watchos"] : nil,
            visionOS: keep.contains("visionos") ? baseline["visionos"] : nil
        )
    }

    public struct PlatformVersions: Sendable, Equatable {
        public let iOS: String?
        public let macOS: String?
        public let tvOS: String?
        public let watchOS: String?
        public let visionOS: String?

        public init(iOS: String?, macOS: String?, tvOS: String?, watchOS: String?, visionOS: String?) {
            self.iOS = iOS
            self.macOS = macOS
            self.tvOS = tvOS
            self.watchOS = watchOS
            self.visionOS = visionOS
        }
    }
}

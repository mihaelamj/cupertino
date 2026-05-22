import Foundation
import SharedConstants

// MARK: - Domain types lifted from `Search/Search.ComposableResult.swift`
// to `SearchModels` by the #898F follow-up to #898 sub-PR E. Carrying
// `Search.Source`, `Search.QueryIntent`, `detectQueryIntent(_:)`, and
// `Search.SourceProperties` here lets `SearchSQLite` reach them via the
// Models tier seam so the concrete target no longer needs
// `import Search`. The types themselves are byte-identical to their
// pre-lift definitions; behaviour is preserved.

// MARK: - Source Identity

/// Identifies which documentation source produced a result
// MARK: - Source (formerly an enum, now a String-wrapping struct)
//
// Open. The closed `enum Source: String, CaseIterable { case appleDocs;
// case samples; ... }` shape was the single biggest blocker to adding a
// new content source as a 2-file PR (the #919 epic goal): every new
// source required a new enum case, every `switch source` site became
// non-exhaustive, every `allCases` consumer required a recompile.
//
// Post-#251 second cut, `Search.Source` is a value type that wraps a
// raw `String` identifier. The 8 historical sources (`apple-docs`,
// `samples`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`,
// `swift-book`, `packages`) remain reachable as static constants
// (`Search.Source.appleDocs`, etc.) so every existing call site keeps
// compiling. New sources land by registering a `SourceDefinition` in
// `Search.SourceRegistry.all` plus a `SourcePrefix` constant in
// `Shared.Constants`; no edit to this file required.
//
// `displayName` and `emoji` were closed switches on the enum cases;
// they now look up the descriptor in `Search.SourceRegistry` and fall
// back to the raw identifier when no descriptor is registered. The
// fallback keeps existing call sites non-Optional without forcing every
// reader to handle nil for the 8 known sources; for new sources the
// human-facing fallback is "wwdc-transcripts" rather than a typed
// rename ceremony, and the descriptor's `displayName` takes over the
// moment the SourceRegistry row lands.
extension Search {
    public struct Source: Hashable, Sendable, Codable, RawRepresentable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        // MARK: - Codable (preserve bare-string wire format from the pre-#251 enum)

        // The pre-refactor `enum Source: String, Codable` encoded to a
        // bare JSON string ("apple-docs"). Swift's synthesised Codable
        // for a struct with a stored `rawValue: String` would encode to
        // a keyed container (`{"rawValue":"apple-docs"}`); RawRepresentable
        // does NOT auto-bridge to single-value Codable for structs (only
        // for raw-typed enums). The explicit init/encode below preserve
        // the historical bare-string wire format so MCP responses,
        // snapshot fixtures, dashboard payloads, and on-disk JSON
        // round-trip byte-identically pre/post #251.

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(String.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        // MARK: - Canonical constants for the 8 historical sources

        public static let appleDocs = Source(rawValue: Shared.Constants.SourcePrefix.appleDocs)
        public static let samples = Source(rawValue: Shared.Constants.SourcePrefix.samples)
        public static let hig = Source(rawValue: Shared.Constants.SourcePrefix.hig)
        public static let appleArchive = Source(rawValue: Shared.Constants.SourcePrefix.appleArchive)
        public static let swiftEvolution = Source(rawValue: Shared.Constants.SourcePrefix.swiftEvolution)
        public static let swiftOrg = Source(rawValue: Shared.Constants.SourcePrefix.swiftOrg)
        public static let swiftBook = Source(rawValue: Shared.Constants.SourcePrefix.swiftBook)
        public static let packages = Source(rawValue: Shared.Constants.SourcePrefix.packages)

        // MARK: - Descriptor-backed display surface

        /// Human-readable display name. Reads from the
        /// `Search.SourceRegistry` descriptor; falls back to `rawValue`
        /// when no descriptor is registered (e.g. a brand-new source
        /// whose SourceDefinition row hasn't landed yet).
        public var displayName: String {
            Search.SourceRegistry.definition(for: rawValue)?.displayName ?? rawValue
        }

        /// Emoji prefix for display. Reads from the
        /// `Search.SourceRegistry` descriptor; falls back to an empty
        /// string when no descriptor is registered.
        public var emoji: String {
            Search.SourceRegistry.definition(for: rawValue)?.emoji ?? ""
        }

        /// Whether this source has a `SourceDefinition` row in
        /// `Search.SourceRegistry.all`. Replaces the structural
        /// validation the closed enum's failable init used to perform:
        /// pre-#251 `Search.Source(rawValue: "wwdc-transcripts")`
        /// returned nil, and callers branched on that to reject
        /// unknown source strings. Post-#251 every string round-trips
        /// into a valid Source, so callers that need the old "is this
        /// a real source?" gate should check `isRegistered` directly.
        public var isRegistered: Bool {
            Search.SourceRegistry.definition(for: rawValue) != nil
        }
    }
}

// MARK: - Query Intent (For Source Prioritization)

/// Detected intent of the search query - determines which sources get boosted
/// This is learned empirically from analyzing each source's nature
extension Search {
    public enum QueryIntent: String, Codable, Sendable {
        case apiReference // "UIView frame", "String methods" → apple-docs
        case howTo // "how to animate", "implement dark mode" → samples, apple-docs
        case designGuidance // "button placement", "typography best practices" → hig
        case languageFeature // "async/await", "property wrappers" → swift-evolution, swift-book
        case conceptual // "concurrency model", "memory management" → apple-docs, swift-book
        case troubleshooting // "crash when", "error handling" → samples, archive
        case migration // "migrate to SwiftUI", "deprecation" → archive, evolution
        case packageDiscovery // "networking library", "JSON parsing package" → packages
        case legacy // "Objective-C", "NSObject", older frameworks → archive, apple-docs

        /// Sources boosted for this intent (in priority order)
        /// Now data-driven via SourceRegistry instead of hardcoded
        public var boostedSources: [Search.Source] {
            // Use registry-based lookup (data-driven)
            registryBoostedSources
        }

        /// Boost multiplier for boosted sources (1.0 = no boost)
        public var boostMultiplier: Double {
            2.0 // Boosted sources get 2x score
        }
    }
}

/// Analyze a query to detect intent
/// Uses keyword heuristics and pattern matching
///
/// #673 Phase D iter-5: 102-line body — sequence of pattern-match checks
/// over `queryLower` (legacy / Obj-C / Swift / sample / etc.). Reads as
/// a flat decision tree; splitting fragments the precedence order
/// (early-return cases must stay in the same function).
// swiftlint:disable:next function_body_length
public func detectQueryIntent(_ query: String) -> Search.QueryIntent {
    let queryLower = query.lowercased()

    // Legacy/Objective-C detection (check early - specific patterns)
    // NS prefix is the classic Objective-C naming convention
    // Also detect explicit Objective-C mentions and older frameworks
    let legacyPrefixes = [
        "nsobject",
        "nsarray",
        "nsdictionary",
        "nsstring",
        "nsnumber",
        "nsurl",
        "nsdata",
        "nserror",
        "nsnotification",
        "nscoder",
        "nsview",
        "nswindow",
        "nsapplication",
        "nstableview",
        "uiview",
        "uiviewcontroller",
        "uitableview",
        "uicollectionview",
    ]
    let legacyKeywords = [
        "objective-c",
        "objc",
        "@objc",
        "bridging",
        "toll-free",
        "autorelease",
        "retain",
        "release",
        "arc",
        "manual memory",
        "nil vs null",
        "selector",
        "@selector",
        "respondsToSelector",
        "performSelector",
        "nib",
        "xib",
        "storyboard segue",
    ]
    let legacyFrameworks = [
        "carbon",
        "cocoa",
        "appkit legacy",
        "foundation legacy",
        "core foundation",
        "cfstring",
        "cfarray",
        "cfdictionary",
    ]

    if legacyKeywords.contains(where: { queryLower.contains($0) }) ||
        legacyFrameworks.contains(where: { queryLower.contains($0) }) {
        return .legacy
    }
    // Check for NS-prefixed classes (but not modern ones like NSObject in Swift context)
    if legacyPrefixes.contains(where: { queryLower.hasPrefix($0) }),
       !queryLower.contains("swift") {
        return .legacy
    }

    // How-to queries
    if queryLower.contains("how to") || queryLower.contains("implement") ||
        queryLower.contains("create") || queryLower.contains("tutorial") ||
        queryLower.contains("example") || queryLower.contains("sample") {
        return .howTo
    }

    // Design guidance
    if queryLower.contains("design") || queryLower.contains("guideline") ||
        queryLower.contains("best practice") || queryLower.contains("layout") ||
        queryLower.contains("typography") || queryLower.contains("ux") ||
        queryLower.contains("user interface") || queryLower.contains("accessibility design") {
        return .designGuidance
    }

    // Language features (Swift Evolution territory)
    if queryLower.contains("proposal") || queryLower.contains("se-") ||
        queryLower.contains("async") || queryLower.contains("await") ||
        queryLower.contains("actor") || queryLower.contains("sendable") ||
        queryLower.contains("property wrapper") || queryLower.contains("result builder") ||
        queryLower.contains("macro") || queryLower.contains("swift 5") ||
        queryLower.contains("swift 6") {
        return .languageFeature
    }

    // Migration (from old to new)
    if queryLower.contains("migrate") || queryLower.contains("deprecated") ||
        queryLower.contains("replacement") || queryLower.contains("upgrade") ||
        queryLower.contains("convert to swift") || queryLower.contains("swiftui from uikit") ||
        queryLower.contains("modernize") {
        return .migration
    }

    // Troubleshooting
    if queryLower.contains("error") || queryLower.contains("crash") ||
        queryLower.contains("fix") || queryLower.contains("debug") ||
        queryLower.contains("issue") || queryLower.contains("problem") ||
        queryLower.contains("not working") || queryLower.contains("fails") {
        return .troubleshooting
    }

    // Package discovery
    if queryLower.contains("library") || queryLower.contains("package") ||
        queryLower.contains("dependency") || queryLower.contains("spm") ||
        queryLower.contains("swift package") || queryLower.contains("cocoapods") {
        return .packageDiscovery
    }

    // Conceptual understanding
    if queryLower.contains("concept") || queryLower.contains("architecture") ||
        queryLower.contains("pattern") || queryLower.contains("how does") ||
        queryLower.contains("what is") || queryLower.contains("explain") ||
        queryLower.contains("understand") || queryLower.contains("overview") {
        return .conceptual
    }

    // Default to API reference
    return .apiReference
}

// MARK: - Source Properties (Quarks - Measurable Attributes)

/// Properties of each documentation source
/// These are the "quarks" - fundamental measurable attributes
/// Values determined empirically by testing each source
extension Search {
    public struct SourceProperties: Codable, Sendable {
        /// How authoritative/official is this source? (0.0-1.0)
        public let authority: Double

        /// How current/fresh is the content? (0.0-1.0)
        public let freshness: Double

        /// How comprehensive is the coverage? (0.0-1.0)
        public let comprehensiveness: Double

        /// Does it have working code examples? (0.0-1.0)
        public let codeExamples: Double

        /// Does it include platform availability info? (0.0-1.0)
        public let hasAvailability: Double

        /// Is it focused on design/UX? (0.0-1.0)
        public let designFocus: Double

        /// Is it focused on language features? (0.0-1.0)
        public let languageFocus: Double

        /// Base search quality for this source (0.0-1.0)
        public let searchQuality: Double

        public init(
            authority: Double,
            freshness: Double,
            comprehensiveness: Double,
            codeExamples: Double,
            hasAvailability: Double,
            designFocus: Double,
            languageFocus: Double,
            searchQuality: Double
        ) {
            self.authority = authority
            self.freshness = freshness
            self.comprehensiveness = comprehensiveness
            self.codeExamples = codeExamples
            self.hasAvailability = hasAvailability
            self.designFocus = designFocus
            self.languageFocus = languageFocus
            self.searchQuality = searchQuality
        }

        /// Combined score for a given intent
        public func scoreFor(intent: QueryIntent) -> Double {
            switch intent {
            case .apiReference:
                return (authority * 0.4) + (comprehensiveness * 0.3) + (hasAvailability * 0.3)
            case .howTo:
                return (codeExamples * 0.5) + (authority * 0.3) + (freshness * 0.2)
            case .designGuidance:
                return (designFocus * 0.6) + (authority * 0.3) + (freshness * 0.1)
            case .languageFeature:
                return (languageFocus * 0.5) + (freshness * 0.3) + (authority * 0.2)
            case .conceptual:
                return (comprehensiveness * 0.4) + (authority * 0.3) + (languageFocus * 0.3)
            case .troubleshooting:
                return (codeExamples * 0.5) + (searchQuality * 0.3) + (comprehensiveness * 0.2)
            case .migration:
                return (freshness * 0.4) + (comprehensiveness * 0.3) + (authority * 0.3)
            case .packageDiscovery:
                return (freshness * 0.4) + (codeExamples * 0.3) + (searchQuality * 0.3)
            case .legacy:
                // Legacy prefers comprehensive historical coverage over freshness
                return (comprehensiveness * 0.5) + (codeExamples * 0.3) + (authority * 0.2)
            }
        }
    }
}

/// Source properties for each source
/// @deprecated Use `SourceRegistry` instead - this is kept for backward compatibility
/// Values now consolidated in `SourceDefinition.swift`
@available(*, deprecated, message: "Use SourceRegistry.properties(for:) instead")
extension Search {
    public enum SourcePropertiesRegistry {
        /// @deprecated Use `SourceRegistry.properties(for:)` instead.
        ///
        /// Post-#251 second cut, `Search.Source` is no longer a closed
        /// `CaseIterable` enum, so the historical "iterate all cases"
        /// build pattern was rewritten to iterate the `SourceRegistry`
        /// definitions directly. Behaviour-preserving for the
        /// known-sources set; future sources registered in
        /// `SourceRegistry` are picked up here automatically.
        public static var properties: [Search.Source: SourceProperties] {
            var result: [Search.Source: SourceProperties] = [:]
            for definition in SourceRegistry.all {
                result[Search.Source(rawValue: definition.id)] = definition.properties
            }
            return result
        }

        /// @deprecated Use `SourceRegistry.properties(for:)` instead
        public static func properties(for source: Search.Source) -> SourceProperties {
            SourceRegistry.properties(for: source.rawValue) ?? SourceProperties(
                authority: 0.5, freshness: 0.5, comprehensiveness: 0.5, codeExamples: 0.5,
                hasAvailability: 0.5, designFocus: 0.5, languageFocus: 0.5, searchQuality: 0.5
            )
        }
    }
}

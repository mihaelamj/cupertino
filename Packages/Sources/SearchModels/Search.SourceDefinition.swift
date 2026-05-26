import Foundation
import SharedConstants

// MARK: - Source Definition

/// Unified definition for a documentation source.
/// Consolidates all source configuration in one place:
/// - Identity (ID, display name, emoji)
/// - Quality properties (for ranking)
/// - Intent mappings (for query-aware boosting)
/// - Optional metadata (URLs, directories)
extension Search {
    public struct SourceDefinition: Sendable, Identifiable {
        // MARK: Identity

        /// Unique identifier (e.g., "apple-docs", "wwdc-transcripts")
        public let id: String

        /// Human-readable display name
        public let displayName: String

        /// Emoji for visual identification
        public let emoji: String

        // MARK: Quality Properties

        /// Source quality properties for ranking
        public let properties: SourceProperties

        // MARK: Intent Mapping

        /// Query intents this source serves well
        public let intents: Set<QueryIntent>

        /// Priority for each intent (higher = more relevant)
        /// Used to order sources when multiple match an intent
        public let intentPriority: [QueryIntent: Int]

        // MARK: Optional Metadata

        /// Base URL for online content (if applicable)
        public let baseURL: URL?

        /// Local directory for cached content (if applicable)
        public let localDirectory: String?

        /// Whether this source is currently enabled
        public let isEnabled: Bool

        /// #1045 Gap 3: pluggability seam for `Search.Classify.kind(...)`.
        /// Each source declares the rawValue of its default
        /// `Search.DocKind` (e.g., `"evolutionProposal"` for swift-evolution,
        /// `"hig"` for hig). SearchSQLite's classifier consults this
        /// string via the composition-root-built `[String: String]` map
        /// passed to `Classify.kind(...)`; the classifier resolves the
        /// string to its own `DocKind` enum via `DocKind(rawValue:)`.
        ///
        /// `nil` means "no default kind — use bespoke classification or
        /// fall through to `.unknown`". `apple-docs` declares nil
        /// because its classifier partitions by `structuredKind` +
        /// `uriPath`; `samples` / `packages` declare nil because they
        /// don't write `docs_metadata` rows that need this taxonomy.
        ///
        /// String-typed (not `DocKind`-typed) to keep `SearchModels` a
        /// foundation-only target — `DocKind` is a SearchSQLite-tier
        /// classifier output. Foundation can't see SearchSQLite.
        public let defaultDocKindRawValue: String?

        // MARK: Initializer

        public init(
            id: String,
            displayName: String,
            emoji: String,
            properties: SourceProperties,
            intents: Set<QueryIntent>,
            intentPriority: [QueryIntent: Int] = [:],
            baseURL: URL? = nil,
            localDirectory: String? = nil,
            isEnabled: Bool = true,
            defaultDocKindRawValue: String? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.emoji = emoji
            self.properties = properties
            self.intents = intents
            self.intentPriority = intentPriority
            self.baseURL = baseURL
            self.localDirectory = localDirectory
            self.isEnabled = isEnabled
            self.defaultDocKindRawValue = defaultDocKindRawValue
        }

        /// Get priority for a specific intent (default: 50)
        public func priority(for intent: QueryIntent) -> Int {
            intentPriority[intent] ?? 50
        }
    }
}

// #934 Step 3b: the rest of this file (the static `Search.SourceRegistry`
// enum with its `all: [SourceDefinition]` array + 7 static lookup
// methods, the `Search.Source` convenience extension exposing
// `definition` / `properties` / `intents`, and the
// `Search.QueryIntent` convenience extension exposing
// `boostedSourceIDs` / `registryBoostedSources`) was DELETED. Every
// surface was a Service Locator per `gof-di-rules.md` Rule 1.
// Callers route through `Search.SourceLookup` (foundation-only
// value type, also in this target); the production list is
// composition-root-assembled in `CLIImpl.SourceLookup.swift`.

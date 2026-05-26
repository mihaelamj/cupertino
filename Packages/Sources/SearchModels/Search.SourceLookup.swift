import Foundation

// MARK: - Search.SourceLookup

extension Search {
    /// Composition-root-injected value type wrapping the full set of
    /// `Search.SourceDefinition` rows the binary knows about. Replaces
    /// the static `Search.SourceRegistry.all` array that lived in
    /// `Search.SourceDefinition.swift` pre-#934 (a Service Locator
    /// surface per `gof-di-rules.md` Rule 1).
    ///
    /// Every consumer that historically reached for
    /// `Search.SourceRegistry.{all, definition(for:), allIDs,
    /// enabledIDs, sources(for:), sourceIDs(for:), properties(for:),
    /// isValid(_:)}` now takes a `Search.SourceLookup` instance via
    /// its constructor and queries the equivalent instance method.
    /// The CLI composition root in
    /// `CLIImpl.Command.Save.Indexers.swift` (and any future
    /// composition site) assembles the production list inline with
    /// the 8 historical sources; tests construct fake lookups for
    /// their fixtures.
    public struct SourceLookup: Sendable {
        /// All registered source definitions, in the order the
        /// composition root supplied them.
        public let definitions: [Search.SourceDefinition]

        public init(definitions: [Search.SourceDefinition]) {
            self.definitions = definitions
        }

        /// Empty lookup. Used by tests that never exercise the
        /// ranking path or by read-only consumers that only need the
        /// `Search.Index` actor for non-lookup APIs. The composition
        /// root MUST NOT use this; it must construct a full lookup.
        public static let empty: Search.SourceLookup = .init(definitions: [])

        // MARK: - Lookup methods (1-to-1 with pre-#934 SourceRegistry statics)

        /// Get definition by source ID. Linear scan; tolerable
        /// because production lookups happen on a handful of items.
        public func definition(for id: String) -> Search.SourceDefinition? {
            definitions.first { $0.id == id }
        }

        /// Get all source IDs in the order the composition root supplied them.
        public var allIDs: [String] {
            definitions.map(\.id)
        }

        /// Get all enabled source IDs (callers filter on `isEnabled`).
        public var enabledIDs: [String] {
            definitions.filter(\.isEnabled).map(\.id)
        }

        /// Get sources for a specific intent, sorted by intent priority desc.
        public func sources(for intent: Search.QueryIntent) -> [Search.SourceDefinition] {
            definitions
                .filter { $0.intents.contains(intent) }
                .sorted { $0.priority(for: intent) > $1.priority(for: intent) }
        }

        /// Get source IDs for a specific intent, sorted by intent priority desc.
        public func sourceIDs(for intent: Search.QueryIntent) -> [String] {
            sources(for: intent).map(\.id)
        }

        /// Get `SourceProperties` for a source ID.
        public func properties(for id: String) -> Search.SourceProperties? {
            definition(for: id)?.properties
        }

        /// Check if a source ID is registered.
        public func isValid(_ id: String) -> Bool {
            definition(for: id) != nil
        }

        /// #1045 Gap 3: registry-derived map from source-id to
        /// `Search.DocKind` rawValue. Composition root passes this via
        /// the SourceLookup (already plumbed through `Search.Index`'s
        /// init); SearchSQLite's `Search.Classify.kind(...)` looks up
        /// the rawValue here and resolves to its own `DocKind` enum.
        /// Sources with `defaultDocKindRawValue == nil` (apple-docs's
        /// bespoke classifier path; samples / packages which don't
        /// emit `docs_metadata` rows) are absent from the dict.
        public var docKindRawValuesByID: [String: String] {
            var result: [String: String] = [:]
            for definition in definitions {
                if let rawValue = definition.defaultDocKindRawValue {
                    result[definition.id] = rawValue
                }
            }
            return result
        }

        // MARK: - Convenience for Search.Source

        /// Display name for a `Search.Source`, falling back to the raw
        /// value when no descriptor row exists.
        public func displayName(for source: Search.Source) -> String {
            definition(for: source.rawValue)?.displayName ?? source.rawValue
        }

        /// Emoji for a `Search.Source`, falling back to an empty string
        /// when no descriptor row exists.
        public func emoji(for source: Search.Source) -> String {
            definition(for: source.rawValue)?.emoji ?? ""
        }

        /// Whether the `Search.Source` has a descriptor row in this lookup.
        public func isRegistered(_ source: Search.Source) -> Bool {
            definition(for: source.rawValue) != nil
        }

        /// Boosted `Search.Source` values for a query intent, in
        /// priority order. Replaces the pre-#934
        /// `Search.QueryIntent.boostedSources` property extension that
        /// reached for the `SourceRegistry` static.
        public func boostedSources(for intent: Search.QueryIntent) -> [Search.Source] {
            sourceIDs(for: intent).map { Search.Source(rawValue: $0) }
        }
    }
}

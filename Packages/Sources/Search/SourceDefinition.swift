import Foundation

// MARK: - Source Definition

/// Unified definition for a documentation source.
/// Consolidates all source configuration in one place:
/// - Identity (ID, display name, emoji)
/// - Quality properties (for ranking)
/// - Intent mappings (for query-aware boosting)
/// - Optional metadata (URLs, directories)
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
        isEnabled: Bool = true
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
    }

    /// Get priority for a specific intent (default: 50)
    public func priority(for intent: QueryIntent) -> Int {
        intentPriority[intent] ?? 50
    }
}

// MARK: - Source Registry

/// Central registry of all documentation sources.
/// Single source of truth for source configuration.
public enum SourceRegistry {
    // MARK: - All Source Definitions

    /// All registered source definitions
    public static let all: [SourceDefinition] = [
        // Apple Documentation (modern)
        SourceDefinition(
            id: "apple-docs",
            displayName: "Apple Documentation",
            emoji: "📘",
            properties: SourceProperties(
                authority: 1.0,
                freshness: 0.9,
                comprehensiveness: 1.0,
                codeExamples: 0.3,
                hasAvailability: 1.0,
                designFocus: 0.2,
                languageFocus: 0.2,
                searchQuality: 0.5
            ),
            intents: [.apiReference, .conceptual, .howTo, .troubleshooting],
            intentPriority: [
                .apiReference: 100,
                .conceptual: 80,
                .howTo: 60,
                .troubleshooting: 50,
            ],
            baseURL: URL(string: "https://developer.apple.com/documentation")
        ),

        // Sample Code
        SourceDefinition(
            id: "samples",
            displayName: "Sample Code",
            emoji: "💻",
            properties: SourceProperties(
                authority: 1.0,
                freshness: 0.8,
                comprehensiveness: 0.4,
                codeExamples: 1.0,
                hasAvailability: 0.5,
                designFocus: 0.4,
                languageFocus: 0.3,
                searchQuality: 0.9
            ),
            intents: [.howTo, .troubleshooting, .conceptual],
            intentPriority: [
                .howTo: 100,
                .troubleshooting: 80,
                .conceptual: 40,
            ],
            baseURL: URL(string: "https://developer.apple.com/sample-code")
        ),

        // Human Interface Guidelines
        SourceDefinition(
            id: "hig",
            displayName: "Human Interface Guidelines",
            emoji: "🎨",
            properties: SourceProperties(
                authority: 1.0,
                freshness: 0.9,
                comprehensiveness: 0.7,
                codeExamples: 0.0,
                hasAvailability: 0.3,
                designFocus: 1.0,
                languageFocus: 0.0,
                searchQuality: 0.9
            ),
            intents: [.designGuidance],
            intentPriority: [
                .designGuidance: 100,
            ],
            baseURL: URL(string: "https://developer.apple.com/design/human-interface-guidelines")
        ),

        // Apple Archive (legacy)
        SourceDefinition(
            id: "apple-archive",
            displayName: "Apple Archive",
            emoji: "📚",
            properties: SourceProperties(
                authority: 0.8,
                freshness: 0.3,
                comprehensiveness: 0.8,
                codeExamples: 0.6,
                hasAvailability: 0.4,
                designFocus: 0.3,
                languageFocus: 0.2,
                searchQuality: 0.6
            ),
            intents: [.legacy, .migration, .troubleshooting],
            intentPriority: [
                .legacy: 100,
                .migration: 80,
                .troubleshooting: 60,
            ],
            baseURL: URL(string: "https://developer.apple.com/library/archive")
        ),

        // Swift Evolution
        SourceDefinition(
            id: "swift-evolution",
            displayName: "Swift Evolution",
            emoji: "🔮",
            properties: SourceProperties(
                authority: 1.0,
                freshness: 0.95,
                comprehensiveness: 0.6,
                codeExamples: 0.8,
                hasAvailability: 0.2,
                designFocus: 0.1,
                languageFocus: 1.0,
                searchQuality: 0.9
            ),
            intents: [.languageFeature, .migration, .conceptual],
            intentPriority: [
                .languageFeature: 100,
                .migration: 70,
                .conceptual: 50,
            ],
            baseURL: URL(string: "https://github.com/swiftlang/swift-evolution")
        ),

        // Swift.org
        SourceDefinition(
            id: "swift-org",
            displayName: "Swift.org",
            emoji: "🦅",
            properties: SourceProperties(
                authority: 1.0,
                freshness: 0.9,
                comprehensiveness: 0.5,
                codeExamples: 0.5,
                hasAvailability: 0.1,
                designFocus: 0.1,
                languageFocus: 0.8,
                searchQuality: 0.7
            ),
            intents: [.languageFeature, .conceptual, .howTo],
            intentPriority: [
                .languageFeature: 80,
                .conceptual: 70,
                .howTo: 50,
            ],
            baseURL: URL(string: "https://swift.org")
        ),

        // The Swift Programming Language (book)
        SourceDefinition(
            id: "swift-book",
            displayName: "The Swift Programming Language",
            emoji: "📖",
            properties: SourceProperties(
                authority: 1.0,
                freshness: 0.9,
                comprehensiveness: 0.9,
                codeExamples: 0.9,
                hasAvailability: 0.1,
                designFocus: 0.0,
                languageFocus: 1.0,
                searchQuality: 0.9
            ),
            intents: [.languageFeature, .conceptual, .howTo],
            intentPriority: [
                .languageFeature: 90,
                .conceptual: 90,
                .howTo: 60,
            ],
            baseURL: URL(string: "https://docs.swift.org/swift-book")
        ),

        // Swift Packages
        SourceDefinition(
            id: "packages",
            displayName: "Swift Packages",
            emoji: "📦",
            properties: SourceProperties(
                authority: 0.6,
                freshness: 0.8,
                comprehensiveness: 0.3,
                codeExamples: 0.4,
                hasAvailability: 0.2,
                designFocus: 0.1,
                languageFocus: 0.3,
                searchQuality: 0.6
            ),
            intents: [.packageDiscovery],
            intentPriority: [
                .packageDiscovery: 100,
            ],
            baseURL: URL(string: "https://swiftpackageindex.com")
        ),
    ]

    // MARK: - Lookup Methods

    /// Get definition by source ID
    public static func definition(for id: String) -> SourceDefinition? {
        all.first { $0.id == id }
    }

    /// Get all source IDs
    public static var allIDs: [String] {
        all.map(\.id)
    }

    /// Get all enabled source IDs
    public static var enabledIDs: [String] {
        all.filter(\.isEnabled).map(\.id)
    }

    /// Get sources for a specific intent, sorted by priority
    public static func sources(for intent: QueryIntent) -> [SourceDefinition] {
        all.filter { $0.intents.contains(intent) }
            .sorted { $0.priority(for: intent) > $1.priority(for: intent) }
    }

    /// Get source IDs for a specific intent, sorted by priority
    public static func sourceIDs(for intent: QueryIntent) -> [String] {
        sources(for: intent).map(\.id)
    }

    /// Get SourceProperties for a source ID
    public static func properties(for id: String) -> SourceProperties? {
        definition(for: id)?.properties
    }

    /// Check if a source ID is valid
    public static func isValid(_ id: String) -> Bool {
        definition(for: id) != nil
    }
}

// MARK: - SearchSource Extension

/// Extend SearchSource to use SourceRegistry
public extension SearchSource {
    /// Get the SourceDefinition for this source
    var definition: SourceDefinition? {
        SourceRegistry.definition(for: rawValue)
    }

    /// Get SourceProperties from registry
    var properties: SourceProperties? {
        definition?.properties
    }

    /// Get intents this source serves
    var intents: Set<QueryIntent> {
        definition?.intents ?? []
    }
}

// MARK: - QueryIntent Extension

/// Extend QueryIntent to use SourceRegistry for boosted sources
public extension QueryIntent {
    /// Get boosted source IDs from registry (data-driven)
    var boostedSourceIDs: [String] {
        SourceRegistry.sourceIDs(for: self)
    }

    /// Get boosted SearchSources from registry
    var registryBoostedSources: [SearchSource] {
        boostedSourceIDs.compactMap { SearchSource(rawValue: $0) }
    }
}

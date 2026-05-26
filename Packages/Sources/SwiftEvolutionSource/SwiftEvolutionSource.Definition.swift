import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftEvolutionSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target.
extension SwiftEvolutionSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.swiftEvolution,
        displayName: "Swift Evolution",
        emoji: "🔮",
        properties: Search.SourceProperties(
            authority: 1.0,
            freshness: 0.95,
            comprehensiveness: 0.6,
            codeExamples: 0.8,
            hasAvailability: 0.2,
            designFocus: 0.1,
            languageFocus: 1.0,
            searchQuality: 0.9,
            rankWeight: 1.5
        ),
        intents: [.languageFeature, .migration, .conceptual],
        intentPriority: [
            .languageFeature: 100,
            .migration: 70,
            .conceptual: 50,
        ],
        baseURL: URL(string: Shared.Constants.BaseURL.swiftEvolution),
        defaultDocKindRawValue: "evolutionProposal"
    )
}

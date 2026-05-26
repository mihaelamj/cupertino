import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftOrgSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target.
extension SwiftOrgSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.swiftOrg,
        displayName: "Swift.org",
        emoji: "🦅",
        properties: Search.SourceProperties(
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
        baseURL: URL(string: Shared.Constants.BaseURL.swiftOrgBase),
        defaultDocKindRawValue: "swiftOrgDoc"
    )
}

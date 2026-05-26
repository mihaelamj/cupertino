import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftBookSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target.
extension SwiftBookSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.swiftBook,
        displayName: "The Swift Programming Language",
        emoji: "📖",
        properties: Search.SourceProperties(
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
        baseURL: URL(string: Shared.Constants.BaseURL.swiftBookBase),
        defaultDocKindRawValue: "swiftBook"
    )
}

import Foundation
import SearchModels
import SharedConstants

// MARK: - AppleDocsSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target. Each
/// `<X>Source/` target carries its own definition so adding a new
/// source no longer touches the CLI composition root's definition
/// list (#1007 epic goal).
extension AppleDocsSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.appleDocs,
        displayName: "Apple Documentation",
        emoji: "📘",
        properties: Search.SourceProperties(
            authority: 1.0,
            freshness: 0.9,
            comprehensiveness: 1.0,
            codeExamples: 0.3,
            hasAvailability: 1.0,
            designFocus: 0.2,
            languageFocus: 0.2,
            searchQuality: 0.5,
            rankWeight: 3.0
        ),
        intents: [.apiReference, .conceptual, .howTo, .troubleshooting],
        intentPriority: [
            .apiReference: 100,
            .conceptual: 80,
            .howTo: 60,
            .troubleshooting: 50,
        ],
        baseURL: URL(string: Shared.Constants.BaseURL.appleDeveloper + "/documentation")
    )
}

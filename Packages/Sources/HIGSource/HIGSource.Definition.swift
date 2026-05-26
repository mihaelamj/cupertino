import Foundation
import SearchModels
import SharedConstants

// MARK: - HIGSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target. Each
/// `<X>Source/` target carries its own definition so adding a new
/// source no longer touches the CLI composition root's definition
/// list (#1007 epic goal).
extension HIGSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.hig,
        displayName: "Human Interface Guidelines",
        emoji: "🎨",
        properties: Search.SourceProperties(
            authority: 1.0,
            freshness: 0.9,
            comprehensiveness: 0.7,
            codeExamples: 0.0,
            hasAvailability: 0.3,
            designFocus: 1.0,
            languageFocus: 0.0,
            searchQuality: 0.9,
            rankWeight: 0.5
        ),
        intents: [.designGuidance],
        intentPriority: [.designGuidance: 100],
        baseURL: URL(string: Shared.Constants.BaseURL.appleDeveloper + "/design/human-interface-guidelines"),
        defaultDocKindRawValue: "hig"
    )
}

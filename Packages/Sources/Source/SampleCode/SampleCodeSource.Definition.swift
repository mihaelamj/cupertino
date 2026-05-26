import Foundation
import SearchModels
import SharedConstants

// MARK: - SampleCodeSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target. Each
/// `<X>Source/` target carries its own definition so adding a new
/// source no longer touches the CLI composition root's definition
/// list (#1007 epic goal).
extension SampleCodeSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.samples,
        displayName: "Sample Code",
        emoji: "💻",
        properties: Search.SourceProperties(
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
        baseURL: URL(string: Shared.Constants.BaseURL.appleDeveloper + "/sample-code")
    )
}

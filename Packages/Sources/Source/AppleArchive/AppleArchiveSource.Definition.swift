import Foundation
import SearchModels
import SharedConstants

// MARK: - AppleArchiveSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target. Each
/// `<X>Source/` target carries its own definition so adding a new
/// source no longer touches the CLI composition root's definition
/// list (#1007 epic goal).
extension AppleArchiveSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.appleArchive,
        displayName: "Apple Archive (Legacy)",
        emoji: "📚",
        properties: Search.SourceProperties(
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
        baseURL: URL(string: Shared.Constants.BaseURL.appleDeveloper + "/library/archive")
    )
}

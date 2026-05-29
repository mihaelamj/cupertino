import Foundation
import SearchModels
import SharedConstants

// MARK: - PackagesSource.definition

/// Per-source `Search.SourceDefinition` literal lifted from
/// `CLI/CLIImpl.SourceLookup.swift` to this per-source target. The
/// definition lets queries discover and rank `source = packages`
/// rows that live in packages.db.
extension PackagesSource {
    public static let definition: Search.SourceDefinition = .init(
        id: Shared.Constants.SourcePrefix.packages,
        displayName: "Swift Packages",
        emoji: "📦",
        properties: Search.SourceProperties(
            authority: 0.6,
            freshness: 0.8,
            comprehensiveness: 0.3,
            codeExamples: 0.4,
            hasAvailability: 0.2,
            designFocus: 0.1,
            languageFocus: 0.3,
            searchQuality: 0.6,
            rankWeight: 1.5
        ),
        intents: [.packageDiscovery],
        intentPriority: [.packageDiscovery: 100],
        baseURL: URL(string: Shared.Constants.BaseURL.swiftPackageIndex),
        requiredEnrichmentInputs: [.appleConstraints, .appleConformances, .packageAvailability]
    )
}

import Foundation
import SearchModels
import SharedConstants

// MARK: - CLIImpl.makeProductionSourceLookup

/// Composition-root factory that returns the `Search.SourceLookup`
/// with all 8 production source definitions. Lives in the `CLIImpl.*`
/// wiring layer (the `executableTarget` composition root) per
/// `gof-di-rules.md` Rule 6: the binary's `*Impl` filenames are where
/// concrete production wiring happens.
///
/// Pre-#934 these definitions lived in `SearchModels` as a public
/// static `Search.SourceRegistry.all` array, a Service Locator that
/// every consumer reached for. #934 dissolved the static and lifted
/// the list to this composition site. Producer code now takes a
/// `Search.SourceLookup` via its constructor (`Search.Index.init`
/// gained the parameter); the executable supplies the production
/// list here.
///
/// **Adding a new source post-#934:** one new `SourceDefinition`
/// literal in this function. Zero edits to `SearchModels`. The
/// `Search.SourceLookup` value type knows nothing about the production
/// list; it just iterates whatever the composition root supplied.
extension CLIImpl {
    static func makeProductionSourceLookup() -> Search.SourceLookup {
        Search.SourceLookup(definitions: [
            Search.SourceDefinition(
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
                    searchQuality: 0.5
                ),
                intents: [.apiReference, .conceptual, .howTo, .troubleshooting],
                intentPriority: [
                    .apiReference: 100,
                    .conceptual: 80,
                    .howTo: 60,
                    .troubleshooting: 50,
                ],
                baseURL: URL(string: Shared.Constants.BaseURL.appleDeveloper + "/documentation")
            ),
            Search.SourceDefinition(
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
            ),
            Search.SourceDefinition(
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
                    searchQuality: 0.9
                ),
                intents: [.designGuidance],
                intentPriority: [.designGuidance: 100],
                baseURL: URL(string: Shared.Constants.BaseURL.appleDeveloper + "/design/human-interface-guidelines")
            ),
            Search.SourceDefinition(
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
            ),
            Search.SourceDefinition(
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
                    searchQuality: 0.9
                ),
                intents: [.languageFeature, .migration, .conceptual],
                intentPriority: [
                    .languageFeature: 100,
                    .migration: 70,
                    .conceptual: 50,
                ],
                baseURL: URL(string: Shared.Constants.BaseURL.swiftEvolution)
            ),
            Search.SourceDefinition(
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
                baseURL: URL(string: Shared.Constants.BaseURL.swiftOrgBase)
            ),
            Search.SourceDefinition(
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
                baseURL: URL(string: Shared.Constants.BaseURL.swiftBookBase)
            ),
            Search.SourceDefinition(
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
                    searchQuality: 0.6
                ),
                intents: [.packageDiscovery],
                intentPriority: [.packageDiscovery: 100],
                baseURL: URL(string: Shared.Constants.BaseURL.swiftPackageIndex)
            ),
        ])
    }
}

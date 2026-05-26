// swiftlint:disable file identifier_name use_data_constructor_over_string_member empty_count
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #934 coverage pins: Search.SourceLookup composition-root injection

@Suite("#934: Search.SourceLookup contract")
struct Issue934SourceLookupContractTests {
    @Test("empty lookup returns nil/empty for every method")
    func emptyLookupContract() {
        let lookup = Search.SourceLookup.empty
        #expect(lookup.definitions.isEmpty)
        #expect(lookup.allIDs.isEmpty)
        #expect(lookup.enabledIDs.isEmpty)
        #expect(lookup.definition(for: "apple-docs") == nil)
        #expect(lookup.properties(for: "apple-docs") == nil)
        #expect(lookup.isValid("apple-docs") == false)
        #expect(lookup.displayName(for: Search.Source.appleDocs) == "apple-docs")
        #expect(lookup.emoji(for: Search.Source.appleDocs) == "")
        #expect(lookup.isRegistered(Search.Source.appleDocs) == false)
        #expect(lookup.sources(for: .apiReference).isEmpty)
        #expect(lookup.sourceIDs(for: .apiReference).isEmpty)
        #expect(lookup.boostedSources(for: .apiReference).isEmpty)
    }

    @Test("a lookup with a single definition exposes that definition through every accessor")
    func singleDefinitionLookup() {
        let fake = Search.SourceDefinition(
            id: "wwdc-transcripts",
            displayName: "WWDC Transcripts",
            emoji: "🎥",
            properties: Search.SourceProperties(
                authority: 1.0,
                freshness: 0.5,
                comprehensiveness: 0.6,
                codeExamples: 0.7,
                hasAvailability: 0.4,
                designFocus: 0.3,
                languageFocus: 0.4,
                searchQuality: 0.7
            ),
            intents: [.howTo, .conceptual]
        )
        let lookup = Search.SourceLookup(definitions: [fake])
        #expect(lookup.definitions.count == 1)
        #expect(lookup.definition(for: "wwdc-transcripts") != nil)
        #expect(lookup.properties(for: "wwdc-transcripts")?.searchQuality == 0.7)
        #expect(lookup.isValid("wwdc-transcripts"))
        #expect(lookup.allIDs == ["wwdc-transcripts"])
        #expect(lookup.displayName(for: Search.Source(rawValue: "wwdc-transcripts")) == "WWDC Transcripts")
        #expect(lookup.emoji(for: Search.Source(rawValue: "wwdc-transcripts")) == "🎥")
        // Intent-based queries route correctly.
        let howTo = lookup.sourceIDs(for: .howTo)
        #expect(howTo == ["wwdc-transcripts"])
        let designGuidance = lookup.sourceIDs(for: .designGuidance)
        #expect(designGuidance.isEmpty, "fake source does not list .designGuidance in its intents")
    }

    @Test("intent-priority sort: higher-priority sources come first")
    func intentPrioritySort() {
        let a = Search.SourceDefinition(
            id: "alpha",
            displayName: "Alpha",
            emoji: "A",
            properties: Search.SourceProperties(
                authority: 1, freshness: 1, comprehensiveness: 1,
                codeExamples: 1, hasAvailability: 1, designFocus: 1,
                languageFocus: 1, searchQuality: 1
            ),
            intents: [.apiReference],
            intentPriority: [.apiReference: 50]
        )
        let b = Search.SourceDefinition(
            id: "bravo",
            displayName: "Bravo",
            emoji: "B",
            properties: Search.SourceProperties(
                authority: 1, freshness: 1, comprehensiveness: 1,
                codeExamples: 1, hasAvailability: 1, designFocus: 1,
                languageFocus: 1, searchQuality: 1
            ),
            intents: [.apiReference],
            intentPriority: [.apiReference: 100]
        )
        let lookup = Search.SourceLookup(definitions: [a, b])
        let sorted = lookup.sourceIDs(for: .apiReference)
        #expect(sorted == ["bravo", "alpha"], "bravo (priority 100) must come before alpha (priority 50)")
    }
}

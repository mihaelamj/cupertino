import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #919 coverage pins: Search.Source alias + partial-registration semantics

@Suite("#919 coverage: Search.Source alias + partial-registration semantics")
struct Issue919SourceAliasCoverageTests {
    @Test("apple-sample-code is a SourcePrefix alias for samples and has no SourceDefinition row")
    func appleSampleCodeIsPartiallyRegistered() {
        // Documented gap captured during the 2026-05-22 coverage audit:
        // `Shared.Constants.SourcePrefix.appleSampleCode` is the
        // long-form alias for `samples` (used by some MCP / formatter
        // call sites for back-compat with pre-#251 source identifiers).
        // The alias does NOT have its own `SourceDefinition` row in
        // `Search.SourceRegistry.all`; callers that compare a raw
        // source string against the alias canonicalise to the short
        // form (`samples`) before any registry lookup. This test pins
        // the current behaviour so a future PR that adds a
        // SourceDefinition for the alias surfaces here.
        #expect(Shared.Constants.SourcePrefix.appleSampleCode == "apple-sample-code")
        let aliasSource = Search.Source(rawValue: Shared.Constants.SourcePrefix.appleSampleCode)
        #expect(aliasSource.isRegistered == false)
        // Display surface falls back to the raw value (per the
        // documented #251 second-cut behaviour for unregistered sources).
        #expect(aliasSource.displayName == "apple-sample-code")
        #expect(aliasSource.emoji == "")
    }

    @Test("Source.isRegistered cleanly separates the 8 historical sources from anything else")
    func isRegisteredSeparatesKnownFromUnknown() {
        // Pins the structural-validation contract `Source.isRegistered`
        // serves as the post-#251 replacement for the pre-refactor
        // failable init's nil-check.
        let known: [Search.Source] = [
            .appleDocs, .samples, .hig, .appleArchive,
            .swiftEvolution, .swiftOrg, .swiftBook, .packages,
        ]
        for source in known {
            #expect(source.isRegistered, "\(source.rawValue) should be registered")
        }
        let unknown: [String] = [
            "wwdc-transcripts",       // future #58
            "swift-forums",            // future #89
            "tech-talks",              // future #273
            Shared.Constants.SourcePrefix.appleSampleCode, // alias, not its own row
            "",                        // empty
            "Apple-Docs",              // case drift
        ]
        for raw in unknown {
            let source = Search.Source(rawValue: raw)
            #expect(source.isRegistered == false, "\(raw) should not be registered")
        }
    }

    @Test("displayName + emoji fall back deterministically when the source isn't registered")
    func unknownSourceDisplaySurfaceFallback() {
        // Pins the fallback contract for future content sources whose
        // SourceDefinition row hasn't landed yet (e.g. mid-#58
        // WWDC-transcripts arc).
        let wwdc = Search.Source(rawValue: "wwdc-transcripts")
        #expect(wwdc.displayName == "wwdc-transcripts")  // rawValue fallback
        #expect(wwdc.emoji == "")                         // empty string fallback
    }

    @Test("All 8 SourceRegistry rows are reachable via Search.Source static constants")
    func registryIsReachableViaConstants() {
        // The 8 historical Search.Source static constants align 1-to-1
        // with the 8 SourceRegistry rows by id; this test pins that
        // every static constant resolves to a registered source.
        let constantsById: [(Search.Source, String)] = [
            (.appleDocs, Shared.Constants.SourcePrefix.appleDocs),
            (.samples, Shared.Constants.SourcePrefix.samples),
            (.hig, Shared.Constants.SourcePrefix.hig),
            (.appleArchive, Shared.Constants.SourcePrefix.appleArchive),
            (.swiftEvolution, Shared.Constants.SourcePrefix.swiftEvolution),
            (.swiftOrg, Shared.Constants.SourcePrefix.swiftOrg),
            (.swiftBook, Shared.Constants.SourcePrefix.swiftBook),
            (.packages, Shared.Constants.SourcePrefix.packages),
        ]
        for (source, expectedId) in constantsById {
            #expect(source.rawValue == expectedId)
            #expect(source.isRegistered, "\(source.rawValue) must be in SourceRegistry.all")
            #expect(Search.SourceRegistry.definition(for: source.rawValue) != nil)
            #expect(Search.SourceRegistry.definition(for: source.rawValue)?.id == expectedId)
        }
    }

    @Test("Adding a new content source (post-#919) is descriptor-driven; the registry surface is open")
    func registrySurfaceIsOpen() {
        // Pins the #919 pluggability principle as a behavioural test:
        // SourceRegistry.all is a `[SourceDefinition]`; any caller can
        // synthesise a new `SourceDefinition` for an unregistered
        // identifier and the rest of the system addresses it through
        // the same APIs. Today the registry's `all` static is the
        // single edit-point for a new content source to "show up"; this
        // test demonstrates the descriptor itself is constructible
        // without touching `Search.Source`'s declaration.
        let wwdcDescriptor = Search.SourceDefinition(
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
        // Synthesised descriptor matches the structural contract.
        #expect(wwdcDescriptor.id == "wwdc-transcripts")
        #expect(wwdcDescriptor.displayName == "WWDC Transcripts")
        // The descriptor can be used as a value type without any code
        // path needing to know about the new identifier ahead of time.
        let asSource = Search.Source(rawValue: wwdcDescriptor.id)
        #expect(asSource.rawValue == "wwdc-transcripts")
    }
}

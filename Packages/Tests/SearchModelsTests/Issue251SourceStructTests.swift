import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #251 second cut: Search.Source struct invariants

@Suite("#251 second cut: Search.Source struct")
struct Issue251SourceStructTests {
    @Test("Static constants resolve to the SourcePrefix rawValues")
    func staticConstantsMatchSourcePrefix() {
        #expect(Search.Source.appleDocs.rawValue == Shared.Constants.SourcePrefix.appleDocs)
        #expect(Search.Source.samples.rawValue == Shared.Constants.SourcePrefix.samples)
        #expect(Search.Source.hig.rawValue == Shared.Constants.SourcePrefix.hig)
        #expect(Search.Source.appleArchive.rawValue == Shared.Constants.SourcePrefix.appleArchive)
        #expect(Search.Source.swiftEvolution.rawValue == Shared.Constants.SourcePrefix.swiftEvolution)
        #expect(Search.Source.swiftOrg.rawValue == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(Search.Source.swiftBook.rawValue == Shared.Constants.SourcePrefix.swiftBook)
        #expect(Search.Source.packages.rawValue == Shared.Constants.SourcePrefix.packages)
    }

    @Test("Codable encodes to a bare string (preserving the pre-#251 enum wire format)")
    func codableBareStringEncoding() throws {
        let source = Search.Source.appleDocs
        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(Search.Source.self, from: encoded)
        let asString = String(data: encoded, encoding: .utf8)
        // The pre-refactor enum encoded to a bare string. Swift's
        // synthesised Codable for a struct with a stored rawValue
        // would encode to {"rawValue": "..."}; the explicit Codable
        // implementation on Search.Source preserves the bare-string
        // shape so MCP responses, dashboard JSON, and on-disk fixtures
        // round-trip byte-identically pre/post #251.
        #expect(asString == "\"apple-docs\"")
        #expect(decoded == source)
        #expect(decoded.rawValue == "apple-docs")
    }

    @Test("init(rawValue:) is non-failing and accepts unregistered strings (#919 goal)")
    func unregisteredSourcesAreLegal() {
        let wwdc = Search.Source(rawValue: "wwdc-transcripts")
        #expect(wwdc.rawValue == "wwdc-transcripts")
        #expect(wwdc.isRegistered == false)
        // Fallbacks for unregistered sources:
        #expect(wwdc.displayName == "wwdc-transcripts")
        #expect(wwdc.emoji == "")
    }

    @Test("isRegistered is true for the 8 historical sources and false otherwise")
    func isRegisteredMatchesSourceRegistry() {
        #expect(Search.Source.appleDocs.isRegistered)
        #expect(Search.Source.samples.isRegistered)
        #expect(Search.Source.hig.isRegistered)
        #expect(Search.Source.appleArchive.isRegistered)
        #expect(Search.Source.swiftEvolution.isRegistered)
        #expect(Search.Source.swiftOrg.isRegistered)
        #expect(Search.Source.swiftBook.isRegistered)
        #expect(Search.Source.packages.isRegistered)
        #expect(Search.Source(rawValue: "definitely-not-a-source").isRegistered == false)
    }

    @Test("displayName for appleArchive preserves the historical 'Apple Archive (Legacy)' label")
    func appleArchiveDisplayNameByteIdentical() {
        // Pre-#251 the enum's switch returned "Apple Archive (Legacy)".
        // SourceRegistry's row was aligned to the same value as part of
        // the second cut so the user-visible label doesn't drift.
        #expect(Search.Source.appleArchive.displayName == "Apple Archive (Legacy)")
    }
}

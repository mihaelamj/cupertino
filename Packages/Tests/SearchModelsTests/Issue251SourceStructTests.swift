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
        // #934 Step 3b: the `.isRegistered` / `.displayName` /
        // `.emoji` convenience properties are GONE (they reached for
        // the static `Search.SourceRegistry.all`). Registered-ness
        // is now a `Search.SourceLookup.isRegistered(_:)` instance
        // method call against the composition-root lookup.
        let lookup = Search.SourceLookup.empty
        #expect(lookup.isRegistered(wwdc) == false)
        #expect(lookup.displayName(for: wwdc) == "wwdc-transcripts")
        #expect(lookup.emoji(for: wwdc) == "")
    }
}

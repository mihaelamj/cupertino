import Foundation
import SharedConstants
import Testing

// MARK: - CorpusManifest shape pin tests

//
// Pin tests for `Shared.Models.CorpusManifest`, the Codable contract
// for each source's repo-side `docs/sources/<id>/manifest.yaml`. See
// `docs/design/corpus-structure.md` §3 for the schema.
//
// Step 2 of the per-source DB split epic: the manifest type lands as a
// contract; no Swift code parses YAML at runtime yet. These tests
// verify the type's shape via JSON roundtripping (Codable conformance,
// optional-field tolerance, key naming). When step 3's YAML loader
// wires up (Yams or otherwise), the same type is what it decodes into.

@Suite("CorpusManifest: Codable contract for per-source manifest.yaml")
struct CorpusManifestShapeTests {
    @Test("Required-fields-only construction + JSON roundtrip")
    func requiredFieldsOnlyRoundtrip() throws {
        let manifest = Shared.Models.CorpusManifest(
            sourceId: "apple-documentation",
            displayName: "Apple Developer Documentation",
            corpusFolder: "apple-documentation",
            destinationDB: "apple-documentation",
            fetcher: .init(kind: "apple-docs-api"),
            indexer: .init(
                fileGlobs: ["documentation/**/*.json", "tutorials/**/*.json"],
                extractor: "Search.AppleDocsStrategy"
            ),
            capabilities: .init(
                searchers: ["text", "symbols"],
                operations: ["read-by-uri"]
            )
        )

        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(Shared.Models.CorpusManifest.self, from: encoded)

        #expect(decoded == manifest, "JSON roundtrip must preserve the manifest")
        #expect(decoded.description == nil)
        #expect(decoded.viewSources == nil)
        #expect(decoded.snapshotPolicy == nil)
        #expect(decoded.searchProperties == nil)
    }

    @Test("All-fields construction + JSON roundtrip (covers view-source + searchProperties + snapshotPolicy)")
    func allFieldsRoundtrip() throws {
        let manifest = Shared.Models.CorpusManifest(
            sourceId: "swift-org",
            displayName: "Swift Documentation",
            corpusFolder: "swift-documentation",
            destinationDB: "swift-documentation",
            fetcher: .init(kind: "git-clone", optionsJSON: #"{"repo":"https://github.com/swiftlang/swift-org-website"}"#),
            indexer: .init(
                fileGlobs: ["swift-org/**/*.md", "swift-book/**/*.md"],
                entryPoints: ["swift-org/index.md"],
                excludes: ["**/_metadata.md"],
                extractor: "Search.SwiftOrgStrategy"
            ),
            capabilities: .init(
                searchers: ["text", "symbols"],
                operations: ["read-by-uri"],
                metadata: ["hasGenerics": true, "hasAvailabilityAttrs": true]
            ),
            description: "Swift documentation + Swift Programming Language book.",
            viewSources: [.init(id: "swift-book", urlPrefix: "https://docs.swift.org/swift-book/")],
            snapshotPolicy: .init(staleAfterDays: 30, refetchOn: ["schema-bump"]),
            searchProperties: .init(searchQuality: 0.95, intentDefault: "reference", rankWeight: 0.95)
        )

        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(Shared.Models.CorpusManifest.self, from: encoded)

        #expect(decoded == manifest)
        #expect(decoded.viewSources?.count == 1)
        #expect(decoded.viewSources?.first?.id == "swift-book")
        #expect(decoded.capabilities.metadata["hasGenerics"] == true)
        #expect(decoded.snapshotPolicy?.staleAfterDays == 30)
        #expect(decoded.searchProperties?.searchQuality == 0.95)
    }

    @Test("Manifest decodes from a minimal canonical JSON literal (no optional keys present)")
    func decodesFromMinimalJSON() throws {
        let json = """
        {
          "sourceId": "hig",
          "displayName": "Human Interface Guidelines",
          "corpusFolder": "hig",
          "destinationDB": "hig",
          "fetcher": { "kind": "apple-docs-api" },
          "indexer": {
            "fileGlobs": ["pages/**/*.json"],
            "extractor": "Search.HIGStrategy"
          },
          "capabilities": {
            "searchers": ["text"],
            "operations": ["read-by-uri"],
            "metadata": { "hasMinPlatformVersion": true }
          }
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(Shared.Models.CorpusManifest.self, from: data)

        #expect(manifest.sourceId == "hig")
        #expect(manifest.destinationDB == "hig")
        #expect(manifest.fetcher.kind == "apple-docs-api")
        #expect(manifest.fetcher.optionsJSON == nil)
        #expect(manifest.indexer.fileGlobs == ["pages/**/*.json"])
        #expect(manifest.indexer.excludes == nil)
        #expect(manifest.capabilities.metadata["hasMinPlatformVersion"] == true)
        #expect(manifest.description == nil)
    }

    @Test("Capabilities.metadata absent flags default to absent (not false): allows narrow per-source manifests")
    func metadataAbsentMeansAbsent() {
        let manifest = Shared.Models.CorpusManifest(
            sourceId: "swift-evolution",
            displayName: "Swift Evolution",
            corpusFolder: "swift-evolution",
            destinationDB: "swift-evolution",
            fetcher: .init(kind: "git-clone"),
            indexer: .init(fileGlobs: ["proposals/**/*.md"], extractor: "Search.SwiftEvolutionStrategy"),
            capabilities: .init(
                searchers: ["text"],
                operations: ["read-by-uri"],
                metadata: ["hasMinSwiftVersion": true, "hasProposalNumber": true]
            )
        )

        // Absent flags should be absent in the dictionary, not false.
        #expect(manifest.capabilities.metadata["hasMinPlatformVersion"] == nil)
        #expect(manifest.capabilities.metadata["hasSampleCode"] == nil)
        #expect(manifest.capabilities.metadata.count == 2)
    }
}

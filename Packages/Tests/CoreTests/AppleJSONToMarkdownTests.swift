@testable import Core
import Foundation
import Testing

@Suite("AppleJSONToMarkdown.extractLinks coverage")
struct AppleJSONToMarkdownExtractLinksTests {
    // MARK: - Helpers

    private func extract(_ json: String) -> [String] {
        let data = Data(json.utf8)
        return AppleJSONToMarkdown.extractLinks(from: data).map(\.absoluteString)
    }

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        // Try with subdirectory first (when resources keep directory structure),
        // then without (when SwiftPM flattens .process resources).
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "AppleJSON") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        throw FixtureError.notFound(name)
    }

    private enum FixtureError: Error { case notFound(String) }

    private func minimalDoc(extra: String) -> String {
        """
        {
            "metadata": { "title": "X" },
            "abstract": [],
            \(extra)
        }
        """
    }

    // MARK: - C1: Hand-crafted unit tests

    @Test("Empty JSON input returns no URLs without crashing")
    func emptyJSONReturnsEmpty() {
        #expect(extract("").isEmpty)
        #expect(extract("{}").isEmpty)
        #expect(extract("not json at all").isEmpty)
    }

    @Test("Document with no references and no sections returns no URLs")
    func documentWithNoLinkSourcesReturnsEmpty() {
        let json = minimalDoc(extra: "\"references\": {}")
        #expect(extract(json).isEmpty)
    }

    @Test("References dict drives discovery")
    func referencesDictDrivesDiscovery() {
        let json = minimalDoc(extra: """
            "references": {
                "doc://X/documentation/Foo/Bar": {
                    "title": "Bar",
                    "url": "/documentation/Foo/Bar"
                },
                "doc://X/documentation/Foo/Baz-abc12": {
                    "title": "Baz",
                    "url": "/documentation/Foo/Baz-abc12"
                }
            }
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Foo/Bar"))
        #expect(urls.contains("https://developer.apple.com/documentation/Foo/Baz-abc12"))
        #expect(urls.count == 2)
    }

    @Test("Hash-disambiguated overload URLs are extracted")
    func hashDisambiguatedURLsExtracted() {
        let json = minimalDoc(extra: """
            "references": {
                "id1": { "url": "/documentation/Swift/Actor/withSerialExecutor(_:)-4ucv5" },
                "id2": { "url": "/documentation/Swift/Actor/withSerialExecutor(_:)-4ff11" }
            }
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Swift/Actor/withSerialExecutor(_:)-4ucv5"))
        #expect(urls.contains("https://developer.apple.com/documentation/Swift/Actor/withSerialExecutor(_:)-4ff11"))
    }

    @Test("Numeric-ID legacy struct field URLs are extracted")
    func numericIDStructFieldsExtracted() {
        let json = minimalDoc(extra: """
            "references": {
                "id1": { "url": "/documentation/Kernel/AppleLabel/1476100-al_boot0" },
                "id2": { "url": "/documentation/Kernel/AppleLabel/1476119-al_checksum" }
            }
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Kernel/AppleLabel/1476100-al_boot0"))
        #expect(urls.contains("https://developer.apple.com/documentation/Kernel/AppleLabel/1476119-al_checksum"))
    }

    @Test("Implementations index URLs are extracted")
    func implementationsIndexURLsExtracted() {
        let json = minimalDoc(extra: """
            "references": {
                "id1": { "url": "/documentation/Swift/AnyBidirectionalCollection/Sequence-Implementations" },
                "id2": { "url": "/documentation/Swift/AnyBidirectionalCollection/Collection-Implementations" }
            }
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Swift/AnyBidirectionalCollection/Sequence-Implementations"))
        #expect(urls.contains("https://developer.apple.com/documentation/Swift/AnyBidirectionalCollection/Collection-Implementations"))
    }

    @Test("Asset, image, and external archive references are filtered out")
    func nonDocumentationURLsFiltered() {
        let json = minimalDoc(extra: """
            "references": {
                "img1": { "url": "Swift-PageImage-card.png" },
                "img2": { "url": "/images/logo.svg" },
                "archive1": { "url": "https://developer.apple.com/library/archive/documentation/General/Foo.html" },
                "real": { "url": "/documentation/Foo/Bar" }
            }
        """)
        let urls = extract(json)
        #expect(urls == ["https://developer.apple.com/documentation/Foo/Bar"])
    }

    @Test("References with nil url are skipped without crash")
    func nilURLReferenceSkipped() {
        let json = minimalDoc(extra: """
            "references": {
                "noUrl": { "title": "Just a title" },
                "real":  { "url": "/documentation/Foo/Bar" }
            }
        """)
        let urls = extract(json)
        #expect(urls == ["https://developer.apple.com/documentation/Foo/Bar"])
    }

    @Test("Belt-and-braces: identifier in topicSections but absent from references resolves via doc:// fallback")
    func topicSectionFallback() {
        let json = minimalDoc(extra: """
            "topicSections": [
                {
                    "title": "Initializers",
                    "identifiers": ["doc://com.apple.Swift/documentation/Swift/Foo/init(_:)-abc12"]
                }
            ]
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Swift/Foo/init(_:)-abc12"))
    }

    @Test("seeAlsoSections walked")
    func seeAlsoSectionsWalked() {
        let json = minimalDoc(extra: """
            "seeAlsoSections": [
                {
                    "title": "See Also",
                    "identifiers": ["doc://X/documentation/Foo/Bar"]
                }
            ]
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Foo/Bar"))
    }

    @Test("relationshipsSections walked")
    func relationshipsSectionsWalked() {
        let json = minimalDoc(extra: """
            "relationshipsSections": [
                {
                    "title": "Conforms To",
                    "identifiers": ["doc://X/documentation/Foo/Conformee"]
                }
            ]
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Foo/Conformee"))
    }

    @Test("defaultImplementationsSections walked")
    func defaultImplementationsSectionsWalked() {
        let json = minimalDoc(extra: """
            "defaultImplementationsSections": [
                {
                    "title": "Default Implementations",
                    "identifiers": ["doc://X/documentation/Foo/SomeProtocol-Implementations"]
                }
            ]
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Foo/SomeProtocol-Implementations"))
    }

    @Test("Inline references inside paragraph content are extracted")
    func inlineReferencesInProseExtracted() {
        let json = minimalDoc(extra: """
            "primaryContentSections": [
                {
                    "kind": "content",
                    "content": [
                        {
                            "type": "paragraph",
                            "inlineContent": [
                                { "type": "text", "text": "See also " },
                                { "type": "reference", "identifier": "doc://X/documentation/Foo/InlineLink" },
                                { "type": "text", "text": " for details." }
                            ]
                        }
                    ]
                }
            ],
            "references": {
                "doc://X/documentation/Foo/InlineLink": {
                    "url": "/documentation/Foo/InlineLink"
                }
            }
        """)
        let urls = extract(json)
        #expect(urls.contains("https://developer.apple.com/documentation/Foo/InlineLink"))
    }

    @Test("Same URL referenced from multiple sections is returned exactly once")
    func dedupAcrossSources() {
        let json = minimalDoc(extra: """
            "references": {
                "doc://X/documentation/Foo/Bar": {
                    "url": "/documentation/Foo/Bar"
                }
            },
            "topicSections": [
                {
                    "title": "Topics",
                    "identifiers": ["doc://X/documentation/Foo/Bar"]
                }
            ],
            "seeAlsoSections": [
                {
                    "title": "See",
                    "identifiers": ["doc://X/documentation/Foo/Bar"]
                }
            ],
            "relationshipsSections": [
                {
                    "title": "Conforms",
                    "identifiers": ["doc://X/documentation/Foo/Bar"]
                }
            ]
        """)
        let urls = extract(json)
        let count = urls.filter { $0 == "https://developer.apple.com/documentation/Foo/Bar" }.count
        #expect(count == 1)
    }

    // MARK: - C2: Real Apple JSON fixture tests

    @Test("Fixture: AnyBidirectionalCollection — all 5 hash-disambiguated init overloads extracted")
    func fixtureAnyBidirectionalCollection_initOverloads() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("AnyBidirectionalCollection")).map(\.absoluteString)
        let expected = [
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/init(_:)-1hwm5",
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/init(_:)-2kvez",
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/init(_:)-4hewp",
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/init(_:)-5lybd",
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/init(_:)-61joz",
        ]
        for url in expected {
            #expect(urls.contains(url), "missing: \(url)")
        }
    }

    @Test("Fixture: AnyBidirectionalCollection — all 3 -implementations URLs extracted")
    func fixtureAnyBidirectionalCollection_implementationsIndexes() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("AnyBidirectionalCollection")).map(\.absoluteString)
        let expected = [
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/sequence-implementations",
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/collection-implementations",
            "https://developer.apple.com/documentation/swift/anybidirectionalcollection/bidirectionalcollection-implementations",
        ]
        for url in expected {
            #expect(urls.contains(url), "missing: \(url)")
        }
    }

    @Test("Fixture: Kernel/AppleLabel — all 8 al_* numeric-ID struct fields extracted")
    func fixtureKernelAppleLabel_structFields() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("Kernel_AppleLabel")).map(\.absoluteString)
        let expected = [
            "https://developer.apple.com/documentation/kernel/applelabel/1476100-al_boot0",
            "https://developer.apple.com/documentation/kernel/applelabel/1476102-al_boot1",
            "https://developer.apple.com/documentation/kernel/applelabel/1476119-al_checksum",
            "https://developer.apple.com/documentation/kernel/applelabel/1476155-al_flags",
            "https://developer.apple.com/documentation/kernel/applelabel/1476151-al_magic",
            "https://developer.apple.com/documentation/kernel/applelabel/1476124-al_offset",
            "https://developer.apple.com/documentation/kernel/applelabel/1476117-al_size",
            "https://developer.apple.com/documentation/kernel/applelabel/1476108-al_type",
        ]
        for url in expected {
            #expect(urls.contains(url), "missing: \(url)")
        }
    }

    @Test("Fixture: Swift/Actor — both withSerialExecutor disambiguated overloads extracted")
    func fixtureSwiftActor_withSerialExecutorVariants() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("Swift_Actor")).map(\.absoluteString)
        let expected = [
            "https://developer.apple.com/documentation/swift/actor/withserialexecutor(_:)-4ucv5",
            "https://developer.apple.com/documentation/swift/actor/withserialexecutor(_:)-4ff11",
        ]
        for url in expected {
            #expect(urls.contains(url), "missing: \(url)")
        }
    }

    @Test("Fixture: Foundation/NSCalendar — discovers ≥ 100 documentation URLs")
    func fixtureNSCalendar_yieldsLargeURLSet() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("Foundation_NSCalendar")).map(\.absoluteString)
        // NSCalendar references dict has 103 /documentation/ URLs;
        // dedup should keep us above 100 even after collapsing duplicates.
        #expect(urls.count >= 100, "got only \(urls.count) URLs")
        #expect(urls.allSatisfy { $0.hasPrefix("https://developer.apple.com/documentation/") })
    }

    @Test("Fixture: CoreFoundation root — all topicSections framework children discovered")
    func fixtureCoreFoundationRoot_subFrameworkLinks() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("CoreFoundation_Root")).map(\.absoluteString)
        // Should find at least 90 doc URLs; refs has 95.
        #expect(urls.count >= 90, "got only \(urls.count) URLs")
    }

    @Test("Fixture: Swift/Sequence — protocol page yields ≥ 150 URLs")
    func fixtureSwiftSequence_protocolPageYieldsManyURLs() throws {
        let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture("Swift_Sequence")).map(\.absoluteString)
        #expect(urls.count >= 150, "got only \(urls.count) URLs")
    }

    @Test("All fixture URLs are valid documentation paths (no images, no external)")
    func allFixtureURLsAreDocPaths() throws {
        for name in [
            "AnyBidirectionalCollection",
            "Kernel_AppleLabel",
            "Swift_Actor",
            "Foundation_NSCalendar",
            "CoreFoundation_Root",
            "Swift_Sequence",
        ] {
            let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture(name)).map(\.absoluteString)
            for url in urls {
                #expect(
                    url.hasPrefix("https://developer.apple.com/documentation/"),
                    "non-documentation URL slipped through in \(name): \(url)"
                )
            }
        }
    }

    @Test("All extractLinks results are unique")
    func extractLinksReturnsUniqueURLs() throws {
        for name in [
            "AnyBidirectionalCollection",
            "Kernel_AppleLabel",
            "Swift_Actor",
            "Foundation_NSCalendar",
            "CoreFoundation_Root",
            "Swift_Sequence",
        ] {
            let urls = try AppleJSONToMarkdown.extractLinks(from: loadFixture(name)).map(\.absoluteString)
            #expect(
                urls.count == Set(urls).count,
                "\(name) returned duplicates: \(urls.count) total, \(Set(urls).count) unique"
            )
        }
    }

    // MARK: - C3 / C4: Regression coverage — every URL in references must be extracted

    @Test("Every documentation URL in fixture references dict appears in extractLinks output")
    func everyReferencesDictDocURLDiscovered() throws {
        for name in [
            "AnyBidirectionalCollection",
            "Kernel_AppleLabel",
            "Swift_Actor",
            "Foundation_NSCalendar",
            "CoreFoundation_Root",
            "Swift_Sequence",
        ] {
            let data = try loadFixture(name)
            let extracted = Set(AppleJSONToMarkdown.extractLinks(from: data).map(\.absoluteString))

            // Re-decode raw JSON to enumerate references manually and form the
            // expected set: every reference URL that starts with /documentation/.
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let refs = json["references"] as? [String: [String: Any]]
            else {
                Issue.record("could not parse references in \(name)")
                continue
            }
            var expected = Set<String>()
            for ref in refs.values {
                guard let url = ref["url"] as? String, url.hasPrefix("/documentation/") else { continue }
                expected.insert("https://developer.apple.com\(url)")
            }
            let missing = expected.subtracting(extracted)
            #expect(
                missing.isEmpty,
                "\(name): \(missing.count) references-dict URLs missing from extractLinks output. First 3: \(Array(missing.prefix(3)))"
            )
        }
    }
}

import Foundation
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

// MARK: - Canonical DocKind mapping

/// 2026-05-27 post-#1056 mechanical hunt: pre-cull
/// `Search.Classify.kind(source:)` had a 5-arm fallback switch
/// returning per-source DocKind values when the registry-supplied
/// dict was empty. Post-cull the switch is gone (the 5 arms were
/// dead-on-prod — every production caller supplies the dict via
/// `Search.SourceLookup.docKindRawValuesByID`). Tests reproduce the
/// canonical mapping inline so the classifier's behavioural contract
/// stays pinned without relying on a default-empty parameter that
/// hides the per-source mapping.
private let canonicalDocKindByID: [String: String] = [
    Shared.Constants.SourcePrefix.swiftEvolution: "evolutionProposal",
    Shared.Constants.SourcePrefix.swiftBook: "swiftBook",
    Shared.Constants.SourcePrefix.swiftOrg: "swiftOrgDoc",
    Shared.Constants.SourcePrefix.hig: "hig",
    Shared.Constants.SourcePrefix.appleArchive: "archive",
]

// MARK: - DocKind taxonomy (#192 section C1)

@Suite("Search.Classify.kind")
struct DocKindClassifyTests {
    // MARK: Single-source branches

    @Test("swift-evolution → evolutionProposal")
    func evolutionSource() {
        #expect(Search.Classify.kind(source: "swift-evolution", docKindByID: canonicalDocKindByID) == .evolutionProposal)
        #expect(Search.Classify.kind(source: "swift-evolution", structuredKind: "anything", docKindByID: canonicalDocKindByID) == .evolutionProposal)
    }

    @Test("swift-book → swiftBook")
    func swiftBookSource() {
        #expect(Search.Classify.kind(source: "swift-book", docKindByID: canonicalDocKindByID) == .swiftBook)
    }

    @Test("swift-org → swiftOrgDoc")
    func swiftOrgSource() {
        #expect(Search.Classify.kind(source: "swift-org", docKindByID: canonicalDocKindByID) == .swiftOrgDoc)
    }

    @Test("hig → hig")
    func higSource() {
        #expect(Search.Classify.kind(source: "hig", docKindByID: canonicalDocKindByID) == .hig)
    }

    @Test("apple-archive → archive")
    func archiveSource() {
        #expect(Search.Classify.kind(source: "apple-archive", docKindByID: canonicalDocKindByID) == .archive)
    }

    @Test("Unknown source → unknown")
    func unknownSource() {
        #expect(Search.Classify.kind(source: "mystery-source", docKindByID: canonicalDocKindByID) == .unknown)
        #expect(Search.Classify.kind(source: "", docKindByID: canonicalDocKindByID) == .unknown)
    }

    // MARK: apple-docs structured-kind branches

    @Test("apple-docs + declaration kinds → symbolPage")
    func appleDocsSymbolPage() {
        let declKinds = [
            "protocol", "class", "struct", "enum",
            "function", "property", "method", "operator",
            "typealias", "macro", "framework",
        ]
        for declKind in declKinds {
            #expect(
                Search.Classify.kind(source: "apple-docs", structuredKind: declKind, docKindByID: canonicalDocKindByID) == .symbolPage,
                "Expected \(declKind) → symbolPage"
            )
        }
    }

    @Test("apple-docs + article/collection → article")
    func appleDocsArticle() {
        #expect(Search.Classify.kind(source: "apple-docs", structuredKind: "article", docKindByID: canonicalDocKindByID) == .article)
        #expect(Search.Classify.kind(source: "apple-docs", structuredKind: "collection", docKindByID: canonicalDocKindByID) == .article)
    }

    @Test("apple-docs + tutorial → tutorial")
    func appleDocsTutorial() {
        #expect(Search.Classify.kind(source: "apple-docs", structuredKind: "tutorial", docKindByID: canonicalDocKindByID) == .tutorial)
    }

    @Test("apple-docs + no structured kind → unknown")
    func appleDocsNoStructuredKind() {
        #expect(Search.Classify.kind(source: "apple-docs", docKindByID: canonicalDocKindByID) == .unknown)
        #expect(Search.Classify.kind(source: "apple-docs", structuredKind: nil, docKindByID: canonicalDocKindByID) == .unknown)
    }

    @Test("apple-docs + unrecognized structured kind → unknown")
    func appleDocsUnknownStructuredKind() {
        #expect(Search.Classify.kind(source: "apple-docs", structuredKind: "widget-gadget", docKindByID: canonicalDocKindByID) == .unknown)
        #expect(Search.Classify.kind(source: "apple-docs", structuredKind: "", docKindByID: canonicalDocKindByID) == .unknown)
    }

    // MARK: sample-code URI override

    @Test("apple-docs + URI containing /samplecode/ → sampleCode")
    func sampleCodeURIOverride() {
        // URI path override wins regardless of structured kind.
        #expect(
            Search.Classify.kind(
                source: "apple-docs",
                structuredKind: "article",
                uriPath: "apple-docs://swiftui/documentation/samplecode/foo",
                docKindByID: canonicalDocKindByID
            ) == .sampleCode
        )
        #expect(
            Search.Classify.kind(
                source: "apple-docs",
                structuredKind: "struct",
                uriPath: "/documentation/samplecode/bar",
                docKindByID: canonicalDocKindByID
            ) == .sampleCode
        )
    }

    @Test("apple-docs with /samplecode/ but unknown structured kind still → sampleCode")
    func sampleCodeURIOverrideWithoutStructuredKind() {
        #expect(
            Search.Classify.kind(
                source: "apple-docs",
                uriPath: "apple-docs://swiftui/samplecode/navigation",
                docKindByID: canonicalDocKindByID
            ) == .sampleCode
        )
    }

    @Test("URI path override is case-insensitive")
    func sampleCodeURICaseInsensitive() {
        #expect(
            Search.Classify.kind(
                source: "apple-docs",
                structuredKind: "article",
                uriPath: "https://developer.apple.com/documentation/SampleCode/foo",
                docKindByID: canonicalDocKindByID
            ) == .sampleCode
        )
    }

    @Test("Non-apple-docs source ignores /samplecode/ in URI")
    func sampleCodeURIOnlyAppliesToAppleDocs() {
        // swift-evolution with a /samplecode/ path still classifies as evolutionProposal.
        // This is defensive — shouldn't happen in practice but shouldn't misclassify
        // if it does.
        #expect(
            Search.Classify.kind(
                source: "swift-evolution",
                uriPath: "weird://something/samplecode/here",
                docKindByID: canonicalDocKindByID
            ) == .evolutionProposal
        )
    }

    // MARK: Constants parity — taxonomy stays in sync with Shared.Constants.SourcePrefix

    @Test("Classifier recognises every source prefix that exists in Shared.Constants")
    func allKnownSourcePrefixes() {
        let prefixes: [(String, Search.DocKind)] = [
            (Shared.Constants.SourcePrefix.swiftEvolution, .evolutionProposal),
            (Shared.Constants.SourcePrefix.swiftBook, .swiftBook),
            (Shared.Constants.SourcePrefix.swiftOrg, .swiftOrgDoc),
            (Shared.Constants.SourcePrefix.hig, .hig),
            (Shared.Constants.SourcePrefix.appleArchive, .archive),
        ]
        for (prefix, expected) in prefixes {
            #expect(
                Search.Classify.kind(source: prefix, docKindByID: canonicalDocKindByID) == expected,
                "Source \(prefix) should map to \(expected)"
            )
        }
    }
}

// MARK: - DocKind enum integrity

@Suite("Search.DocKind enum")
struct DocKindEnumTests {
    @Test("Every case has the expected raw string")
    func rawValues() {
        let expected: [Search.DocKind: String] = [
            .symbolPage: "symbolPage",
            .article: "article",
            .tutorial: "tutorial",
            .sampleCode: "sampleCode",
            .evolutionProposal: "evolutionProposal",
            .swiftBook: "swiftBook",
            .swiftOrgDoc: "swiftOrgDoc",
            .hig: "hig",
            .archive: "archive",
            .unknown: "unknown",
        ]
        for (kind, raw) in expected {
            #expect(kind.rawValue == raw, "\(kind) rawValue must be \(raw)")
        }
    }

    @Test("allCases has exactly 10 entries")
    func caseCount() {
        #expect(Search.DocKind.allCases.count == 10)
    }

    @Test("Raw strings are stable (taxonomy lock)")
    func stableRawStrings() {
        // If any future commit accidentally renames a case, this test fails.
        // The raw strings are persisted in `search.db` rows; renaming breaks
        // every existing DB.
        let allRaws = Set(Search.DocKind.allCases.map(\.rawValue))
        #expect(allRaws == [
            "symbolPage", "article", "tutorial", "sampleCode",
            "evolutionProposal", "swiftBook", "swiftOrgDoc",
            "hig", "archive", "unknown",
        ])
    }
}

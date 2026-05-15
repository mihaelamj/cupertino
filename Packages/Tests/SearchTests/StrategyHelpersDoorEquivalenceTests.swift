import Foundation
@testable import Search
import SearchModels
import SharedConstants
import Testing

// MARK: - #588 door-equivalence (tier A / B / C) tests
//
// Truth-table coverage for the pure helpers that drive the import-time
// door check in `Search.Strategies.AppleDocs`. Pure functions, no I/O —
// the unit tests pin the equivalence semantics so a future refactor
// can't silently relax tier C into tier B (which would lose content)
// or tighten tier B into tier C (which would surface 24K false-
// positive collisions on the existing case-variant corpus).

@Suite("Search.StrategyHelpers.canonicalTitleForEquivalence (#588)")
struct CanonicalTitleForEquivalenceTests {
    typealias SUT = Search.StrategyHelpers

    @Test("HTML entity decode collapses byte-different titles that mean the same thing")
    func htmlEntityDecode() {
        let raw = SUT.canonicalTitleForEquivalence("AsyncSequence&lt;Element&gt;")
        let unraw = SUT.canonicalTitleForEquivalence("AsyncSequence<Element>")
        #expect(raw == unraw)
        #expect(raw == "asyncsequence<element>")
    }

    @Test("Strips site-wide ' | Apple Developer Documentation' suffix")
    func stripsSiteSuffix() {
        let withSuffix = SUT.canonicalTitleForEquivalence("View | Apple Developer Documentation")
        let bare = SUT.canonicalTitleForEquivalence("View")
        #expect(withSuffix == bare)
        #expect(bare == "view")
    }

    @Test("Lowercases and collapses internal whitespace")
    func whitespaceCanonicalization() {
        #expect(SUT.canonicalTitleForEquivalence("  Integrating   Accessibility \t Into Your App  ")
            == "integrating accessibility into your app")
    }

    @Test("Space- and underscore-bearing titles do NOT silently equate (only whitespace, not punctuation, is collapsed)")
    func spacesVsUnderscoresStayDistinct() {
        let spaces = SUT.canonicalTitleForEquivalence("integrating accessibility into your app")
        let unders = SUT.canonicalTitleForEquivalence("integrating_accessibility_into_your_app")
        // These are the 2 titles for the lone Accessibility tier-C
        // cluster in the audit. They produce DIFFERENT canonical
        // forms here, so they still classify as tier C unless title
        // canonicalization is extended further. (#588 step-3 leaves
        // them as tier C; the title-canon refinement is its own
        // followup. The point of this test is to pin the current
        // behaviour explicitly so any later change is intentional.)
        #expect(spaces != unders)
    }

    @Test("Empty / whitespace-only titles canonicalize to empty string")
    func emptyTitleCanonicalizesToEmpty() {
        #expect(SUT.canonicalTitleForEquivalence("") == "")
        #expect(SUT.canonicalTitleForEquivalence("   \t\n  ") == "")
    }

    @Test("Multiple HTML entities in one title")
    func multipleEntities() {
        let mixed = SUT.canonicalTitleForEquivalence("Pair&lt;A&amp;B&gt;")
        #expect(mixed == "pair<a&b>")
    }
}

@Suite("Search.StrategyHelpers.classifyDoorEncounter (#588 tier A / B / C)")
struct ClassifyDoorEncounterTests {
    typealias SUT = Search.StrategyHelpers

    @Test("Tier A: identical contentHash → benignByteIdentical")
    func tierAByteIdentical() {
        let prior = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "abc123")
        let incoming = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "abc123")
        #expect(SUT.classifyDoorEncounter(prior: prior, incoming: incoming) == .benignByteIdentical)
    }

    @Test("Tier A wins even when titles also match (cheapest path)")
    func tierAWinsOverTierB() {
        let prior = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "abc123")
        let incoming = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "abc123")
        #expect(SUT.classifyDoorEncounter(prior: prior, incoming: incoming) == .benignByteIdentical)
    }

    @Test("Tier B: same canonical title + different contentHash → benignTitleMatchWithDrift")
    func tierBDrift() {
        // The 24K case-variant clusters from the corpus audit: Apple
        // serves StoreKit/foo and storekit/foo as the same logical
        // page, but crawl-time noise (timestamps, rendering nondetermism)
        // produces different content hashes.
        let prior = SUT.SeenURIRecord(canonicalTitle: "init(rawvalue:)", contentHash: "hash_from_crawl_1")
        let incoming = SUT.SeenURIRecord(canonicalTitle: "init(rawvalue:)", contentHash: "hash_from_crawl_2")
        #expect(SUT.classifyDoorEncounter(prior: prior, incoming: incoming) == .benignTitleMatchWithDrift)
    }

    @Test("Tier C: different canonical titles → malignantTitleMismatch")
    func tierCCollision() {
        // The 1 remaining true tier-C cluster after step 1: PHASE
        // SoundEvent — one URL variant's crawled title is the wrong
        // method ("seek(...)") for the URL ("start(...)"). Two
        // different Apple pages collapsed to the same URI; surfacing
        // this loud is principle 3.
        let prior = SUT.SeenURIRecord(canonicalTitle: "start(at:completion:)", contentHash: "h1")
        let incoming = SUT.SeenURIRecord(canonicalTitle: "seek(to:resumeat:completion:)", contentHash: "h2")
        #expect(SUT.classifyDoorEncounter(prior: prior, incoming: incoming) == .malignantTitleMismatch)
    }

    @Test("Empty contentHash on either side is NOT treated as tier A (#588 — empty hash means we lack the evidence)")
    func emptyHashSkipsTierA() {
        let priorNoHash = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "")
        let incomingHashed = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "abc")
        #expect(SUT.classifyDoorEncounter(prior: priorNoHash, incoming: incomingHashed) == .benignTitleMatchWithDrift)

        let priorHashed = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "abc")
        let incomingNoHash = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "")
        #expect(SUT.classifyDoorEncounter(prior: priorHashed, incoming: incomingNoHash) == .benignTitleMatchWithDrift)

        let bothEmpty = SUT.SeenURIRecord(canonicalTitle: "different", contentHash: "")
        let bothEmpty2 = SUT.SeenURIRecord(canonicalTitle: "view", contentHash: "")
        #expect(SUT.classifyDoorEncounter(prior: bothEmpty, incoming: bothEmpty2) == .malignantTitleMismatch)
    }

    @Test("Classifier is deterministic — same inputs always produce the same output")
    func deterministic() {
        let prior = SUT.SeenURIRecord(canonicalTitle: "x", contentHash: "h")
        let incoming = SUT.SeenURIRecord(canonicalTitle: "y", contentHash: "h2")
        for _ in 0 ..< 50 {
            #expect(SUT.classifyDoorEncounter(prior: prior, incoming: incoming) == .malignantTitleMismatch)
        }
    }
}

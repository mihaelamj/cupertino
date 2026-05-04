import Foundation
@testable import Search
import Testing

// Covers H5 from #192: `DocsSourceCandidateFetcher` against a fixture
// search.db. Verifies that the fetcher scopes to its source, adapts
// `Search.Result` fields into `SmartCandidate` correctly, respects `limit`,
// and reports `sourceName`.

private func seedIndex() async throws -> (Search.Index, URL) {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("docs-fetcher-\(UUID().uuidString).db")
    let index = try await Search.Index(dbPath: dbPath)

    // Two docs in apple-docs source, plus one in swift-evolution so we can
    // verify source scoping.
    try await index.indexDocument(
        uri: "apple-docs://swiftui/view",
        source: "apple-docs",
        framework: "swiftui",
        title: "View",
        content: "A SwiftUI view protocol.",
        filePath: "/tmp/view.md",
        contentHash: "h1",
        lastCrawled: Date()
    )
    try await index.indexDocument(
        uri: "apple-docs://swiftui/animation",
        source: "apple-docs",
        framework: "swiftui",
        title: "Animation",
        content: "SwiftUI animation APIs.",
        filePath: "/tmp/anim.md",
        contentHash: "h2",
        lastCrawled: Date()
    )
    try await index.indexDocument(
        uri: "swift-evolution://SE-0306",
        source: "swift-evolution",
        framework: nil,
        title: "Actors",
        content: "Swift actors proposal.",
        filePath: "/tmp/se306.md",
        contentHash: "h3",
        lastCrawled: Date()
    )
    return (index, dbPath)
}

@Suite("Search.DocsSourceCandidateFetcher (#192 H5)")
struct DocsSourceCandidateFetcherTests {
    @Test("Source scoping: fetcher for apple-docs never surfaces swift-evolution rows")
    func scopesToDeclaredSource() async throws {
        let (index, dbPath) = try await seedIndex()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let fetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: index,
            source: "apple-docs"
        )

        // A term present in both apple-docs AND swift-evolution content.
        let candidates = try await fetcher.fetch(question: "Swift", limit: 10)
        await index.disconnect()

        #expect(!candidates.isEmpty)
        #expect(candidates.allSatisfy { $0.source == "apple-docs" })
        #expect(!candidates.contains { $0.identifier.contains("SE-0306") })
    }

    @Test("Adapter fills identifier, title, chunk, rawScore, and source correctly")
    func adaptsSearchResultFields() async throws {
        let (index, dbPath) = try await seedIndex()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let fetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: index,
            source: "apple-docs"
        )
        let candidates = try await fetcher.fetch(question: "animation", limit: 5)
        await index.disconnect()

        let hit = try #require(candidates.first { $0.identifier == "apple-docs://swiftui/animation" })
        #expect(hit.source == "apple-docs")
        #expect(hit.title == "Animation")
        #expect(!hit.chunk.isEmpty, "summary is the chunk surface — must not be empty")
        // BM25 is negative; fetcher inverts to make higher = better. Positive
        // rawScore confirms the inversion happened.
        #expect(hit.rawScore > 0)
        #expect(hit.metadata["framework"] == "swiftui")
    }

    @Test("sourceName reflects the configured source")
    func sourceNameReflectsConfig() async throws {
        let (index, dbPath) = try await seedIndex()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let appleFetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: index,
            source: "apple-docs"
        )
        let evolutionFetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: index,
            source: "swift-evolution"
        )
        await index.disconnect()

        #expect(appleFetcher.sourceName == "apple-docs")
        #expect(evolutionFetcher.sourceName == "swift-evolution")
    }

    @Test("Limit caps the number of candidates")
    func limitIsRespected() async throws {
        let (index, dbPath) = try await seedIndex()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let fetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: index,
            source: "apple-docs"
        )

        let limited = try await fetcher.fetch(question: "swift", limit: 1)
        let unlimited = try await fetcher.fetch(question: "swift", limit: 10)
        await index.disconnect()

        #expect(limited.count <= 1)
        #expect(unlimited.count >= limited.count)
    }
}

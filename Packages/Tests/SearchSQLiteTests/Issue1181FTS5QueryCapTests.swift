import Foundation
import LoggingModels
import SearchModels
@testable import SearchSQLite
import Testing

// #1181: cupertino search is a plain SQLite FTS5 keyword index, not a semantic
// retriever. `sanitizeFTS5Query` caps the number of terms forwarded to the
// `MATCH` so a pathological multi-KB query (e.g. an AI agent pasting prose)
// cannot blow FTS5's expression-tree limits. Excess terms are dropped, not
// errored, so the call still returns useful results.
@Suite("#1181 — FTS5 query term cap")
struct Issue1181FTS5QueryCapTests {
    @MainActor
    private static func makeIndex() async throws -> Search.Index {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts5-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbPath = tmp.appendingPathComponent("test.db")
        return try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
    }

    @Test("caps a pathological query at maxFTS5QueryTerms")
    @MainActor
    func capsLongQuery() async throws {
        let index = try await Self.makeIndex()
        let longQuery = Array(repeating: "view", count: 200).joined(separator: " ")
        let result = index.sanitizeFTS5Query(longQuery)
        #expect(result.split(separator: " ").count == Search.Index.maxFTS5QueryTerms)
    }

    @Test("leaves a short keyword query untouched")
    @MainActor
    func shortQueryUnaffected() async throws {
        let index = try await Self.makeIndex()
        let result = index.sanitizeFTS5Query("URLSession NavigationStack")
        #expect(result == "\"URLSession\" \"NavigationStack\"")
    }
}

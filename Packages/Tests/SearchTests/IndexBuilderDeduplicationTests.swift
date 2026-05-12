import Foundation
@testable import Search
import SharedConstants
import SharedCore
import SharedModels
import Testing

// Regression coverage for `Search.IndexBuilder.deduplicateDocFilesByCanonicalURL`
// (#200). The dedup helper reads `crawledAt` out of saved
// `StructuredDocumentationPage` JSON files to break ties between case-axis
// URL duplicates. If the JSON decoder isn't configured with `.iso8601` the
// decode silently fails, the helper falls back to filesystem mtime, and
// dedup picks the wrong file when mtime and crawledAt diverge (e.g. after
// a corpus copy or git checkout that shuffles mtimes).

@Suite("Search.IndexBuilder.deduplicateDocFilesByCanonicalURL (#200)", .serialized)
struct IndexBuilderDeduplicationTests {
    @Test("Two files with same canonical URL: keeps the one with newer crawledAt even when its mtime is older")
    func keepsNewestByCrawledAtNotMtime() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-dedup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        // Two distinct on-disk files that both point to the same canonical
        // Apple URL via their `page.url` field. This simulates the real
        // production case where successive crawls or a URL-canonicalization
        // change left two on-disk copies of the same page (e.g. underscore
        // vs dash framework variants pre-fix). Distinct filenames so the test
        // is FS-case-insensitivity-independent (macOS HFS+ default would
        // otherwise collapse them before dedup runs).
        let sharedCanonicalURL = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/list"))

        let older = try writeFixtureDoc(
            url: sharedCanonicalURL,
            crawledAt: Date(timeIntervalSince1970: 1700000000),
            into: docsDir,
            framework: "swiftui",
            name: "list"
        )
        let newer = try writeFixtureDoc(
            url: sharedCanonicalURL,
            crawledAt: Date(timeIntervalSince1970: 1800000000),
            into: docsDir,
            framework: "swiftui",
            name: "list-copy"
        )

        // Sabotage filesystem mtime: bump the older file's mtime to be newer
        // than the actually-newer file's mtime. If dedup falls back to mtime
        // (i.e. the JSON decode silently fails because `.iso8601` isn't set),
        // it would now incorrectly keep `older`. With `.iso8601` working,
        // dedup reads `crawledAt` from the JSON directly and keeps `newer`.
        let inFuture = Date().addingTimeInterval(86400)
        try FileManager.default.setAttributes(
            [.modificationDate: inFuture],
            ofItemAtPath: older.path
        )

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let builder = Search.IndexBuilder(
            searchIndex: index,
            metadata: nil,
            docsDirectory: docsDir,
            indexSampleCode: false
        )

        let result = try await builder.deduplicateDocFilesByCanonicalURL([older, newer])
        #expect(result == [newer])
    }

    @Test("Single file with no duplicates passes through unchanged")
    func singleFilePassesThrough() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-dedup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        let file = try writeFixtureDoc(
            url: #require(URL(string: "https://developer.apple.com/documentation/swiftui/list")),
            crawledAt: Date(),
            into: docsDir,
            framework: "swiftui",
            name: "list"
        )

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let builder = Search.IndexBuilder(
            searchIndex: index,
            metadata: nil,
            docsDirectory: docsDir,
            indexSampleCode: false
        )

        let result = try await builder.deduplicateDocFilesByCanonicalURL([file])
        #expect(result == [file])
    }

    @Test("Distinct canonical URLs both survive (no false-positive dedup)")
    func distinctURLsBothSurvive() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-dedup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        let listView = try writeFixtureDoc(
            url: #require(URL(string: "https://developer.apple.com/documentation/swiftui/list")),
            crawledAt: Date(),
            into: docsDir,
            framework: "swiftui",
            name: "list"
        )
        let textField = try writeFixtureDoc(
            url: #require(URL(string: "https://developer.apple.com/documentation/swiftui/textfield")),
            crawledAt: Date(),
            into: docsDir,
            framework: "swiftui",
            name: "textfield"
        )

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let builder = Search.IndexBuilder(
            searchIndex: index,
            metadata: nil,
            docsDirectory: docsDir,
            indexSampleCode: false
        )

        let result = try await builder.deduplicateDocFilesByCanonicalURL([listView, textField])
        #expect(Set(result) == Set([listView, textField]))
    }

    @Test("loadStructuredPage: decoder is configured with .iso8601 (regression for codex review on #264)")
    func loadStructuredPageDecodesIso8601() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-dedup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        let knownDate = Date(timeIntervalSince1970: 1750000000)
        let file = try writeFixtureDoc(
            url: #require(URL(string: "https://developer.apple.com/documentation/swiftui/view")),
            crawledAt: knownDate,
            into: docsDir,
            framework: "swiftui",
            name: "view"
        )

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let builder = Search.IndexBuilder(
            searchIndex: index,
            metadata: nil,
            docsDirectory: docsDir,
            indexSampleCode: false
        )

        let page = try #require(await builder.loadStructuredPage(from: file))
        #expect(page.crawledAt == knownDate)
        // canonicalDocumentationURL should also use the page.url branch, not
        // the path-based fallback. Asserting it returns the lowercased Apple URL.
        let canonical = await builder.canonicalDocumentationURL(for: file)
        #expect(canonical == "https://developer.apple.com/documentation/swiftui/view")
    }
}

private func writeFixtureDoc(
    url: URL,
    crawledAt: Date,
    into directory: URL,
    framework: String,
    name: String
) throws -> URL {
    let frameworkDir = directory.appendingPathComponent(framework)
    try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)

    let page = Shared.Models.StructuredDocumentationPage(
        url: url,
        title: "Sample",
        kind: .struct,
        source: .appleJSON,
        abstract: nil,
        declaration: nil,
        overview: nil,
        sections: [],
        codeExamples: [],
        language: nil,
        crawledAt: crawledAt,
        contentHash: "test-hash-\(UUID().uuidString)"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(page)

    let fileURL = frameworkDir.appendingPathComponent("\(name).json")
    try data.write(to: fileURL)
    return fileURL
}

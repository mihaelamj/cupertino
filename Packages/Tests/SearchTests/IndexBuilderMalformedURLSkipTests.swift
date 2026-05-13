import Foundation
@testable import Search
import SharedConstants
import SharedCore
import SharedModels
import Testing

// Covers the malformed-URL skip path in
// `Search.AppleDocsStrategy.indexFromMetadata(into:metadata:progress:)`.
//
// The skip fires when a row in `CrawlMetadata.pages` has a URL key that
// `URL(string:)` cannot parse.  We use the empty string as the reliably-
// malformed key: `URL(string: "")` returns nil on macOS 14+ and the first
// test pins that assumption so the rest of the suite is honest about why
// it works.

@Suite("Search.AppleDocsStrategy malformed-URL skip", .serialized)
struct IndexBuilderMalformedURLSkipTests {
    @Test("Sanity: URL(string: \"\") is nil on this platform")
    func emptyStringIsNilURL() {
        // The whole suite depends on this.  If a future macOS makes empty
        // strings parse to a non-nil URL the suite needs a different
        // malformed-key strategy.
        #expect(URL(string: "") == nil)
    }

    @Test("Indexes the good row and skips the malformed-URL row")
    func skipsMalformedURLRowKeepsGoodRow() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-malformed-url-skip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        // Both files must exist on disk: the metadata-driven path reads file contents,
        // so the file must be present or the earlier "file does not exist" skip fires
        // before the URL-parse check is reached.
        let goodFile = docsDir.appendingPathComponent("good.md")
        let badFile = docsDir.appendingPathComponent("bad.md")
        try "# Good page\n\nHello, well-formed.".write(to: goodFile, atomically: true, encoding: .utf8)
        try "# Bad page\n\nHello, malformed-key.".write(to: badFile, atomically: true, encoding: .utf8)

        let goodMetadata = Shared.Models.PageMetadata(
            url: "https://developer.apple.com/documentation/swiftui/list",
            framework: "swiftui",
            filePath: goodFile.path,
            contentHash: "good-hash",
            depth: 0
        )
        let badMetadata = Shared.Models.PageMetadata(
            url: "",
            framework: "swiftui",
            filePath: badFile.path,
            contentHash: "bad-hash",
            depth: 0
        )
        let crawlMetadata = Shared.Models.CrawlMetadata(
            pages: [
                "https://developer.apple.com/documentation/swiftui/list": goodMetadata,
                "": badMetadata,
            ]
        )

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let strategy = Search.AppleDocsStrategy(docsDirectory: docsDir)

        let stats = try await strategy.indexFromMetadata(
            into: index, metadata: crawlMetadata, progress: nil
        )

        let indexedCount = try await index.documentCount()
        #expect(
            indexedCount == 1,
            "Only the row with a parseable URL key should be indexed; the empty-string row must be skipped"
        )
        #expect(stats.indexed == 1)
        #expect(stats.skipped == 1)
    }

    @Test("All-malformed metadata indexes nothing without crashing")
    func allMalformedRowsAreAllSkipped() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-malformed-url-skip-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        let onlyFile = docsDir.appendingPathComponent("only.md")
        try "# Bad page".write(to: onlyFile, atomically: true, encoding: .utf8)

        let onlyMetadata = Shared.Models.PageMetadata(
            url: "",
            framework: "swiftui",
            filePath: onlyFile.path,
            contentHash: "h",
            depth: 0
        )
        let crawlMetadata = Shared.Models.CrawlMetadata(pages: ["": onlyMetadata])

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let strategy = Search.AppleDocsStrategy(docsDirectory: docsDir)

        let stats = try await strategy.indexFromMetadata(
            into: index, metadata: crawlMetadata, progress: nil
        )

        let indexedCount = try await index.documentCount()
        #expect(indexedCount == 0, "All-malformed metadata should land on zero indexed rows and zero crashes")
        #expect(stats.indexed == 0)
        #expect(stats.skipped == 1)
    }
}

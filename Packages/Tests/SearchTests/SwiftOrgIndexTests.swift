import Foundation
@testable import Search
import Testing

// MARK: - is404Page heuristic (fix for #110)

@Suite("Search.IndexBuilder.is404Page")
struct Is404PageTests {
    @Test("Exact 'not found' title flags the page as 404")
    func titleExactNotFound() {
        #expect(Search.IndexBuilder.is404Page(title: "Not Found", content: "anything"))
        #expect(Search.IndexBuilder.is404Page(title: "not found", content: "anything"))
    }

    @Test("Title containing 404 flags the page as 404")
    func titleContains404() {
        #expect(Search.IndexBuilder.is404Page(title: "404 - Page", content: "anything"))
        #expect(Search.IndexBuilder.is404Page(title: "Error 404", content: "anything"))
    }

    @Test("Content with 'the requested url was not found' flags as 404")
    func contentRequestedURL() {
        let content = "The requested URL was not found on this server."
        #expect(Search.IndexBuilder.is404Page(title: "Some Title", content: content))
    }

    @Test("Content with '404 not found' flags as 404")
    func content404NotFound() {
        #expect(Search.IndexBuilder.is404Page(title: "Some Title", content: "404 Not Found"))
    }

    @Test("Short page with 'page not found' flags as 404")
    func shortPageWithPageNotFound() {
        let shortContent = "Page not found. Please check the URL." // < 500 chars
        #expect(Search.IndexBuilder.is404Page(title: "Error", content: shortContent))
    }

    @Test("Long prose page mentioning 'page not found' is NOT a 404 (real #110 regression)")
    func longProseWithPageNotFound() {
        // Mirrors the Swift Book 'The Basics' false positive: a long doc page that
        // happens to discuss HTTP errors and mentions 'page not found' in a sentence.
        let basicsLikeContent = String(
            repeating: "When a user requests a resource that does not exist, the server may return a page not found response. ",
            count: 20
        )
        #expect(basicsLikeContent.count > 500)
        #expect(!Search.IndexBuilder.is404Page(title: "The Basics", content: basicsLikeContent))
    }

    @Test("Regular documentation page is not flagged")
    func regularPage() {
        let content = "String is a Unicode-correct, locale-insensitive sequence of characters."
        #expect(!Search.IndexBuilder.is404Page(title: "String", content: content))
    }

    @Test("Empty title and content do not flag as 404")
    func emptyInputs() {
        #expect(!Search.IndexBuilder.is404Page(title: "", content: ""))
    }
}

// MARK: - findDocFiles crawl-manifest filter (fix for #110)

@Suite("Search.IndexBuilder.findDocFiles")
struct FindDocFilesTests {
    private static func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-findDocFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("metadata.json is excluded from the doc file list")
    func excludesMetadataJSON() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // A crawl manifest (should be skipped) plus one real doc (should be included).
        try Data("{\"count\": 1}".utf8).write(to: dir.appendingPathComponent("metadata.json"))
        try Data("{\"url\": \"/x\"}".utf8).write(to: dir.appendingPathComponent("real_doc.json"))

        let found = try Search.IndexBuilder.findDocFiles(in: dir)

        #expect(found.count == 1)
        #expect(found.first?.lastPathComponent == "real_doc.json")
    }

    @Test("metadata.json in a subdirectory is also excluded")
    func excludesNestedMetadataJSON() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sub = dir.appendingPathComponent("swift-book")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        try Data("{}".utf8).write(to: sub.appendingPathComponent("metadata.json"))
        try Data("{\"url\": \"/basics\"}".utf8).write(to: sub.appendingPathComponent("thebasics.json"))

        let found = try Search.IndexBuilder.findDocFiles(in: dir)
        let names = Set(found.map(\.lastPathComponent))

        #expect(names == ["thebasics.json"])
    }

    @Test("JSON preferred over MD when both exist for the same basename")
    func jsonPreferredOverMD() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("{\"url\": \"/x\"}".utf8).write(to: dir.appendingPathComponent("doc.json"))
        try Data("# Doc".utf8).write(to: dir.appendingPathComponent("doc.md"))

        let found = try Search.IndexBuilder.findDocFiles(in: dir)
        let names = found.map(\.lastPathComponent)

        #expect(names.contains("doc.json"))
        #expect(!names.contains("doc.md"))
    }

    @Test("MD included when no JSON exists for the same basename")
    func mdIncludedWhenNoJSON() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("# Doc".utf8).write(to: dir.appendingPathComponent("doc.md"))

        let found = try Search.IndexBuilder.findDocFiles(in: dir)
        let names = found.map(\.lastPathComponent)

        #expect(names == ["doc.md"])
    }

    @Test("Files with non-doc extensions are ignored")
    func ignoresOtherExtensions() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("{}".utf8).write(to: dir.appendingPathComponent("doc.json"))
        try Data("random".utf8).write(to: dir.appendingPathComponent("readme.txt"))
        try Data("<html />".utf8).write(to: dir.appendingPathComponent("page.html"))

        let found = try Search.IndexBuilder.findDocFiles(in: dir)
        #expect(found.map(\.lastPathComponent) == ["doc.json"])
    }
}

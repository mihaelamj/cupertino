@testable import Core
@testable import Search
import Foundation
import Shared
import Testing

// MARK: - symbolTokens / splitIdentifier

@Test("splitIdentifier: camelCase → space-separated")
func splitCamel() {
    #expect(Search.PackageIndex.splitIdentifier("makeHTTPRequest") == "make HTTP Request")
}

@Test("splitIdentifier: ALL_CAPS + snake_case")
func splitSnake() {
    #expect(Search.PackageIndex.splitIdentifier("URL_SESSION_SHARED") == "URL SESSION SHARED")
}

@Test("splitIdentifier: HTTPServer (consecutive caps) → HTTP Server")
func splitConsecutiveCaps() {
    #expect(Search.PackageIndex.splitIdentifier("HTTPServer") == "HTTP Server")
}

@Test("splitIdentifier: simple lowercase untouched")
func splitSimpleLower() {
    #expect(Search.PackageIndex.splitIdentifier("vapor") == "vapor")
}

@Test("symbolTokens: contains both original and split forms")
func symbolTokensBothForms() {
    let out = Search.PackageIndex.symbolTokens(from: "let x = makeHTTPRequest(url)")
    #expect(out.contains("makeHTTPRequest"))
    #expect(out.contains("make HTTP Request"))
    #expect(out.contains("url"))
}

@Test("extractTitle: markdown uses first H1")
func extractTitleMarkdownH1() {
    let md = "# My Package\n\nSome text."
    #expect(Search.PackageIndex.extractTitle(relpath: "README.md", content: md) == "My Package")
}

@Test("extractTitle: markdown without H1 falls back to filename")
func extractTitleMarkdownNoH1() {
    let md = "Just text, no heading."
    #expect(Search.PackageIndex.extractTitle(relpath: "README.md", content: md) == "README.md")
}

@Test("extractTitle: non-markdown uses filename")
func extractTitleNonMarkdown() {
    #expect(Search.PackageIndex.extractTitle(relpath: "Sources/Foo/Foo.swift", content: "// blah") == "Foo.swift")
}

// MARK: - PackageIndex SQL round-trip

@Test("PackageIndex: index + summary + dedupe round-trip")
func packageIndexRoundTrip() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-pkgidx-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let dbPath = tempDir.appendingPathComponent("packages.db")

    let index = try await Search.PackageIndex(dbPath: dbPath)
    defer { Task { await index.disconnect() } }

    let resolved = Core.ResolvedPackage(
        owner: "apple",
        repo: "swift-log",
        url: "https://github.com/apple/swift-log",
        priority: .appleOfficial,
        parents: ["apple/swift-log"]
    )
    let files: [Core.ExtractedFile] = [
        .init(
            relpath: "README.md",
            kind: .readme,
            module: nil,
            content: "# swift-log\n\nLogging for Swift.",
            byteSize: 40
        ),
        .init(
            relpath: "Sources/Logging/Logger.swift",
            kind: .source,
            module: "Logging",
            content: "public struct Logger { public var logLevel: Level = .info }",
            byteSize: 60
        ),
    ]
    let extraction = Core.PackageArchiveExtractor.Result(
        branch: "HEAD",
        files: files,
        totalBytes: 100,
        tarballBytes: 9000
    )

    // First index
    let r1 = try await index.index(resolved: resolved, extraction: extraction)
    #expect(r1.filesIndexed == 2)
    let s1 = try await index.summary()
    #expect(s1.packageCount == 1)
    #expect(s1.fileCount == 2)

    // Re-index same package — should replace, not duplicate
    let r2 = try await index.index(resolved: resolved, extraction: extraction)
    #expect(r2.filesIndexed == 2)
    let s2 = try await index.summary()
    #expect(s2.packageCount == 1)
    #expect(s2.fileCount == 2)
}

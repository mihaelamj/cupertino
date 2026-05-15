import Foundation
import LoggingModels
import MCPCore
@testable import MCPSupport
import SharedConstants
import Testing

// Real behavioural coverage of `MCP.Support.DocsResourceProvider`. The
// existing test file in this folder pins the malformed-URL skip path
// added in PR #288; this file pins the rest of the GoF contract:
//
// - the Factory Method shape of `MCP.Support.DocsResourceProvider` (its
//   inputs and the resource listings it emits)
// - the Strategy shape of `MCP.Support.MarkdownLookupStrategy`
//   (substitutability and "lookup-then-fallback" sequencing)
// - the URI parsers for the three supported schemes
// - the error contract on bad / missing inputs

// MARK: - Test fixtures

/// `MarkdownLookupStrategy` stub that returns the same hardcoded
/// content for any URI it receives. Used to verify the Strategy is
/// preferred over the filesystem fallback.
private struct AlwaysHitsMarkdownLookup: MCP.Support.MarkdownLookupStrategy {
    let payload: String
    func lookup(uri _: String) async throws -> String? {
        payload
    }
}

/// `MarkdownLookupStrategy` stub that always returns nil — simulates
/// "URI not in the database" so the provider must fall through to the
/// filesystem path.
private struct AlwaysMissesMarkdownLookup: MCP.Support.MarkdownLookupStrategy {
    func lookup(uri _: String) async throws -> String? {
        nil
    }
}

/// `MarkdownLookupStrategy` stub that throws. Used to verify the
/// provider propagates strategy errors instead of swallowing them.
private struct ThrowingMarkdownLookup: MCP.Support.MarkdownLookupStrategy {
    struct StubError: Error {}
    func lookup(uri _: String) async throws -> String? {
        throw StubError()
    }
}

/// Builds a tmp directory, returns its URL, and registers cleanup.
private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-docsres-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeProvider(
    crawlOutputDirectory: URL,
    evolutionDir: URL,
    archiveDir: URL,
    markdownLookup: (any MCP.Support.MarkdownLookupStrategy)? = nil
) -> MCP.Support.DocsResourceProvider {
    let crawler = Shared.Configuration.Crawler(outputDirectory: crawlOutputDirectory)
    let changeDetection = Shared.Configuration.ChangeDetection(outputDirectory: crawlOutputDirectory)
    let config = Shared.Configuration(crawler: crawler, changeDetection: changeDetection)
    return MCP.Support.DocsResourceProvider(
        configuration: config,
        evolutionDirectory: evolutionDir,
        archiveDirectory: archiveDir,
        markdownLookup: markdownLookup,
        logger: Logging.NoopRecording()
    )
}

// MARK: - Namespace anchor

@Suite("MCP.Support namespace anchor")
struct MCPSupportNamespaceTests {
    @Test("MCP.Support namespace exists and is reachable")
    func namespaceExists() {
        let _: MCP.Support.Type = MCP.Support.self
    }
}

// MARK: - listResources

@Suite("MCP.Support.DocsResourceProvider.listResources")
struct DocsResourceProviderListResourcesTests {
    @Test("Returns empty when no apple-docs metadata, no evolution dir, no archive dir")
    func emptyEverywhere() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("missing-evolution"),
            archiveDir: tmp.appendingPathComponent("missing-archive")
        )
        // Inject empty metadata explicitly so the provider doesn't fall
        // through to the load-from-disk path, which would read whatever
        // `~/.cupertino/metadata.json` already exists on the user's
        // machine and contaminate the assertion.
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata())
        let result = try await provider.listResources(cursor: nil)
        #expect(result.resources.isEmpty)
    }

    @Test("Apple-docs entry has scheme prefix, framework segment, and markdown mime type")
    func appleDocsEntryShape() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )

        // Framework-root URL post-#568: only the page whose URL path
        // is exactly `/documentation/<framework>` survives the
        // resources/list filter. Deep symbol pages
        // (`/documentation/swiftui/list` etc.) belong to `tools/call
        // search` + `readResource`, not the resource browser.
        let page = Shared.Models.PageMetadata(
            url: "https://developer.apple.com/documentation/swiftui",
            framework: "swiftui",
            filePath: "/dev/null",
            contentHash: "h",
            depth: 0
        )
        let metadata = Shared.Models.CrawlMetadata(pages: [
            "https://developer.apple.com/documentation/swiftui": page,
        ])
        await provider.injectMetadataForTesting(metadata)

        let result = try await provider.listResources(cursor: nil)
        let appleDocs = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        #expect(appleDocs.count == 1)
        // Post-#588 lossless URI: a framework-root URL
        // (`/documentation/swiftui`) maps to `apple-docs://swiftui` — no
        // trailing slash, no path segment beyond the framework.
        // Sub-page URIs still carry the `<framework>/<rest>` shape.
        #expect(appleDocs.first?.uri == "apple-docs://swiftui")
        #expect(appleDocs.first?.mimeType == MCP.SharedTools.Copy.mimeTypeMarkdown)
    }

    @Test("Apple-docs entries are alphabetised by `name`")
    func sortedByName() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )

        // Three framework-root pages so the result is non-empty
        // post-#568 filter (deep symbol URLs are now correctly
        // dropped). Generated `name` is the last URL component
        // capitalised + dash/underscore-stripped: Swiftui, Foundation,
        // Accelerate. Input order is intentionally non-sorted so the
        // assertion exercises real sorting, not a vacuous tautology.
        let pages: [String: Shared.Models.PageMetadata] = [
            "https://developer.apple.com/documentation/swiftui": .init(
                url: "https://developer.apple.com/documentation/swiftui",
                framework: "swiftui",
                filePath: "/dev/null",
                contentHash: "1",
                depth: 0
            ),
            "https://developer.apple.com/documentation/foundation": .init(
                url: "https://developer.apple.com/documentation/foundation",
                framework: "foundation",
                filePath: "/dev/null",
                contentHash: "2",
                depth: 0
            ),
            "https://developer.apple.com/documentation/accelerate": .init(
                url: "https://developer.apple.com/documentation/accelerate",
                framework: "accelerate",
                filePath: "/dev/null",
                contentHash: "3",
                depth: 0
            ),
        ]
        await provider.injectMetadataForTesting(.init(pages: pages))

        let names = try await provider.listResources(cursor: nil).resources.map(\.name)
        #expect(names.count == 3, "three framework roots should survive the filter (got \(names))")
        #expect(names == names.sorted(), "listResources should sort by name (got \(names))")
    }

    @Test("Picks up SE-* markdown files in the evolution directory")
    func evolutionDirectoryListing() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let evolution = tmp.appendingPathComponent("evolution")
        try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
        try "# SE-0001".write(to: evolution.appendingPathComponent("SE-0001-foo.md"), atomically: true, encoding: .utf8)
        try "# SE-0002".write(to: evolution.appendingPathComponent("SE-0002-bar.md"), atomically: true, encoding: .utf8)
        // Non-md file: must be ignored.
        try "ignore".write(to: evolution.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        // .md file but wrong prefix: must be ignored too.
        try "# random".write(to: evolution.appendingPathComponent("random.md"), atomically: true, encoding: .utf8)

        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: evolution,
            archiveDir: tmp.appendingPathComponent("archive")
        )

        let result = try await provider.listResources(cursor: nil)
        let evolutionResources = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.swiftEvolutionScheme)
        }
        #expect(evolutionResources.count == 2)
        let names = evolutionResources.map(\.name).sorted()
        #expect(names == ["SE-0001-foo", "SE-0002-bar"])
    }

    @Test("Picks up ST-* markdown files in the evolution directory too")
    func evolutionDirectoryAcceptsSTPrefix() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let evolution = tmp.appendingPathComponent("evolution")
        try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
        try "# ST".write(to: evolution.appendingPathComponent("ST-0001-test.md"), atomically: true, encoding: .utf8)

        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: evolution,
            archiveDir: tmp.appendingPathComponent("archive")
        )

        let stResources = try await provider.listResources(cursor: nil).resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.swiftEvolutionScheme)
        }
        #expect(stResources.count == 1)
    }

    @Test("Picks up archive-directory markdown files under each guide UID")
    func archiveDirectoryListing() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = tmp.appendingPathComponent("archive")
        let guide = archive.appendingPathComponent("xcode-help")
        try FileManager.default.createDirectory(at: guide, withIntermediateDirectories: true)
        try "# intro".write(to: guide.appendingPathComponent("intro.md"), atomically: true, encoding: .utf8)
        // Non-md gets ignored.
        try "ignore".write(to: guide.appendingPathComponent("intro.txt"), atomically: true, encoding: .utf8)

        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: archive
        )
        let result = try await provider.listResources(cursor: nil)
        let archiveResources = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleArchiveScheme)
        }
        #expect(archiveResources.count == 1)
        #expect(archiveResources.first?.uri == "\(Shared.Constants.Search.appleArchiveScheme)xcode-help/intro")
    }
}

// MARK: - readResource: apple-docs

@Suite("MCP.Support.DocsResourceProvider.readResource — apple-docs")
struct DocsResourceProviderReadAppleDocsTests {
    @Test("Reads .json file and returns the stored rawMarkdown payload")
    func readsJSONRawMarkdown() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let docsRoot = tmp.appendingPathComponent("docs")
        let frameworkDir = docsRoot.appendingPathComponent("swiftui")
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)

        let payload = "# Title\n\nBody markdown."
        let pageURL = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/list"))
        let page = Shared.Models.StructuredDocumentationPage(
            url: pageURL,
            title: "Title",
            kind: .struct,
            source: .appleJSON,
            rawMarkdown: payload
        )
        let jsonData = try Shared.Utils.JSONCoding.encode(page)
        try jsonData.write(to: frameworkDir.appendingPathComponent("list.json"))

        let provider = makeProvider(
            crawlOutputDirectory: docsRoot,
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )

        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/list")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == payload)
        #expect(text.mimeType == MCP.SharedTools.Copy.mimeTypeMarkdown)
    }

    @Test("Falls back to .md when no .json exists")
    func fallsBackToMarkdownFile() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let docsRoot = tmp.appendingPathComponent("docs")
        let frameworkDir = docsRoot.appendingPathComponent("swiftui")
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        let payload = "# Plain MD fallback"
        try payload.write(
            to: frameworkDir.appendingPathComponent("list\(Shared.Constants.FileName.markdownExtension)"),
            atomically: true,
            encoding: .utf8
        )

        let provider = makeProvider(
            crawlOutputDirectory: docsRoot,
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )

        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/list")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == payload)
    }

    @Test("Throws notFound when neither .json nor .md exists for the framework/filename")
    func notFoundWhenNeitherExists() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/nope")
        }
    }

    @Test("Throws invalidURI when apple-docs:// is missing the framework/filename segments")
    func invalidURIMissingSegments() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui-no-slash")
        }
    }
}

// MARK: - readResource: GoF Strategy (markdownLookup)

@Suite("MCP.Support.DocsResourceProvider — MarkdownLookupStrategy seam")
struct DocsResourceProviderStrategyTests {
    @Test("readResource prefers the injected strategy when it returns content")
    func strategyPreferredOverFilesystem() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Put a different .md on disk so we can prove the strategy wins.
        let docsRoot = tmp.appendingPathComponent("docs")
        let frameworkDir = docsRoot.appendingPathComponent("swiftui")
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        try "from-disk".write(
            to: frameworkDir.appendingPathComponent("list\(Shared.Constants.FileName.markdownExtension)"),
            atomically: true,
            encoding: .utf8
        )

        let provider = makeProvider(
            crawlOutputDirectory: docsRoot,
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive"),
            markdownLookup: AlwaysHitsMarkdownLookup(payload: "from-strategy")
        )
        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/list")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == "from-strategy", "Strategy should be tried first")
    }

    @Test("readResource falls back to filesystem when strategy returns nil")
    func fallsBackWhenStrategyMisses() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let docsRoot = tmp.appendingPathComponent("docs")
        let frameworkDir = docsRoot.appendingPathComponent("swiftui")
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        try "from-disk".write(
            to: frameworkDir.appendingPathComponent("list\(Shared.Constants.FileName.markdownExtension)"),
            atomically: true,
            encoding: .utf8
        )

        let provider = makeProvider(
            crawlOutputDirectory: docsRoot,
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive"),
            markdownLookup: AlwaysMissesMarkdownLookup()
        )
        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/list")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == "from-disk", "Filesystem fallback should run when strategy returns nil")
    }

    @Test("readResource propagates strategy errors (no swallow, no fallback)")
    func propagatesStrategyError() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive"),
            markdownLookup: ThrowingMarkdownLookup()
        )
        await #expect(throws: ThrowingMarkdownLookup.StubError.self) {
            _ = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/list")
        }
    }
}

// MARK: - readResource: swift-evolution + apple-archive + unknown

@Suite("MCP.Support.DocsResourceProvider.readResource — other schemes")
struct DocsResourceProviderReadOtherSchemesTests {
    @Test("Reads a swift-evolution:// resource from the evolution directory")
    func readsSwiftEvolution() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let evolution = tmp.appendingPathComponent("evolution")
        try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
        let body = "# SE-0042"
        try body.write(to: evolution.appendingPathComponent("SE-0042-life.md"), atomically: true, encoding: .utf8)

        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: evolution,
            archiveDir: tmp.appendingPathComponent("archive")
        )
        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.swiftEvolutionScheme)SE-0042")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == body)
    }

    @Test("Throws invalidURI on swift-evolution:// with empty proposal ID")
    func invalidURIWhenEvolutionIDEmpty() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let evolution = tmp.appendingPathComponent("evolution")
        try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: evolution,
            archiveDir: tmp.appendingPathComponent("archive")
        )
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: Shared.Constants.Search.swiftEvolutionScheme)
        }
    }

    @Test("Reads an apple-archive:// resource under the matching guide UID")
    func readsAppleArchive() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = tmp.appendingPathComponent("archive")
        let guide = archive.appendingPathComponent("xcode-help")
        try FileManager.default.createDirectory(at: guide, withIntermediateDirectories: true)
        let body = "# Archive intro"
        try body.write(to: guide.appendingPathComponent("intro.md"), atomically: true, encoding: .utf8)

        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: archive
        )
        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.appleArchiveScheme)xcode-help/intro")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == body)
    }

    @Test("Throws notFound when the apple-archive:// guide / filename pair has no file on disk")
    func notFoundWhenArchiveFileMissing() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = tmp.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: archive
        )
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "\(Shared.Constants.Search.appleArchiveScheme)nope/missing")
        }
    }

    @Test("Throws invalidURI on apple-archive:// missing the filename segment")
    func invalidArchiveURIMissingFilename() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = tmp.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: archive
        )
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "\(Shared.Constants.Search.appleArchiveScheme)xcode-help-no-slash")
        }
    }

    @Test("Throws invalidURI when the URI scheme isn't apple-docs / swift-evolution / apple-archive")
    func invalidURIUnknownScheme() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "ftp://example.com/file.md")
        }
    }
}

// MARK: - listResourceTemplates

@Suite("MCP.Support.DocsResourceProvider.listResourceTemplates")
struct DocsResourceProviderListTemplatesTests {
    @Test("Returns the two canonical templates (apple-docs + swift-evolution)")
    func twoTemplates() async throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let provider = makeProvider(
            crawlOutputDirectory: tmp.appendingPathComponent("docs"),
            evolutionDir: tmp.appendingPathComponent("evolution"),
            archiveDir: tmp.appendingPathComponent("archive")
        )
        let result = try await provider.listResourceTemplates(cursor: nil)
        let templates = result?.resourceTemplates ?? []
        #expect(templates.count == 2)
        let templateURIs = templates.map(\.uriTemplate)
        #expect(templateURIs.contains(MCP.SharedTools.Copy.templateAppleDocs))
        #expect(templateURIs.contains(MCP.SharedTools.Copy.templateSwiftEvolution))
    }
}

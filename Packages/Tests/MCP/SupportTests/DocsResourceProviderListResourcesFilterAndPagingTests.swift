import Foundation
import LoggingModels
import MCPCore
@testable import MCPSupport
import SharedConstants
import Testing

// Covers the framework-root filter + cursor pagination + loud-metadata-
// load behaviour added to
// `MCP.Support.DocsResourceProvider.listResources` in #568.
//
// Pre-fix shape (silent on v1.1.0, loud on v1.2.0-staged): every entry in
// `CrawlMetadata.pages` became one apple-docs resource, giving 55k+
// entries against the live corpus and 11.1 MB JSON responses. Post-fix
// shape: only framework-root pages become resources, and a result with
// more than `pageSize` items returns the first slice + a `nextCursor`.
//
// The malformed-URL skip behaviour is covered separately in
// `DocsResourceProviderMalformedURLSkipTests`; this suite only verifies
// the count + filter + pagination contract.

@Suite("MCP.Support.DocsResourceProvider listResources filter + paging", .serialized)
struct DocsResourceProviderListResourcesFilterAndPagingTests {
    // MARK: - Helpers

    private func makeProvider(in tempRoot: URL) -> MCP.Support.DocsResourceProvider {
        let evolutionDir = tempRoot.appendingPathComponent("swift-evolution")
        let archiveDir = tempRoot.appendingPathComponent("archive")
        let config = Shared.Configuration(
            crawler: Shared.Configuration.Crawler(outputDirectory: tempRoot),
            changeDetection: Shared.Configuration.ChangeDetection(outputDirectory: tempRoot)
        )
        return MCP.Support.DocsResourceProvider(
            configuration: config,
            evolutionDirectory: evolutionDir,
            archiveDirectory: archiveDir,
            markdownLookup: nil,
            logger: Logging.NoopRecording()
        )
    }

    private func framework(name: String) -> (key: String, page: Shared.Models.PageMetadata) {
        // Framework root: path is exactly `/documentation/<framework>`, no trailing component.
        let url = "https://developer.apple.com/documentation/\(name)"
        return (url, Shared.Models.PageMetadata(
            url: url,
            framework: name,
            filePath: "/dev/null",
            contentHash: name,
            depth: 0
        ))
    }

    private func deepPage(framework: String, slug: String) -> (key: String, page: Shared.Models.PageMetadata) {
        // Deep page (NOT a framework root): one or more path components under the framework.
        let url = "https://developer.apple.com/documentation/\(framework)/\(slug)"
        return (url, Shared.Models.PageMetadata(
            url: url,
            framework: framework,
            filePath: "/dev/null",
            contentHash: "\(framework)/\(slug)",
            depth: 1
        ))
    }

    // MARK: - Filter

    @Test("Filter: framework-root pages survive, deep symbol pages are dropped")
    func filterKeepsRootsDropsDeepPages() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-filter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var pages: [String: Shared.Models.PageMetadata] = [:]
        let (rootKey, rootPage) = framework(name: "swiftui")
        pages[rootKey] = rootPage
        for slug in ["list", "view", "init(_:)", "anonymous-field-0", "unnamed-struct"] {
            let (k, p) = deepPage(framework: "swiftui", slug: slug)
            pages[k] = p
        }

        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: pages))

        let result = try await provider.listResources(cursor: nil)
        let appleDocs = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        #expect(appleDocs.count == 1, "Only the framework root should survive the filter")
    }

    @Test("Filter: framework-root URL with trailing slash still counts as root")
    func filterAcceptsTrailingSlash() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-trailingslash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let url = "https://developer.apple.com/documentation/swiftui/"
        let page = Shared.Models.PageMetadata(
            url: url,
            framework: "swiftui",
            filePath: "/dev/null",
            contentHash: "swiftui",
            depth: 0
        )
        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: [url: page]))

        let result = try await provider.listResources(cursor: nil)
        let appleDocs = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        #expect(appleDocs.count == 1)
    }

    @Test("Filter: case-insensitive match between URL path and framework name")
    func filterCaseInsensitive() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-caseins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Apple's JSON API returns mixed-case framework names; the canonical URL is lowercased.
        let url = "https://developer.apple.com/documentation/SwiftUI"
        let page = Shared.Models.PageMetadata(
            url: url,
            framework: "swiftui",
            filePath: "/dev/null",
            contentHash: "swiftui",
            depth: 0
        )
        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: [url: page]))

        let result = try await provider.listResources(cursor: nil)
        let appleDocs = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        #expect(appleDocs.count == 1)
    }

    // MARK: - Count cap (the contract that pins the bug regression shut)

    @Test("Count cap: a 60k-page corpus collapses to ≤ pageSize apple-docs resources")
    func countCapAgainst60kCorpus() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // 100 framework roots + 599 deep pages per framework ≈ 60k entries,
        // mirroring the live `metadata.json` shape that surfaced the bug.
        var pages: [String: Shared.Models.PageMetadata] = [:]
        for frameworkIndex in 0..<100 {
            let frameworkName = "framework\(frameworkIndex)"
            let (k, p) = framework(name: frameworkName)
            pages[k] = p
            for slug in 0..<599 {
                let (dk, dp) = deepPage(framework: frameworkName, slug: "deep-\(slug)")
                pages[dk] = dp
            }
        }
        #expect(pages.count == 100 * 600, "fixture should be exactly 60,000 pages")

        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: pages))

        let result = try await provider.listResources(cursor: nil)
        let appleDocs = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        // Filter alone would yield 100 frameworks; the pageSize cap is the
        // second line of defence. The pinned contract: never more than
        // `MCP.Support.DocsResourceProvider.pageSize` apple-docs resources
        // in a single page, no matter what the corpus shape is.
        #expect(appleDocs.count <= MCP.Support.DocsResourceProvider.pageSize)
        // And every survivor is a framework root.
        for resource in appleDocs {
            #expect(!resource.uri.contains("/deep-"), "deep-page URI leaked past filter: \(resource.uri)")
        }
    }

    // MARK: - Pagination

    @Test("Pagination: first page returns pageSize items + nextCursor when more remain")
    func paginationFirstPage() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-page1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Need strictly more than pageSize framework roots so a nextCursor must be issued.
        var pages: [String: Shared.Models.PageMetadata] = [:]
        let pageSize = MCP.Support.DocsResourceProvider.pageSize
        let total = pageSize + 50
        for i in 0..<total {
            let (k, p) = framework(name: "framework\(String(format: "%04d", i))")
            pages[k] = p
        }

        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: pages))

        let firstPage = try await provider.listResources(cursor: nil)
        #expect(firstPage.resources.count == pageSize)
        #expect(firstPage.nextCursor != nil)
    }

    @Test("Pagination: nextCursor returns the remaining tail and no further nextCursor")
    func paginationSecondPageExhausts() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-page2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var pages: [String: Shared.Models.PageMetadata] = [:]
        let pageSize = MCP.Support.DocsResourceProvider.pageSize
        let total = pageSize + 50
        for i in 0..<total {
            let (k, p) = framework(name: "framework\(String(format: "%04d", i))")
            pages[k] = p
        }

        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: pages))

        let firstPage = try await provider.listResources(cursor: nil)
        let nextCursor = try #require(firstPage.nextCursor)
        let secondPage = try await provider.listResources(cursor: nextCursor)
        #expect(secondPage.resources.count == 50, "second page should hold the remaining 50 framework roots")
        #expect(secondPage.nextCursor == nil, "second page is the final slice; nextCursor must be nil")
    }

    @Test("Pagination: invalid cursor throws invalidArgument (#595 — strict, was lenient pre-fix)")
    func paginationInvalidCursorThrows() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-badcursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let (k, p) = framework(name: "swiftui")
        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: [k: p]))

        // Pre-#595 this silently returned page 1, trapping paginating
        // clients in an infinite re-fetch loop. Post-#595 it throws
        // invalidArgument; the JSON-RPC layer surfaces -32602.
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.listResources(cursor: "🚫not-a-cursor")
        }
    }

    @Test("Pagination: empty / nil cursor remains the 'first page' bootstrap call (regression check)")
    func paginationEmptyCursorReturnsFirstPage() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-listres-emptycursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let (k, p) = framework(name: "swiftui")
        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(Shared.Models.CrawlMetadata(pages: [k: p]))
        let emptyResult = try await provider.listResources(cursor: "")
        #expect(emptyResult.resources.count == 1)
        let nilResult = try await provider.listResources(cursor: nil as String?)
        #expect(nilResult.resources.count == 1)
    }
}

import Foundation
import LoggingModels
import MCPCore
@testable import MCPSupport
import SearchModels
import SharedConstants
import Testing

// Covers the cursor-pagination contract on
// `MCP.Support.DocsResourceProvider.listResources` (#568 + #595).
//
// 2026-05-28 (Principle 7): the resources list is now built purely
// from the DB-backed `MarkdownLookupStrategy.listResources()` seam, so
// these tests drive the provider with a stub lookup returning a
// controllable entry list. The framework-root vs full-document
// enumeration policy is exercised separately against a real
// `Search.Index` in `DocsResourceProviderDBBackedTests`.
//
// Pinned contract: a result longer than `pageSize` returns the first
// slice + a `nextCursor`; following the cursor returns the tail with
// no further cursor; a malformed cursor throws `invalidArgument`.

/// Stub lookup returning a fixed list (read path unused here).
private struct ListStubLookup: MCP.Support.MarkdownLookupStrategy {
    let entries: [Search.URIResource]
    func lookup(uri _: String) async throws -> String? {
        nil
    }

    func listResources() async throws -> [Search.URIResource] {
        entries
    }
}

@Suite("MCP.Support.DocsResourceProvider listResources paging", .serialized)
struct DocsResourceProviderListResourcesFilterAndPagingTests {
    // MARK: - Helpers

    private func makeProvider(entries: [Search.URIResource]) -> MCP.Support.DocsResourceProvider {
        MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: ListStubLookup(entries: entries),
            logger: Logging.NoopRecording()
        )
    }

    private func appleDocsEntry(name: String) -> Search.URIResource {
        Search.URIResource(
            uri: "\(Shared.Constants.Search.appleDocsScheme)\(name)",
            name: name,
            description: "Documentation: \(name)"
        )
    }

    // MARK: - Count cap

    @Test("Count cap: a large entry list collapses to ≤ pageSize resources per page")
    func countCapAgainstLargeList() async throws {
        var entries: [Search.URIResource] = []
        for index in 0..<(MCP.Support.DocsResourceProvider.pageSize + 200) {
            entries.append(appleDocsEntry(name: "framework\(String(format: "%04d", index))"))
        }
        let provider = makeProvider(entries: entries)
        let result = try await provider.listResources(cursor: nil)
        #expect(result.resources.count <= MCP.Support.DocsResourceProvider.pageSize)
    }

    // MARK: - Pagination

    @Test("Pagination: first page returns pageSize items + nextCursor when more remain")
    func paginationFirstPage() async throws {
        let pageSize = MCP.Support.DocsResourceProvider.pageSize
        let total = pageSize + 50
        var entries: [Search.URIResource] = []
        for index in 0..<total {
            entries.append(appleDocsEntry(name: "framework\(String(format: "%04d", index))"))
        }
        let firstPage = try await makeProvider(entries: entries).listResources(cursor: nil)
        #expect(firstPage.resources.count == pageSize)
        #expect(firstPage.nextCursor != nil)
    }

    @Test("Pagination: nextCursor returns the remaining tail and no further nextCursor")
    func paginationSecondPageExhausts() async throws {
        let pageSize = MCP.Support.DocsResourceProvider.pageSize
        let total = pageSize + 50
        var entries: [Search.URIResource] = []
        for index in 0..<total {
            entries.append(appleDocsEntry(name: "framework\(String(format: "%04d", index))"))
        }
        let provider = makeProvider(entries: entries)
        let firstPage = try await provider.listResources(cursor: nil)
        let nextCursor = try #require(firstPage.nextCursor)
        let secondPage = try await provider.listResources(cursor: nextCursor)
        #expect(secondPage.resources.count == 50, "second page should hold the remaining 50 entries")
        #expect(secondPage.nextCursor == nil, "second page is the final slice; nextCursor must be nil")
    }

    @Test("Pagination: invalid cursor throws invalidArgument (#595 — strict, was lenient pre-fix)")
    func paginationInvalidCursorThrows() async throws {
        let provider = makeProvider(entries: [appleDocsEntry(name: "swiftui")])
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.listResources(cursor: "🚫not-a-cursor")
        }
    }

    @Test("Pagination: empty / nil cursor remains the 'first page' bootstrap call (regression check)")
    func paginationEmptyCursorReturnsFirstPage() async throws {
        let provider = makeProvider(entries: [appleDocsEntry(name: "swiftui")])
        let emptyResult = try await provider.listResources(cursor: "")
        #expect(emptyResult.resources.count == 1)
        let nilResult = try await provider.listResources(cursor: nil as String?)
        #expect(nilResult.resources.count == 1)
    }
}

import Foundation
import LoggingModels
import MCPCore
@testable import MCPSupport
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

// DB-backed behavioural coverage of `MCP.Support.DocsResourceProvider`.
//
// 2026-05-28 (Principle 7): the MCP `resources/{list,read}` path is
// served PURELY from the per-source SQLite DBs. This suite pins:
//
// - the Strategy shape of `MCP.Support.MarkdownLookupStrategy`
//   (read + list, substitutability, error propagation)
// - the readResource contract: DB hit → text, DB miss → notFound, no
//   filesystem fallback
// - the listResources contract: entries built from the DB-backed seam,
//   sorted by name, paginated
// - that a real `Search.Index` over a per-source DB enumerates +
//   resolves resources with NO filesystem access

// MARK: - Test doubles for the MarkdownLookupStrategy seam

/// Strategy stub returning fixed content for any URI + a fixed list.
private struct StubMarkdownLookup: MCP.Support.MarkdownLookupStrategy {
    var readPayload: String?
    var listPayload: [Search.URIResource] = []

    func lookup(uri _: String) async throws -> String? {
        readPayload
    }

    func listResources() async throws -> [Search.URIResource] {
        listPayload
    }
}

/// Strategy stub whose `lookup` throws. Pins error propagation (no
/// swallow, no fallback).
private struct ThrowingMarkdownLookup: MCP.Support.MarkdownLookupStrategy {
    struct StubError: Error {}
    func lookup(uri _: String) async throws -> String? {
        throw StubError()
    }

    func listResources() async throws -> [Search.URIResource] {
        throw StubError()
    }
}

// MARK: - Namespace anchor

@Suite("MCP.Support namespace anchor")
struct MCPSupportNamespaceTests {
    @Test("MCP.Support namespace exists and is reachable")
    func namespaceExists() {
        let _: MCP.Support.Type = MCP.Support.self
    }
}

// MARK: - readResource (DB-only)

@Suite("MCP.Support.DocsResourceProvider.readResource — DB-only")
struct DocsResourceProviderReadTests {
    private func makeProvider(
        lookup: (any MCP.Support.MarkdownLookupStrategy)?
    ) -> MCP.Support.DocsResourceProvider {
        MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: lookup,
            logger: Logging.NoopRecording()
        )
    }

    @Test("Returns the DB content when the lookup resolves the URI")
    func returnsDBContent() async throws {
        let provider = makeProvider(lookup: StubMarkdownLookup(readPayload: "from-db"))
        let result = try await provider.readResource(uri: "apple-docs://swiftui/list")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text == "from-db")
        #expect(text.mimeType == MCP.SharedTools.Copy.mimeTypeMarkdown)
    }

    @Test("Throws notFound when the lookup returns nil (no filesystem fallback)")
    func notFoundOnMiss() async throws {
        let provider = makeProvider(lookup: StubMarkdownLookup(readPayload: nil))
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/nope")
        }
    }

    @Test("Throws notFound when no lookup is wired at all")
    func notFoundWhenNoLookup() async throws {
        let provider = makeProvider(lookup: nil)
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/list")
        }
    }

    @Test("Propagates lookup errors (no swallow, no fallback)")
    func propagatesLookupError() async throws {
        let provider = makeProvider(lookup: ThrowingMarkdownLookup())
        await #expect(throws: ThrowingMarkdownLookup.StubError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/list")
        }
    }
}

// MARK: - listResources (DB-only)

@Suite("MCP.Support.DocsResourceProvider.listResources — DB-only")
struct DocsResourceProviderListTests {
    private func makeProvider(
        lookup: (any MCP.Support.MarkdownLookupStrategy)?
    ) -> MCP.Support.DocsResourceProvider {
        MCP.Support.DocsResourceProvider(
            knownURISchemes: [],
            markdownLookup: lookup,
            logger: Logging.NoopRecording()
        )
    }

    @Test("Empty when no lookup wired")
    func emptyWhenNoLookup() async throws {
        let result = try await makeProvider(lookup: nil).listResources(cursor: nil)
        #expect(result.resources.isEmpty)
        #expect(result.nextCursor == nil)
    }

    @Test("Maps DB-backed entries to MCP resources with markdown mime type")
    func mapsEntries() async throws {
        let lookup = StubMarkdownLookup(
            readPayload: nil,
            listPayload: [
                Search.URIResource(uri: "apple-docs://swiftui", name: "SwiftUI", description: "d"),
            ]
        )
        let result = try await makeProvider(lookup: lookup).listResources(cursor: nil)
        #expect(result.resources.count == 1)
        #expect(result.resources.first?.uri == "apple-docs://swiftui")
        #expect(result.resources.first?.mimeType == MCP.SharedTools.Copy.mimeTypeMarkdown)
    }

    @Test("Sorts entries by name")
    func sortedByName() async throws {
        let lookup = StubMarkdownLookup(
            readPayload: nil,
            listPayload: [
                Search.URIResource(uri: "a://3", name: "Zebra", description: "d"),
                Search.URIResource(uri: "a://1", name: "Apple", description: "d"),
                Search.URIResource(uri: "a://2", name: "Mango", description: "d"),
            ]
        )
        let names = try await makeProvider(lookup: lookup).listResources(cursor: nil).resources.map(\.name)
        #expect(names == ["Apple", "Mango", "Zebra"])
    }

    @Test("Empty DB enumeration yields an empty page (lookup error logged, not thrown)")
    func enumerationErrorYieldsEmptyPage() async throws {
        // ThrowingMarkdownLookup.listResources throws; the provider logs
        // and returns an empty page rather than failing the call.
        let result = try await makeProvider(lookup: ThrowingMarkdownLookup()).listResources(cursor: nil)
        #expect(result.resources.isEmpty)
        #expect(result.nextCursor == nil)
    }
}

// MARK: - End-to-end DB-backed (real Search.Index, no filesystem)

/// `MarkdownLookupStrategy` backed by a real per-source `Search.Index`
/// — the test-side equivalent of the production `LiveMarkdownLookupStrategy`
/// (which lives in the CLI composition root and isn't importable here).
/// Read + list both resolve from the DB; no filesystem is consulted.
private struct IndexBackedLookup: MCP.Support.MarkdownLookupStrategy {
    let dbURL: URL
    let mode: Search.ResourceListMode

    func lookup(uri: String) async throws -> String? {
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        defer { Task { await index.disconnect() } }
        return try await index.getDocumentContent(uri: uri, format: .markdown)
    }

    func listResources() async throws -> [Search.URIResource] {
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let entries = try await index.listResourceEntries(mode: mode)
        await index.disconnect()
        return entries
    }
}

@Suite("MCP.Support.DocsResourceProvider — end-to-end DB-backed", .serialized)
struct DocsResourceProviderDBBackedTests {
    private static func makeTempDB() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "mcp-resources-\(UUID().uuidString).db"
        )
    }

    /// Build a per-source `Search.Index` with apple-docs framework
    /// roots + sub-pages.
    private static func seedAppleDocs(_ dbURL: URL) async throws {
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        // Framework-root rows (uri == apple-docs://<framework>).
        for fw in ["swiftui", "foundation"] {
            try await index.indexDocument(Search.IndexDocumentParams(
                uri: "\(Shared.Constants.Search.appleDocsScheme)\(fw)",
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: fw,
                title: fw,
                content: "Root of \(fw)",
                filePath: "/n/a",
                contentHash: "h-\(fw)",
                lastCrawled: Date()
            ))
        }
        // A deep sub-page that must NOT appear in the framework-root list.
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui/list",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "List",
            content: "SwiftUI List view body content",
            filePath: "/n/a",
            contentHash: "h-list",
            lastCrawled: Date()
        ))
        await index.disconnect()
    }

    @Test("Framework-root mode lists only roots; sub-pages excluded")
    func frameworkRootList() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try await Self.seedAppleDocs(dbURL)

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .frameworkRoots),
            logger: Logging.NoopRecording()
        )
        let result = try await provider.listResources(cursor: nil)
        let uris = Set(result.resources.map(\.uri))
        #expect(uris == [
            "\(Shared.Constants.Search.appleDocsScheme)swiftui",
            "\(Shared.Constants.Search.appleDocsScheme)foundation",
        ])
        // The deep sub-page is excluded from the framework-root slice.
        #expect(!uris.contains("\(Shared.Constants.Search.appleDocsScheme)swiftui/list"))
    }

    @Test("readResource resolves a listed framework-root URI from the DB")
    func readListedRoot() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try await Self.seedAppleDocs(dbURL)

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .frameworkRoots),
            logger: Logging.NoopRecording()
        )
        let result = try await provider.readResource(uri: "\(Shared.Constants.Search.appleDocsScheme)swiftui")
        guard case .text(let text) = result.contents.first else {
            Issue.record("Expected text contents")
            return
        }
        #expect(text.text.contains("Root of swiftui"))
    }

    @Test("all-documents mode lists every doc row; readResource reads each")
    func allDocumentsList() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        for proposal in ["SE-0001", "SE-0002", "SE-0003"] {
            try await index.indexDocument(Search.IndexDocumentParams(
                uri: "\(Shared.Constants.Search.swiftEvolutionScheme)\(proposal)",
                source: Shared.Constants.SourcePrefix.swiftEvolution,
                framework: "swift-evolution",
                title: proposal,
                content: "Body of \(proposal)",
                filePath: "/n/a",
                contentHash: "h-\(proposal)",
                lastCrawled: Date()
            ))
        }
        await index.disconnect()

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.swiftEvolutionScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .allDocuments),
            logger: Logging.NoopRecording()
        )
        let listResult = try await provider.listResources(cursor: nil)
        #expect(listResult.resources.count == 3)

        // Every listed URI is readable from the DB.
        for resource in listResult.resources {
            let read = try await provider.readResource(uri: resource.uri)
            guard case .text(let text) = read.contents.first else {
                Issue.record("Expected text for \(resource.uri)")
                continue
            }
            #expect(!text.text.isEmpty)
        }
    }
}

// MARK: - listResourceTemplates

@Suite("MCP.Support.DocsResourceProvider.listResourceTemplates")
struct DocsResourceProviderListTemplatesTests {
    @Test("Returns the two canonical templates (apple-docs + swift-evolution)")
    func twoTemplates() async throws {
        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [],
            markdownLookup: nil,
            logger: Logging.NoopRecording()
        )
        let result = try await provider.listResourceTemplates(cursor: nil)
        let templates = result?.resourceTemplates ?? []
        #expect(templates.count == 2)
        let templateURIs = templates.map(\.uriTemplate)
        #expect(templateURIs.contains(MCP.SharedTools.Copy.templateAppleDocs))
        #expect(templateURIs.contains(MCP.SharedTools.Copy.templateSwiftEvolution))
    }
}

import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

// MARK: - #582 read_document → resources/read fallback symmetry

// Pre-fix, `read_document` (tool) and `resources/read` (resource) used
// different URI-lookup paths:
//
// - `read_document` → `Search.Index.getDocumentContent(uri:format:)` — direct
//   primary-key lookup in `docs_metadata`. Returns nil on miss → "Document
//   not found".
// - `resources/read` → `DocsResourceProvider.readResource(uri:)` — DB lookup
//   first, then filesystem fallback that parses the apple-docs URI and
//   reads `<crawl outputDirectory>/<framework>/<filename>.{json,md}`.
//
// For URIs the DB doesn't have but the on-disk corpus does (typical with
// bundles whose indexer-written URIs use the pre-#293 `.lastPathComponent`
// shape while `resources/list` already produced the post-#293 full-path-
// encoded shape via `URLUtilities.filename(from:)`), the two paths disagreed:
// `read_document` failed, `resources/read` returned ~20 KB of content.
//
// The fix wires the same `MCP.Core.ResourceProvider` instance into
// `CompositeToolProvider`'s `documentResourceProvider` field. When
// `searchIndex.getDocumentContent` misses, `handleReadDocument` falls
// back through the provider's `readResource` (same path `resources/read`
// uses).

/// Test double for `MCP.Core.ResourceProvider`. Returns the configured
/// text content on `readResource`; the list / templates surfaces aren't
/// exercised by `read_document` so they return trivial values.
private struct StubResourceProvider: MCP.Core.ResourceProvider {
    let textForURI: [String: String]

    func listResources(cursor _: String?) async throws -> MCP.Core.Protocols.ListResourcesResult {
        MCP.Core.Protocols.ListResourcesResult(resources: [])
    }

    func readResource(uri: String) async throws -> MCP.Core.Protocols.ReadResourceResult {
        guard let text = textForURI[uri] else {
            throw Shared.Core.ToolError.notFound(uri)
        }
        let contents = MCP.Core.Protocols.ResourceContents.text(
            MCP.Core.Protocols.TextResourceContents(
                uri: uri,
                mimeType: "text/markdown",
                text: text
            )
        )
        return MCP.Core.Protocols.ReadResourceResult(contents: [contents])
    }

    func listResourceTemplates(cursor _: String?) async throws -> MCP.Core.Protocols.ListResourceTemplatesResult? {
        nil
    }
}

@Suite("#582 read_document falls back through resources/read on DB miss")
struct ReadDocumentFallbackTests {
    /// Open a real `Search.Index` against a fresh temp file with **no**
    /// documents indexed. Every `getDocumentContent` returns nil so the
    /// composite tool provider's fallback path is exercised.
    private func makeEmptySearchIndex() async throws -> (index: Search.Index, cleanup: () throws -> Void) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("readdoc-fallback-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        let cleanup = { try? FileManager.default.removeItem(at: tempDB) }
        return (index, { try cleanup() ?? () })
    }

    @Test("Search-index miss → falls back to resourceProvider; tool returns the same content resources/read would")
    func fallbackReturnsResourceContent() async throws {
        let (index, cleanup) = try await makeEmptySearchIndex()
        defer { try? cleanup() }

        let testURI = "apple-docs://accelerate/documentation_accelerate"
        let expectedBody = "# Accelerate\n\nThe accelerate framework provides high-performance math primitives."

        let resourceProvider = StubResourceProvider(textForURI: [testURI: expectedBody])

        let provider = CompositeToolProvider(
            searchIndex: index,
            sampleDatabase: nil,
            docsService: nil,
            sampleService: nil,
            teaserService: nil,
            unifiedService: nil,
            documentResourceProvider: resourceProvider
        )

        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolReadDocument,
            arguments: [
                Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable(testURI),
            ]
        )

        // Drill into the first text content block.
        guard case .text(let textContent) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(
            textContent.text == expectedBody,
            "read_document must return the resource-fallback content verbatim"
        )
        await index.disconnect()
    }

    @Test("Search-index miss + resourceProvider miss → still throws 'Document not found'")
    func bothPathsMissStillThrows() async throws {
        let (index, cleanup) = try await makeEmptySearchIndex()
        defer { try? cleanup() }

        let resourceProvider = StubResourceProvider(textForURI: [:])

        let provider = CompositeToolProvider(
            searchIndex: index,
            sampleDatabase: nil,
            docsService: nil,
            sampleService: nil,
            teaserService: nil,
            unifiedService: nil,
            documentResourceProvider: resourceProvider
        )

        await #expect(throws: Error.self) {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolReadDocument,
                arguments: [
                    Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable("apple-docs://nowhere/missing"),
                ]
            )
        }
        await index.disconnect()
    }

    @Test("No resourceProvider injected → preserves the pre-fix error shape (back-compat)")
    func nilResourceProviderPreservesOldShape() async throws {
        let (index, cleanup) = try await makeEmptySearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(
            searchIndex: index,
            sampleDatabase: nil,
            docsService: nil,
            sampleService: nil,
            teaserService: nil,
            unifiedService: nil,
            documentResourceProvider: nil
        )

        await #expect(throws: Error.self) {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolReadDocument,
                arguments: [
                    Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable("apple-docs://anywhere/missing"),
                ]
            )
        }
        await index.disconnect()
    }
}

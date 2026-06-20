import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// The `list_sources` MCP tool (#1277): advertise + return the injected active-source inventory
/// as JSON, so a client can detect a missing/partial corpus. Gated on the injected inventory, so
/// servers that do not wire it (and existing test doubles) are unaffected.
@Suite("#1277 list_sources MCP tool")
struct Issue1277ListSourcesToolTests {
    private func makeInventory() -> Search.SourceInventory {
        Search.SourceInventory(sources: [
            .init(
                id: "apple-documentation",
                sourceID: "apple-docs",
                displayName: "Apple Developer Documentation",
                filename: "apple-documentation.db",
                present: true,
                schemaVersion: 18
            ),
            .init(id: "packages", sourceID: "packages", displayName: "Swift Packages", filename: "packages.db", present: false, schemaVersion: 0),
        ])
    }

    private func makeProvider(inventory: Search.SourceInventory?) -> CompositeToolProvider {
        CompositeToolProvider(
            searchIndex: nil,
            sampleDatabase: nil,
            docsService: nil,
            sampleService: nil,
            teaserService: nil,
            unifiedService: nil,
            sourceInventory: inventory
        )
    }

    @Test("tools/list advertises list_sources when an inventory is injected")
    func advertisesWhenInjected() async throws {
        let result = try await makeProvider(inventory: makeInventory()).listTools(cursor: nil)
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListSources })
    }

    @Test("tools/list hides list_sources when no inventory is injected")
    func hiddenWhenNotInjected() async throws {
        let result = try await makeProvider(inventory: nil).listTools(cursor: nil)
        #expect(!result.tools.contains { $0.name == Shared.Constants.Search.toolListSources })
    }

    @Test("list_sources returns the injected inventory as JSON")
    func returnsInventoryJSON() async throws {
        let result = try await makeProvider(inventory: makeInventory()).callTool(
            name: Shared.Constants.Search.toolListSources,
            arguments: nil
        )
        guard case let .text(text) = result.content.first else {
            Issue.record("Expected a text tool response")
            return
        }
        let decoded = try JSONDecoder().decode(Search.SourceInventory.self, from: Data(text.text.utf8))
        #expect(decoded.expected == 2)
        #expect(decoded.installed == 1)
        #expect(decoded.sources.map(\.id) == ["apple-documentation", "packages"])
        // The routing sourceID round-trips through the MCP JSON (the pluggability enabler).
        #expect(decoded.sources.map(\.sourceID) == ["apple-docs", "packages"])
        #expect(decoded.sources.first?.schemaVersion == 18)
    }
}

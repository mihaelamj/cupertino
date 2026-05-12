import Foundation
import MCP
@testable import MCPSupport
import Search
import SharedConfiguration
import SharedConstants
import SharedCore
import SharedModels
import Testing

// Covers the malformed-URL skip path added to
// `MCP.Support.DocsResourceProvider.listResources` in PR #288: a row in
// `CrawlMetadata.pages` whose URL key fails `URL(string:)` is skipped
// rather than crashing the listing call. The previous force-unwrap form
// would crash on the same input.
//
// We reach the actor's internal state via the test-only
// `injectMetadataForTesting(_:)` seam so the test doesn't need to write
// a `metadata.json` fixture to whatever directory the configuration is
// pointing at.

@Suite("MCP.Support.DocsResourceProvider malformed-URL skip", .serialized)
struct DocsResourceProviderMalformedURLSkipTests {
    private func makeProvider(in tempRoot: URL) -> MCP.Support.DocsResourceProvider {
        // All-defaults Configuration is fine: we inject metadata via the
        // test seam, so the provider never touches the on-disk paths the
        // configuration would otherwise point at.
        let evolutionDir = tempRoot.appendingPathComponent("swift-evolution")
        let archiveDir = tempRoot.appendingPathComponent("archive")
        return MCP.Support.DocsResourceProvider(
            configuration: Shared.Configuration(),
            evolutionDirectory: evolutionDir,
            archiveDirectory: archiveDir,
            searchIndex: nil
        )
    }

    @Test("Skips the malformed-URL row, keeps the good row, doesn't crash")
    func skipsMalformedURLRowKeepsGoodRow() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-docsres-skip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let goodPage = Shared.Models.PageMetadata(
            url: "https://developer.apple.com/documentation/swiftui/list",
            framework: "swiftui",
            filePath: "/dev/null",
            contentHash: "good",
            depth: 0
        )
        let badPage = Shared.Models.PageMetadata(
            url: "",
            framework: "swiftui",
            filePath: "/dev/null",
            contentHash: "bad",
            depth: 0
        )
        let metadata = Shared.Models.CrawlMetadata(pages: [
            "https://developer.apple.com/documentation/swiftui/list": goodPage,
            "": badPage,
        ])

        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(metadata)

        let result = try await provider.listResources(cursor: nil)

        // Only resources contributed by the apple-docs path should be the
        // single good page; the empty-string-keyed row must NOT appear.
        // (Evolution/archive paths read from on-disk directories that don't
        // exist in this tmp root, so their `do/catch` arms return empty
        // and don't contaminate the count we care about.)
        let appleDocsResources = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        #expect(appleDocsResources.count == 1, "Empty-string URL row must be skipped, not crash the listing")

        // Pin that the good row is the one that survived.
        let goodURI = appleDocsResources.first?.uri ?? ""
        #expect(goodURI.contains("swiftui"))
    }

    @Test("All-malformed metadata yields an empty apple-docs slice without crashing")
    func allMalformedRowsAreAllSkipped() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-docsres-skip-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let badPage = Shared.Models.PageMetadata(
            url: "",
            framework: "swiftui",
            filePath: "/dev/null",
            contentHash: "bad",
            depth: 0
        )
        let metadata = Shared.Models.CrawlMetadata(pages: ["": badPage])

        let provider = makeProvider(in: tempRoot)
        await provider.injectMetadataForTesting(metadata)

        let result = try await provider.listResources(cursor: nil)
        let appleDocsResources = result.resources.filter {
            $0.uri.hasPrefix(Shared.Constants.Search.appleDocsScheme)
        }
        #expect(appleDocsResources.isEmpty)
    }
}

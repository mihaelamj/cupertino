@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import SwiftBookSource
import Testing

// MARK: - #1082 — corpusDirectoryAlias routing

//
// Focused tests for the post-#1082 view-source-directory routing:
//
//   1. `makeDocsIndexingDirectoryByKey` resolves an aliased provider
//      to the parent's URL (default path).
//
//   2. When a `--<parent>-dir` override is supplied, the aliased
//      provider inherits the SAME override (not the default path).
//
//   3. An explicit `--<aliased>-dir` override still wins over the
//      inherited parent value (rare but well-defined).
//
//   4. `resolveSourceDirectory(for: swiftBook, ...)` returns a real
//      URL (not nil, not `/dev/null`) when `directoryByKey` carries
//      a valid swift-book entry — the load-bearing wiring assertion
//      for #1082.

@Suite("#1082 — corpusDirectoryAlias propagation")
struct Issue1082CorpusDirectoryAliasTests {
    @Test("Aliased provider inherits parent's default directory (no override)")
    func aliasedInheritsParentDefault() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let paths = Shared.Paths.live()
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths
        )
        let parentURL = dict[Shared.Constants.SourcePrefix.swiftOrg] ?? nil
        let aliasedURL = dict[Shared.Constants.SourcePrefix.swiftBook] ?? nil
        #expect(parentURL != nil, "swift-org has fetchInfo with .swiftOrg key; resolver must populate")
        #expect(aliasedURL == parentURL, "swift-book is aliased to swift-org and must inherit its URL")
    }

    @Test("Aliased provider inherits parent's --<parent>-dir override")
    func aliasedInheritsParentOverride() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let paths = Shared.Paths.live()
        let customURL = URL(fileURLWithPath: "/Volumes/External/custom-swift-corpus")
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths,
            overrides: [Shared.Constants.SourcePrefix.swiftOrg: customURL]
        )
        let parentURL = dict[Shared.Constants.SourcePrefix.swiftOrg] ?? nil
        let aliasedURL = dict[Shared.Constants.SourcePrefix.swiftBook] ?? nil
        #expect(parentURL?.path == customURL.resolvingSymlinksInPath().path)
        #expect(
            aliasedURL?.path == customURL.resolvingSymlinksInPath().path,
            "view-source must inherit parent's override, not fall back to default"
        )
    }

    @Test("Explicit --<aliased>-dir override wins over inherited parent value")
    func explicitAliasedOverrideWinsOverInheritance() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let paths = Shared.Paths.live()
        let parentOverride = URL(fileURLWithPath: "/tmp/parent-override")
        let aliasedOverride = URL(fileURLWithPath: "/tmp/aliased-override")
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths,
            overrides: [
                Shared.Constants.SourcePrefix.swiftOrg: parentOverride,
                Shared.Constants.SourcePrefix.swiftBook: aliasedOverride,
            ]
        )
        let parentURL = dict[Shared.Constants.SourcePrefix.swiftOrg] ?? nil
        let aliasedURL = dict[Shared.Constants.SourcePrefix.swiftBook] ?? nil
        #expect(parentURL?.path == parentOverride.resolvingSymlinksInPath().path)
        #expect(
            aliasedURL?.path == aliasedOverride.resolvingSymlinksInPath().path,
            "explicit aliased override must win over inheritance"
        )
    }

    @Test("resolveSourceDirectory(swift-book) returns swift-org's URL (not /dev/null, not nil)")
    func resolverReturnsRealURLForViewSource() throws {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let provider = try #require(
            registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.swiftBook },
            "SwiftBookSource must be in the production registry"
        )
        let swiftOrgURL = URL(fileURLWithPath: "/tmp/swift-org-corpus")
        let input = Search.DocsIndexingInput(
            searchDBPath: URL(fileURLWithPath: "/tmp/search.db"),
            docsDirectory: URL(fileURLWithPath: "/tmp/docs"),
            evolutionDirectory: nil,
            swiftOrgDirectory: swiftOrgURL,
            archiveDirectory: nil,
            higDirectory: nil,
            clearExisting: false,
            markdownStrategy: NoopMarkdownStrategy(),
            sampleCatalogProvider: NoopSampleCatalogProvider(),
            directoryByKey: [
                Shared.Constants.SourcePrefix.swiftOrg: swiftOrgURL,
                Shared.Constants.SourcePrefix.swiftBook: swiftOrgURL,
            ]
        )
        let resolved = CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(
            for: provider,
            input: input
        )
        #expect(
            resolved?.path == swiftOrgURL.path,
            "Pre-#1082 returned /dev/null; post-fix returns swift-org's URL via directoryByKey"
        )
        #expect(resolved?.path != "/dev/null")
    }
}

// MARK: - Test fixtures

import LoggingModels

private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

private struct NoopSampleCatalogProvider: Search.SampleCatalogProvider {
    func fetch() async -> Search.SampleCatalogState {
        .loaded(entries: [])
    }
}

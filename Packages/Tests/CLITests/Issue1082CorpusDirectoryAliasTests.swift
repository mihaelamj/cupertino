@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #1082 — corpusDirectoryAlias routing (protocol seam still present, no production user post-#1093)

//
// #1082 introduced `Search.SourceProvider.corpusDirectoryAlias` as
// the view-source-directory routing seam. SwiftBookSource was its
// first (and only) consumer. #1093 split swift-book into an
// independently-fetchable source with its own corpus dir, so
// SwiftBookSource no longer overrides this property.
//
// The protocol seam stays for future view-sources (e.g. a tutorial
// source that piggybacks on apple-docs's corpus). These tests use a
// fake provider to pin the resolver's alias-propagation logic so a
// future view-source can rely on it.

private struct ContractFakeAliasedProvider: Search.SourceProvider {
    static let fakeID = "issue-1082-fake-aliased"
    static let parentSourceID = Shared.Constants.SourcePrefix.swiftOrg

    let definition = Search.SourceDefinition(
        id: ContractFakeAliasedProvider.fakeID,
        displayName: "Issue 1082 Fake Aliased Provider",
        emoji: "🧪",
        properties: Search.SourceProperties(
            authority: 0.5,
            freshness: 0.5,
            comprehensiveness: 0.5,
            codeExamples: 0.5,
            hasAvailability: 0.5,
            designFocus: 0.5,
            languageFocus: 0.5,
            searchQuality: 0.5
        ),
        intents: [.howTo]
    )

    var destinationDB: Shared.Models.DatabaseDescriptor {
        .swiftOrg
    }

    var fetchInfo: Search.FetchInfo? {
        nil
    } // view-source has no own fetch
    var corpusDirectoryAlias: String? {
        Self.parentSourceID
    }

    var capabilities: Search.Capabilities {
        Search.Capabilities(searchers: [.text], operations: [.readByURI])
    }

    var legacySourceIDAliases: Set<String> {
        []
    }

    func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        preconditionFailure("Contract test never invokes makeStrategy")
    }

    func makeIndexer() -> any Search.SourceIndexer {
        preconditionFailure("Contract test never invokes makeIndexer")
    }
}

@Suite("#1082 — corpusDirectoryAlias propagation (protocol seam pinned via fake provider)")
struct Issue1082CorpusDirectoryAliasTests {
    private func registryWithFakeAliased() -> Search.SourceRegistry {
        var registry = CLIImpl.makeProductionSourceRegistry()
        registry.register(ContractFakeAliasedProvider())
        return registry
    }

    @Test("Aliased provider inherits parent's default directory (no override)")
    func aliasedInheritsParentDefault() {
        let registry = registryWithFakeAliased()
        let paths = Shared.Paths.live()
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths
        )
        let parentURL = dict[ContractFakeAliasedProvider.parentSourceID] ?? nil
        let aliasedURL = dict[ContractFakeAliasedProvider.fakeID] ?? nil
        #expect(parentURL != nil, "swift-org has fetchInfo with .swiftOrg key; resolver must populate")
        #expect(aliasedURL == parentURL, "fake provider is aliased to swift-org and must inherit its URL")
    }

    @Test("Aliased provider inherits parent's --<parent>-dir override")
    func aliasedInheritsParentOverride() {
        let registry = registryWithFakeAliased()
        let paths = Shared.Paths.live()
        let customURL = URL(fileURLWithPath: "/Volumes/External/custom-swift-corpus")
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths,
            overrides: [ContractFakeAliasedProvider.parentSourceID: customURL]
        )
        let parentURL = dict[ContractFakeAliasedProvider.parentSourceID] ?? nil
        let aliasedURL = dict[ContractFakeAliasedProvider.fakeID] ?? nil
        #expect(parentURL?.path == customURL.resolvingSymlinksInPath().path)
        #expect(
            aliasedURL?.path == customURL.resolvingSymlinksInPath().path,
            "view-source must inherit parent's override, not fall back to default"
        )
    }

    @Test("Explicit --<aliased>-dir override wins over inherited parent value")
    func explicitAliasedOverrideWinsOverInheritance() {
        let registry = registryWithFakeAliased()
        let paths = Shared.Paths.live()
        let parentOverride = URL(fileURLWithPath: "/tmp/parent-override")
        let aliasedOverride = URL(fileURLWithPath: "/tmp/aliased-override")
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths,
            overrides: [
                ContractFakeAliasedProvider.parentSourceID: parentOverride,
                ContractFakeAliasedProvider.fakeID: aliasedOverride,
            ]
        )
        let parentURL = dict[ContractFakeAliasedProvider.parentSourceID] ?? nil
        let aliasedURL = dict[ContractFakeAliasedProvider.fakeID] ?? nil
        #expect(parentURL?.path == parentOverride.resolvingSymlinksInPath().path)
        #expect(
            aliasedURL?.path == aliasedOverride.resolvingSymlinksInPath().path,
            "explicit aliased override must win over inheritance"
        )
    }

    @Test("Post-#1093: no shipping source overrides corpusDirectoryAlias (sentinel)")
    func noProductionAliasedProvider() {
        // Pin that the seam exists but is unused in production. If
        // a future source adopts the view-source pattern, this test
        // becomes a candidate for removal/reframe. SwiftBookSource
        // used to be the only consumer; #1093 split it out.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let aliasedProviders = registry.allEnabled.filter { $0.corpusDirectoryAlias != nil }
        #expect(
            aliasedProviders.isEmpty,
            "No production source overrides corpusDirectoryAlias post-#1093"
        )
    }
}

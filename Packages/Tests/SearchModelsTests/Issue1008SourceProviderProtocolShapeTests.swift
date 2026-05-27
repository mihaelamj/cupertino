import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #1008 SourceProvider protocol shape

/// Pins the load-bearing shape of `Search.SourceProvider` +
/// `Search.SourceRegistry` + `Search.FetchInfo` +
/// `Search.IndexEnvironment` introduced by epic #1007 Phase 1A.
/// A rename or required-member deletion breaks these tests before
/// downstream per-source target conformers (`<X>Source/`) discover
/// the drift mid-compile.
@Suite("#1008: SourceProvider / SourceRegistry / FetchInfo shape pins")
struct Issue1008SourceProviderProtocolShapeTests {
    // MARK: - SourceRegistry round-trip

    @Test("Empty registry has count 0 and isEmpty true")
    func emptyRegistry() {
        let registry = Search.SourceRegistry()
        #expect(registry.isEmpty)
        #expect(registry.all.isEmpty)
        #expect(registry.allEnabled.isEmpty)
        #expect(registry.provider(for: "anything") == nil)
    }

    @Test("Register populates the registry; lookup by id returns the provider")
    func registerAndLookup() {
        var registry = Search.SourceRegistry()
        registry.register(FixtureProvider(idValue: "fixture-a"))
        registry.register(FixtureProvider(idValue: "fixture-b"))
        #expect(registry.count == 2)
        #expect(!registry.isEmpty)
        #expect(registry.provider(for: "fixture-a")?.definition.id == "fixture-a")
        #expect(registry.provider(for: "fixture-b")?.definition.id == "fixture-b")
        #expect(registry.provider(for: "nope") == nil)
    }

    @Test("Re-register on the same id replaces the entry, preserves insertion-order slot")
    func reregisterIdempotent() {
        var registry = Search.SourceRegistry()
        registry.register(FixtureProvider(idValue: "a", displayNameValue: "first"))
        registry.register(FixtureProvider(idValue: "b", displayNameValue: "second"))
        registry.register(FixtureProvider(idValue: "a", displayNameValue: "first-replaced"))
        #expect(registry.count == 2)
        #expect(registry.all.map(\.definition.displayName) == ["first-replaced", "second"])
    }

    @Test("setEnabled toggles entry visibility in allEnabled but keeps the entry registered")
    func enabledToggle() {
        var registry = Search.SourceRegistry()
        registry.register(FixtureProvider(idValue: "a"))
        registry.register(FixtureProvider(idValue: "b"))
        registry.setEnabled(false, forSourceID: "a")
        #expect(registry.count == 2)
        #expect(registry.allEnabled.map(\.definition.id) == ["b"])
        #expect(registry.provider(for: "a") == nil) // disabled providers are hidden from lookup
        #expect(registry.entry(for: "a")?.isEnabled == false) // but the entry survives
    }

    @Test("Re-register preserves a prior `isEnabled: false` flag when isEnabled: is not passed explicitly")
    func reregisterPreservesDisabledFlag() {
        var registry = Search.SourceRegistry()
        registry.register(FixtureProvider(idValue: "a"))
        registry.setEnabled(false, forSourceID: "a")
        #expect(registry.entry(for: "a")?.isEnabled == false)

        // Re-register without passing isEnabled: operator's earlier disable
        // MUST be preserved. Pre-#1008-critic-fix, the default `isEnabled: true`
        // silently clobbered the disabled state on this call path.
        registry.register(FixtureProvider(idValue: "a", displayNameValue: "replaced"))
        #expect(registry.entry(for: "a")?.isEnabled == false) // still disabled
        #expect(registry.entry(for: "a")?.provider.definition.displayName == "replaced") // but provider replaced
        #expect(registry.provider(for: "a") == nil) // still hidden from lookup

        // Explicit re-enable on re-register is honored.
        registry.register(FixtureProvider(idValue: "a"), isEnabled: true)
        #expect(registry.entry(for: "a")?.isEnabled == true)
        #expect(registry.provider(for: "a") != nil)
    }

    @Test("Iteration preserves insertion order, not id order")
    func iterationOrder() {
        var registry = Search.SourceRegistry()
        registry.register(FixtureProvider(idValue: "z"))
        registry.register(FixtureProvider(idValue: "a"))
        registry.register(FixtureProvider(idValue: "m"))
        #expect(registry.all.map(\.definition.id) == ["z", "a", "m"])
    }

    // MARK: - FetchInfo equality + DefaultOutputDirKey cases

    @Test("DefaultOutputDirKey covers the 8 path keys the CLI resolves")
    func fetchInfoOutputDirCases() {
        let cases = Search.FetchInfo.DefaultOutputDirKey.allCases
        // The 8 keys correspond to the pre-#1007 FetchType enum's defaultOutputDir(paths:)
        // switch arms (docs/swift/evolution/packages/code-or-samples/archive/hig/all).
        #expect(cases.count == 9)
        #expect(cases.contains(.docs))
        #expect(cases.contains(.swiftOrg))
        #expect(cases.contains(.swiftEvolution))
        #expect(cases.contains(.packages))
        #expect(cases.contains(.sampleCode))
        #expect(cases.contains(.archive))
        #expect(cases.contains(.hig))
        #expect(cases.contains(.baseDirectory))
    }

    @Test("FetchInfo equality based on all stored fields")
    func fetchInfoEquatable() {
        let lhs = Search.FetchInfo(
            displayName: "Apple Documentation",
            sourceID: "apple-docs",
            crawlBaseURLs: ["https://developer.apple.com/documentation"],
            defaultOutputDirKey: .docs,
            isWebCrawlable: true
        )
        var rhs = lhs
        #expect(lhs == rhs)
        rhs = Search.FetchInfo(
            displayName: "Different",
            sourceID: "apple-docs",
            crawlBaseURLs: ["https://developer.apple.com/documentation"],
            defaultOutputDirKey: .docs,
            isWebCrawlable: true
        )
        #expect(lhs != rhs)
    }
}

// MARK: - Fixture conformer

/// Minimal `Search.SourceProvider` conformer for protocol-shape pins.
/// Production conformers live in per-source SPM targets
/// (`<X>Source/`); this fixture stays in the test target.
private struct FixtureProvider: Search.SourceProvider {
    let idValue: String
    let displayNameValue: String

    init(idValue: String, displayNameValue: String = "Fixture") {
        self.idValue = idValue
        self.displayNameValue = displayNameValue
    }

    var definition: Search.SourceDefinition {
        Search.SourceDefinition(
            id: idValue,
            displayName: displayNameValue,
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
            intents: [.howTo],
            intentPriority: [.howTo: 50],
            baseURL: nil
        )
    }

    var fetchInfo: Search.FetchInfo? { nil }

    var destinationDB: Shared.Models.DatabaseDescriptor { .search }

    func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        FixtureStrategy(source: idValue)
    }

    func makeIndexer() -> any Search.SourceIndexer {
        FixtureIndexer(sourceIDValue: idValue, displayNameValue: displayNameValue)
    }
}

private struct FixtureStrategy: Search.SourceIndexingStrategy {
    let source: String

    func indexItems(
        into _: any Search.Database & Search.IndexWriter,
        progress _: (any Search.IndexingProgressReporting)?
    ) async throws -> Search.IndexStats {
        Search.IndexStats(source: source, indexed: 0, skipped: 0)
    }
}

private struct FixtureIndexer: Search.SourceIndexer {
    let sourceIDValue: String
    let displayNameValue: String
    var sourceID: String { sourceIDValue }
    var displayName: String { displayNameValue }
}

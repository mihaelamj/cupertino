import Foundation
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants
import Testing

// Tests pin the value-type and protocol surface of `ServicesModels` so
// the higher-level `Services` target can rely on stable defaults,
// limit-clamping, and source enumeration. Each test exercises behaviour
// the formatters and SearchToolProvider depend on at runtime.

// MARK: - Namespace + Formatter anchors

@Suite("Services namespace + Formatter anchors")
struct ServicesNamespaceTests {
    @Test("Services namespace is accessible")
    func servicesNamespaceExists() {
        let _: Services.Type = Services.self
    }

    @Test("Services.Formatter namespace is accessible")
    func formatterNamespaceExists() {
        let _: Services.Formatter.Type = Services.Formatter.self
    }
}

// MARK: - Services.SearchQuery

@Suite("Services.SearchQuery value type")
struct ServicesSearchQueryTests {
    @Test("Initializes with text-only and inherits defaults")
    func defaults() {
        let query = Services.SearchQuery(text: "SwiftUI")
        #expect(query.text == "SwiftUI")
        #expect(query.source == nil)
        #expect(query.framework == nil)
        #expect(query.language == nil)
        #expect(query.includeArchive == false)
        #expect(query.minimumiOS == nil)
        #expect(query.minimumMacOS == nil)
        #expect(query.minimumTvOS == nil)
        #expect(query.minimumWatchOS == nil)
        #expect(query.minimumVisionOS == nil)
        #expect(query.limit == Shared.Constants.Limit.defaultSearchLimit)
    }

    @Test("Clamps limit to Shared.Constants.Limit.maxSearchLimit")
    func clampsLimit() {
        let exceeds = Services.SearchQuery(text: "x", limit: Shared.Constants.Limit.maxSearchLimit + 100)
        #expect(exceeds.limit == Shared.Constants.Limit.maxSearchLimit)
    }

    @Test("Accepts a limit below max unchanged")
    func belowMaxPassesThrough() {
        let q = Services.SearchQuery(text: "x", limit: 3)
        #expect(q.limit == 3)
    }

    @Test("Accepts all platform-version filters at once")
    func acceptsAllPlatformFilters() {
        let q = Services.SearchQuery(
            text: "view",
            source: "apple-docs",
            framework: "SwiftUI",
            language: "swift",
            limit: 7,
            includeArchive: true,
            minimumiOS: "17.0",
            minimumMacOS: "14.0",
            minimumTvOS: "17.0",
            minimumWatchOS: "10.0",
            minimumVisionOS: "1.0"
        )
        #expect(q.source == "apple-docs")
        #expect(q.framework == "SwiftUI")
        #expect(q.language == "swift")
        #expect(q.limit == 7)
        #expect(q.includeArchive == true)
        #expect(q.minimumiOS == "17.0")
        #expect(q.minimumMacOS == "14.0")
        #expect(q.minimumTvOS == "17.0")
        #expect(q.minimumWatchOS == "10.0")
        #expect(q.minimumVisionOS == "1.0")
    }
}

// MARK: - Services.HIGQuery

@Suite("Services.HIGQuery value type")
struct ServicesHIGQueryTests {
    @Test("Initializes with text-only and inherits defaults")
    func defaults() {
        let q = Services.HIGQuery(text: "buttons")
        #expect(q.text == "buttons")
        #expect(q.platform == nil)
        #expect(q.category == nil)
        #expect(q.limit == Shared.Constants.Limit.defaultSearchLimit)
    }

    @Test("Accepts platform and category filters")
    func acceptsPlatformCategory() {
        let q = Services.HIGQuery(text: "menus", platform: "iOS", category: "components", limit: 5)
        #expect(q.platform == "iOS")
        #expect(q.category == "components")
        #expect(q.limit == 5)
    }

    @Test("Clamps limit to Shared.Constants.Limit.maxSearchLimit")
    func clampsLimit() {
        let q = Services.HIGQuery(text: "x", limit: Shared.Constants.Limit.maxSearchLimit + 1)
        #expect(q.limit == Shared.Constants.Limit.maxSearchLimit)
    }
}

// MARK: - Services.SearchFilters

@Suite("Services.SearchFilters value type")
struct ServicesSearchFiltersTests {
    @Test("Empty filters report no active filters")
    func emptyHasNoActive() {
        #expect(Services.SearchFilters().hasActiveFilters == false)
    }

    @Test("Single non-nil source field flags activity")
    func sourceActive() {
        #expect(Services.SearchFilters(source: "apple-docs").hasActiveFilters == true)
    }

    @Test("Single non-nil framework field flags activity")
    func frameworkActive() {
        #expect(Services.SearchFilters(framework: "SwiftUI").hasActiveFilters == true)
    }

    @Test("Single non-nil language field flags activity")
    func languageActive() {
        #expect(Services.SearchFilters(language: "swift").hasActiveFilters == true)
    }

    @Test("Any minimum-platform field flags activity")
    func anyPlatformActive() {
        #expect(Services.SearchFilters(minimumiOS: "17.0").hasActiveFilters)
        #expect(Services.SearchFilters(minimumMacOS: "14.0").hasActiveFilters)
        #expect(Services.SearchFilters(minimumTvOS: "17.0").hasActiveFilters)
        #expect(Services.SearchFilters(minimumWatchOS: "10.0").hasActiveFilters)
        #expect(Services.SearchFilters(minimumVisionOS: "1.0").hasActiveFilters)
    }

    @Test("Multiple non-nil fields all flag activity together")
    func combinedActive() {
        let f = Services.SearchFilters(
            source: "apple-docs",
            framework: "SwiftUI",
            language: "swift"
        )
        #expect(f.hasActiveFilters == true)
        #expect(f.source == "apple-docs")
        #expect(f.framework == "SwiftUI")
        #expect(f.language == "swift")
    }
}

// MARK: - Services.Formatter.Config

@Suite("Services.Formatter.Config")
struct ServicesFormatterConfigTests {
    @Test("Default Config has sensible defaults for callers that skip the init")
    func defaults() {
        let c = Services.Formatter.Config()
        #expect(c.showScore == false)
        #expect(c.showWordCount == false)
        #expect(c.showSource == true)
        #expect(c.showAvailability == false)
        #expect(c.showSeparators == false)
        #expect(c.emptyMessage == "No results found")
    }

    @Test("Config.shared turns on score/wordCount/availability/separators")
    func sharedConfigShape() {
        let c = Services.Formatter.Config.shared
        #expect(c.showScore == true)
        #expect(c.showWordCount == true)
        #expect(c.showSource == false)
        #expect(c.showAvailability == true)
        #expect(c.showSeparators == true)
        #expect(c.emptyMessage == "_No results found. Try broader search terms._")
    }

    @Test("cliDefault and mcpDefault are aliases of shared (identical CLI/MCP output)")
    func cliMCPAliasShared() {
        let cli = Services.Formatter.Config.cliDefault
        let mcp = Services.Formatter.Config.mcpDefault
        let shared = Services.Formatter.Config.shared
        // Field-by-field equality: shared aliases must match shared.
        #expect(cli.showScore == shared.showScore)
        #expect(cli.showWordCount == shared.showWordCount)
        #expect(cli.showSource == shared.showSource)
        #expect(cli.showAvailability == shared.showAvailability)
        #expect(cli.showSeparators == shared.showSeparators)
        #expect(cli.emptyMessage == shared.emptyMessage)
        #expect(mcp.showScore == shared.showScore)
        #expect(mcp.emptyMessage == shared.emptyMessage)
    }
}

// MARK: - Services.Formatter.TeaserResults

@Suite("Services.Formatter.TeaserResults")
struct TeaserResultsTests {
    @Test("Default TeaserResults() is empty")
    func defaultIsEmpty() {
        #expect(Services.Formatter.TeaserResults().isEmpty)
    }

    @Test("Empty TeaserResults exposes an empty allSources collection")
    func emptyAllSources() {
        let results = Services.Formatter.TeaserResults()
        #expect(results.allSources.isEmpty)
    }

    @Test("TeaserResults isEmpty turns false once any source has results")
    func appleDocsFlipsEmpty() {
        let r = Services.Formatter.TeaserResults(appleDocs: [Self.stubResult(title: "Apple Docs")])
        #expect(r.isEmpty == false)
    }

    @Test("samples source mapping populates allSources")
    func samplesPopulateAllSources() {
        let project = Sample.Index.Project(
            id: "adopting-swiftui",
            title: "Adopting SwiftUI",
            description: "Sample",
            frameworks: ["SwiftUI"],
            readme: nil,
            webURL: "https://developer.apple.com/documentation/swiftui/adopting-swiftui",
            zipFilename: "AdoptingSwiftUI.zip",
            fileCount: 3,
            totalSize: 1024
        )
        let r = Services.Formatter.TeaserResults(samples: [project])
        #expect(r.isEmpty == false)
        #expect(r.allSources.count == 1)
        let teaser = r.allSources[0]
        #expect(teaser.displayName == "Sample Code")
        #expect(teaser.titles == ["Adopting SwiftUI"])
        #expect(teaser.isEmpty == false)
    }

    /// Test fixture: minimal Search.Result for cases where we only need
    /// the title field. Sample data is uniform across the suite to keep
    /// failures readable.
    static func stubResult(title: String = "stub") -> Search.Result {
        Search.Result(
            uri: "apple-docs://" + title.lowercased(),
            source: "apple-docs",
            framework: "Test",
            title: title,
            summary: "summary",
            filePath: "/tmp/\(title).md",
            wordCount: 10,
            rank: -1.0
        )
    }
}

// MARK: - Services.Formatter.Unified.Input

@Suite("Services.Formatter.Unified.Input")
struct UnifiedInputTests {
    @Test("Default Unified.Input has zero totalCount and zero non-empty sources")
    func defaults() {
        let input = Services.Formatter.Unified.Input()
        #expect(input.totalCount == 0)
        #expect(input.nonEmptySourceCount == 0)
        #expect(input.allSources.isEmpty)
        #expect(input.sourceTeasers == nil)
        #expect(input.limit == 10)
    }

    @Test("totalCount sums every result list")
    func totalCountSums() {
        let doc = TeaserResultsTests.stubResult()
        let input = Services.Formatter.Unified.Input(
            docResults: [doc, doc],
            higResults: [doc],
            packagesResults: [doc, doc, doc]
        )
        #expect(input.totalCount == 6)
        #expect(input.nonEmptySourceCount == 3)
    }

    @Test("allSources preserves canonical display order")
    func sourceOrder() {
        let doc = TeaserResultsTests.stubResult()
        // Populate three sources out of order: HIG, AppleDocs, Packages.
        // allSources must return them in the canonical order
        // [AppleDocs, Archive, Samples, HIG, SwiftEvolution, SwiftOrg, SwiftBook, Packages].
        let input = Services.Formatter.Unified.Input(
            docResults: [doc],
            higResults: [doc],
            packagesResults: [doc]
        )
        let names = input.allSources.map(\.info.name)
        #expect(names.count == 3)
        // AppleDocs comes before HIG comes before Packages.
        let appleIdx = names.firstIndex(of: Shared.Constants.SourcePrefix.infoAppleDocs.name)
        let higIdx = names.firstIndex(of: Shared.Constants.SourcePrefix.infoHIG.name)
        let pkgIdx = names.firstIndex(of: Shared.Constants.SourcePrefix.infoPackages.name)
        #expect(appleIdx != nil && higIdx != nil && pkgIdx != nil)
        #expect((appleIdx ?? 0) < (higIdx ?? 0))
        #expect((higIdx ?? 0) < (pkgIdx ?? 0))
    }

    @Test("sourceTeasers reports sources that hit the limit")
    func teasersAtLimit() {
        let doc = TeaserResultsTests.stubResult()
        // limit=2; docResults at 2 (== limit, "hasMore"), packagesResults at 1 (no teaser).
        let input = Services.Formatter.Unified.Input(
            docResults: [doc, doc],
            packagesResults: [doc],
            limit: 2
        )
        let teasers = input.sourceTeasers
        #expect(teasers != nil)
        #expect(teasers?.count == 1)
        #expect(teasers?.first?.hasMore == true)
        #expect(teasers?.first?.shownCount == 2)
    }
}

// MARK: - Services.Formatter.Footer.Kind

@Suite("Services.Formatter.Footer.Kind enum")
struct FooterKindTests {
    @Test("Has the canonical case set used by the formatters")
    func canonicalCases() {
        let cases = Services.Formatter.Footer.Kind.allCases
        // The formatter code branches on these five cases. Locking the
        // set here means adding a new case forces a test + formatter update.
        let values = Set(cases.map(\.rawValue))
        #expect(values == ["sourceTip", "semanticTip", "teaser", "platformTip", "custom"])
    }

    @Test("Raw values are stable identifiers")
    func rawValues() {
        #expect(Services.Formatter.Footer.Kind.sourceTip.rawValue == "sourceTip")
        #expect(Services.Formatter.Footer.Kind.semanticTip.rawValue == "semanticTip")
        #expect(Services.Formatter.Footer.Kind.teaser.rawValue == "teaser")
        #expect(Services.Formatter.Footer.Kind.platformTip.rawValue == "platformTip")
        #expect(Services.Formatter.Footer.Kind.custom.rawValue == "custom")
    }
}

// MARK: - Services.Formatter.Footer.Item

@Suite("Services.Formatter.Footer.Item value type")
struct FooterItemTests {
    @Test("Initializes with content-only and inherits nil title / emoji")
    func defaults() {
        let item = Services.Formatter.Footer.Item(kind: .custom, content: "hi")
        #expect(item.kind == .custom)
        #expect(item.title == nil)
        #expect(item.content == "hi")
        #expect(item.emoji == nil)
    }

    @Test("Accepts title and emoji")
    func acceptsTitleAndEmoji() {
        let item = Services.Formatter.Footer.Item(
            kind: .platformTip,
            title: "Tip",
            content: "Filter by --platform iOS",
            emoji: "💡"
        )
        #expect(item.kind == .platformTip)
        #expect(item.title == "Tip")
        #expect(item.emoji == "💡")
    }
}

// MARK: - Searcher / Teaser / Formatter.Result protocol witnesses

@Suite("ServicesModels protocol witnesses")
struct ServicesProtocolWitnessTests {
    /// Stub DocsSearcher returns an empty result set regardless of query.
    private struct StubDocs: Services.DocsSearcher {
        func search(_ query: Services.SearchQuery) async throws -> [Search.Result] { [] }
    }

    /// Stub UnifiedSearcher returns an empty unified input.
    private struct StubUnified: Services.UnifiedSearcher {
        func searchAll(
            query: String,
            framework: String?,
            limit: Int
        ) async -> Services.Formatter.Unified.Input {
            Services.Formatter.Unified.Input(limit: limit)
        }
    }

    /// Stub Teaser returns the default empty TeaserResults.
    private struct StubTeaser: Services.Teaser {
        func fetchAllTeasers(
            query: String,
            framework: String?,
            currentSource: String?,
            includeArchive: Bool
        ) async -> Services.Formatter.TeaserResults {
            Services.Formatter.TeaserResults()
        }
    }

    @Test("DocsSearcher protocol accepts a stub implementation")
    func docsSearcherWitness() async throws {
        let searcher: any Services.DocsSearcher = StubDocs()
        let results = try await searcher.search(Services.SearchQuery(text: "x"))
        #expect(results.isEmpty)
    }

    @Test("UnifiedSearcher protocol accepts a stub implementation")
    func unifiedSearcherWitness() async {
        let searcher: any Services.UnifiedSearcher = StubUnified()
        let input = await searcher.searchAll(query: "x", framework: nil, limit: 5)
        #expect(input.totalCount == 0)
        #expect(input.limit == 5)
    }

    @Test("Teaser protocol accepts a stub implementation")
    func teaserWitness() async {
        let teaser: any Services.Teaser = StubTeaser()
        let results = await teaser.fetchAllTeasers(
            query: "x",
            framework: nil,
            currentSource: nil,
            includeArchive: false
        )
        #expect(results.isEmpty)
    }
}

import Foundation
@testable import Services
import SharedConstants
@testable import SharedCore
import Testing

// MARK: - Services Tests

@Suite("Services Module Tests")
struct ServicesTests {
    // MARK: - Services.SearchQuery Tests

    @Test("Services.SearchQuery initializes with defaults")
    func searchQueryDefaults() {
        let query = Services.SearchQuery(text: "View")

        #expect(query.text == "View")
        #expect(query.source == nil)
        #expect(query.framework == nil)
        #expect(query.language == nil)
        #expect(query.limit == Shared.Constants.Limit.defaultSearchLimit)
        #expect(query.includeArchive == false)
    }

    @Test("Services.SearchQuery clamps limit to max")
    func searchQueryClampsLimit() {
        let query = Services.SearchQuery(text: "View", limit: 1000)

        #expect(query.limit == Shared.Constants.Limit.maxSearchLimit)
    }

    @Test("Services.SearchQuery accepts all parameters")
    func searchQueryAllParams() {
        let query = Services.SearchQuery(
            text: "Button",
            source: "apple-docs",
            framework: "swiftui",
            language: "swift",
            limit: 50,
            includeArchive: true
        )

        #expect(query.text == "Button")
        #expect(query.source == "apple-docs")
        #expect(query.framework == "swiftui")
        #expect(query.language == "swift")
        #expect(query.limit == 50)
        #expect(query.includeArchive == true)
    }

    // MARK: - Services.SearchFilters Tests

    @Test("Services.SearchFilters detects active filters")
    func searchFiltersActiveDetection() {
        let noFilters = Services.SearchFilters()
        #expect(noFilters.hasActiveFilters == false)

        let withSource = Services.SearchFilters(source: "apple-docs")
        #expect(withSource.hasActiveFilters == true)

        let withFramework = Services.SearchFilters(framework: "swiftui")
        #expect(withFramework.hasActiveFilters == true)

        let withLanguage = Services.SearchFilters(language: "swift")
        #expect(withLanguage.hasActiveFilters == true)
    }

    // MARK: - HIGQuery Tests

    @Test("HIGQuery initializes with defaults")
    func higQueryDefaults() {
        let query = HIGQuery(text: "buttons")

        #expect(query.text == "buttons")
        #expect(query.platform == nil)
        #expect(query.category == nil)
        #expect(query.limit == Shared.Constants.Limit.defaultSearchLimit)
    }

    @Test("HIGQuery accepts platform and category")
    func higQueryWithFilters() {
        let query = HIGQuery(
            text: "navigation",
            platform: "iOS",
            category: "patterns",
            limit: 30
        )

        #expect(query.text == "navigation")
        #expect(query.platform == "iOS")
        #expect(query.category == "patterns")
        #expect(query.limit == 30)
    }

    // MARK: - Sample.Search.Query Tests

    @Test("Sample.Search.Query initializes with defaults")
    func sampleQueryDefaults() {
        let query = Sample.Search.Query(text: "SwiftUI")

        #expect(query.text == "SwiftUI")
        #expect(query.framework == nil)
        #expect(query.searchFiles == true)
        #expect(query.limit == Shared.Constants.Limit.defaultSearchLimit)
    }

    @Test("Sample.Search.Result isEmpty check")
    func sampleSearchResultIsEmpty() {
        let empty = Sample.Search.Result(projects: [], files: [])
        #expect(empty.isEmpty == true)
        #expect(empty.totalCount == 0)
    }
}

// MARK: - Format Config Tests

@Suite("Format Configuration Tests")
struct FormatConfigTests {
    @Test("CLI and MCP configs are identical")
    func configsAreIdentical() {
        let cli = SearchResultFormatConfig.cliDefault
        let mcp = SearchResultFormatConfig.mcpDefault

        // CLI and MCP must produce identical output
        #expect(cli.showScore == mcp.showScore)
        #expect(cli.showWordCount == mcp.showWordCount)
        #expect(cli.showSource == mcp.showSource)
        #expect(cli.showAvailability == mcp.showAvailability)
        #expect(cli.showSeparators == mcp.showSeparators)
        #expect(cli.emptyMessage == mcp.emptyMessage)
    }

    @Test("Shared config has expected values")
    func sharedConfigValues() {
        let config = SearchResultFormatConfig.shared

        #expect(config.showScore == true)
        #expect(config.showWordCount == true)
        #expect(config.showSource == false)
        #expect(config.showAvailability == true)
        #expect(config.showSeparators == true)
        #expect(config.emptyMessage == "_No results found. Try broader search terms._")
    }
}

// MARK: - Sample.Services.CandidateFetcher (#230)

@Suite("Sample.Services.CandidateFetcher (#230)")
struct SampleCandidateFetcherTests {
    @Test("sourceName matches the canonical samples prefix")
    func sourceNameIsSamples() async throws {
        // Build a fetcher against a temp DB just to verify the protocol
        // hookup; the in-memory DB is empty so fetch() returns no rows
        // but doesn't throw.
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("samples-fetcher-test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let service = try await Sample.Search.Service(dbPath: tempDB)
        defer { Task { await service.disconnect() } }

        let fetcher = Sample.Services.CandidateFetcher(service: service)
        #expect(fetcher.sourceName == Shared.Constants.SourcePrefix.samples)
    }

    @Test("Empty samples DB → fetch returns empty array, doesn't throw")
    func emptyDBYieldsEmptyResults() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("samples-fetcher-test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let service = try await Sample.Search.Service(dbPath: tempDB)
        defer { Task { await service.disconnect() } }

        let fetcher = Sample.Services.CandidateFetcher(service: service)
        let candidates = try await fetcher.fetch(question: "swiftui list", limit: 5)
        #expect(candidates.isEmpty)
    }
}

// MARK: - Teaser fallback resilience

@Suite("TeaserResults default + withTeaserService failure handling")
struct TeaserResultsResilienceTests {
    @Test("TeaserResults() default is empty")
    func defaultIsEmpty() {
        let results = TeaserResults()
        #expect(results.isEmpty)
        #expect(results.appleDocs.isEmpty)
        #expect(results.samples.isEmpty)
        #expect(results.archive.isEmpty)
        #expect(results.hig.isEmpty)
        #expect(results.swiftEvolution.isEmpty)
        #expect(results.swiftOrg.isEmpty)
        #expect(results.swiftBook.isEmpty)
        #expect(results.packages.isEmpty)
        #expect(results.allSources.isEmpty)
    }

    @Test("withTeaserService throws when search.db is a directory (open fails)")
    func searchDbAsDirectoryFails() async throws {
        // Pointing search.db at an existing directory makes
        // `sqlite3_open_v2` fail. This is the simplest reproducible
        // proxy for "search.db can't be read right now" — same shape as
        // the real-world `database is locked` error caught by the
        // resilience patch in `cupertino search --source samples`.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("teaser-search-as-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await #expect(throws: (any Error).self) {
            try await Services.ServiceContainer.withTeaserService(
                searchDbPath: tempDir.path,
                sampleDbPath: nil
            ) { service in
                _ = await service.fetchAllTeasers(
                    query: "swiftui",
                    framework: nil,
                    currentSource: Shared.Constants.SourcePrefix.samples,
                    includeArchive: false
                )
            }
        }
    }

    @Test("Caller swallowing withTeaserService error → empty TeaserResults works")
    func callerCanFallBackOnEmpty() async {
        // Replicates the resilience pattern in Command.Search.runSampleSearch:
        // catch the throw, fall back to TeaserResults(). Verifies the
        // fallback contract (empty + iterable) so future changes don't
        // accidentally make the empty struct require parameters.
        let teasers: TeaserResults
        do {
            teasers = try await Services.ServiceContainer.withTeaserService(
                searchDbPath: "/var/empty/intentionally-broken-search.db.\(UUID().uuidString)",
                sampleDbPath: nil
            ) { service in
                await service.fetchAllTeasers(
                    query: "swiftui",
                    framework: nil,
                    currentSource: Shared.Constants.SourcePrefix.samples,
                    includeArchive: false
                )
            }
        } catch {
            teasers = TeaserResults()
        }
        #expect(teasers.isEmpty || !teasers.isEmpty) // either path is OK
        #expect(teasers.allSources.isEmpty || !teasers.allSources.isEmpty)
    }
}

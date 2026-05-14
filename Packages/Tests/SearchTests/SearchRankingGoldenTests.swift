import Foundation
@testable import Search
import ASTIndexer
import Testing

@Suite("SearchRanking Golden Tests (VIG-291)")
struct SearchRankingGoldenTests {

    private func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("search-ranking-golden-\(UUID().uuidString).db")
    }

    private func indexPage(
        on idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        content: String,
        minMacOS: String? = nil
    ) async throws {
        try await idx.indexDocument(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            title: title,
            content: content,
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            minMacOS: minMacOS
        )
    }

    // MARK: - Query 1

    @Test("Query 1: 'Task' → canonical Swift Task wins")
    func query1Task() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_task",
            framework: "swift",
            title: "Task",
            content: "A unit of asynchronous work."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://kernel/documentation_kernel_task_info",
            framework: "kernel",
            title: "task_info",
            content: "Returns information about a Mach task."
        )

        let hits = try await idx.search(query: "Task", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits[0].uri.hasSuffix("documentation_swift_task"))
    }

    // MARK: - Query 2

    @Test("Query 2: 'View' → SwiftUI View beats DeviceManagement View (framework authority)")
    func query2View() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_view",
            framework: "swiftui",
            title: "View",
            content: "A type that represents part of your app's user interface."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://devicemanagement/documentation_devicemanagement_view",
            framework: "devicemanagement",
            title: "View",
            content: "An MDM payload that configures view-related restrictions."
        )

        let hits = try await idx.search(query: "View", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits[0].uri == "apple-docs://swiftui/documentation_swiftui_view")
    }

    // MARK: - Query 3

    @Test("Query 3: 'URL' → Foundation URL surfaces despite BM25 burial")
    func query3URL() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        // Seed Foundation URL with long content to penalize BM25 rank
        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_url",
            framework: "foundation",
            title: "URL",
            content: "A value that identifies the location of a resource. " + String(repeating: "Long content to penalize BM25. ", count: 50)
        )

        // Seed many decoys that win BM25 due to short content
        for i in 1...10 {
            try await indexPage(
                on: idx,
                uri: "apple-docs://decoy/documentation_decoy_\(i)",
                framework: "decoy",
                title: "URL",
                content: "Short content."
            )
        }

        let hits = try await idx.search(query: "URL", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits[0].uri == "apple-docs://foundation/documentation_foundation_url")
    }

    // MARK: - Query 4

    @Test("Query 4: 'Observable' → symbol boost flips Sort 2 order")
    func query4Observable() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        // Competitor: exact title match 'Observable' -> 20x boost (0.05 multiplier) in Sort 1.
        // We add EXTREME filler content to penalize its base BM25 heavily.
        let competitorUri = "apple-docs://competitor/documentation_competitor_observable"
        try await indexPage(
            on: idx,
            uri: competitorUri,
            framework: "competitor",
            title: "Observable",
            content: "A competitor. " + String(repeating: "Irrelevant words to dilute the rank. ", count: 1000)
        )

        // Symbol doc: non-matching title, but contains 'Observable' symbol.
        // We use a title that matches the first word to get a partial match boost.
        let symbolDocUri = "apple-docs://swift/observable_symbol_doc"
        try await indexPage(
            on: idx,
            uri: symbolDocUri,
            framework: "swift",
            title: "Observable protocol",
            content: "A protocol for observable objects."
        )
        try await idx.indexDocSymbols(
            docUri: symbolDocUri,
            symbols: [
                ASTIndexer.Symbol(name: "Observable", kind: .protocol, line: 1, column: 1)
            ]
        )
        try await idx.recomputeSymbolsBlob(docUri: symbolDocUri)

        let hits = try await idx.search(query: "Observable", source: "apple-docs", limit: 5)
        
        // Print ranks for verification as requested by Linda
        for (i, hit) in hits.enumerated() {
            print("Query 4 result [\(i)]: \(hit.uri), rank: \(hit.rank)")
        }

        try #require(hits.count >= 2)
        #expect(hits[0].uri == symbolDocUri)
    }

    // MARK: - Query 5

    @Test("Query 5: 'SwiftUI' → framework root page wins")
    func query5SwiftUI() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui",
            framework: "swiftui",
            title: "SwiftUI",
            content: "The SwiftUI framework."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_view",
            framework: "swiftui",
            title: "View",
            content: "A SwiftUI view."
        )

        let hits = try await idx.search(query: "SwiftUI", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits[0].uri == "apple-docs://swiftui/documentation_swiftui")
    }

    // MARK: - Query 6

    @Test("Query 6: 'Text' → parent beats nested type")
    func query6Text() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_text",
            framework: "swiftui",
            title: "Text",
            content: "A view that displays one or more lines of read-only text."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_text_scale",
            framework: "swiftui",
            title: "Text.Scale",
            content: "A scale for text."
        )

        let hits = try await idx.search(query: "Text", source: "apple-docs", limit: 5)
        try #require(hits.count >= 2)
        #expect(hits[0].uri == "apple-docs://swiftui/documentation_swiftui_text")
    }

    // MARK: - Query 7

    @Test("Query 7: 'Result' → Swift Result beats Vision/InstallerJS")
    func query7Result() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_result",
            framework: "swift",
            title: "Result",
            content: "A success or failure."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_result",
            framework: "vision",
            title: "Result",
            content: "Vision result."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://installer_js/documentation_installer_js_result",
            framework: "installer_js",
            title: "Result",
            content: "InstallerJS result."
        )

        let hits = try await idx.search(query: "Result", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits[0].uri == "apple-docs://swift/documentation_swift_result")
    }

    // MARK: - Query 8

    @Test("Query 8: 'Task' with minMacOS 13.0 → bypass behavior")
    func query8TaskFilter() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)

        // Canonical Task (minMacOS 12.0)
        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_task",
            framework: "swift",
            title: "Task",
            content: "Swift Task.",
            minMacOS: "12.0"
        )
        // SomeTaskThing (minMacOS 15.0) -> should be excluded by filter
        try await indexPage(
            on: idx,
            uri: "apple-docs://other/documentation_some_task_thing",
            framework: "other",
            title: "Task",
            content: "Some Task thing.",
            minMacOS: "15.0"
        )

        let hits = try await idx.search(query: "Task", source: "apple-docs", limit: 5, minMacOS: "13.0")
        
        // Assert results.count == 1 (SomeTaskThing excluded)
        #expect(hits.count == 1)
        // Assert canonical page at position 0 (rank -2000.0)
        try #require(!hits.isEmpty)
        #expect(hits[0].uri == "apple-docs://swift/documentation_swift_task")
        #expect(hits[0].rank == -2000.0)
    }
}

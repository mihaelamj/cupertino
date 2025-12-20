import Foundation
import MCP
@testable import SampleIndex
@testable import Search
@testable import SearchToolProvider
@testable import Services
@testable import Shared
import Testing
import TestSupport

// MARK: - Test Helpers

/// Creates a temporary search index for testing
/// - Returns: A tuple containing the search index and cleanup function
func createTestSearchIndex() async throws -> (index: Search.Index, cleanup: () throws -> Void) {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    let index = try await Search.Index(dbPath: tempDB)

    let cleanup = {
        try FileManager.default.removeItem(at: tempDB)
    }

    return (index, cleanup)
}

/// Creates a test search index with documents from multiple sources
func createMultiSourceSearchIndex() async throws -> (index: Search.Index, cleanup: () throws -> Void) {
    let (index, cleanup) = try await createTestSearchIndex()

    // Apple docs
    try await index.indexDocument(
        uri: "apple-docs://swiftui/animation",
        source: Shared.Constants.SourcePrefix.appleDocs,
        framework: "swiftui",
        title: "Animation in SwiftUI",
        content: "SwiftUI provides powerful animation APIs for creating smooth animations.",
        filePath: "/test/animation.md",
        contentHash: "hash1",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    // Apple archive
    try await index.indexDocument(
        uri: "apple-archive://coreanim/animation",
        source: Shared.Constants.SourcePrefix.appleArchive,
        framework: "coreanimation",
        title: "Core Animation Programming Guide",
        content: "Core Animation provides high-performance animation capabilities.",
        filePath: "/test/coreanimation.md",
        contentHash: "hash2",
        lastCrawled: Date(),
        sourceType: "archive"
    )

    // HIG
    try await index.indexDocument(
        uri: "hig://motion/animation",
        source: Shared.Constants.SourcePrefix.hig,
        framework: nil,
        title: "Motion and Animation Guidelines",
        content: "Motion adds vitality to an app's user experience.",
        filePath: "/test/hig-motion.md",
        contentHash: "hash3",
        lastCrawled: Date(),
        sourceType: "hig"
    )

    // Swift Evolution
    try await index.indexDocument(
        uri: "swift-evolution://SE-0392",
        source: Shared.Constants.SourcePrefix.swiftEvolution,
        framework: nil,
        title: "SE-0392 Animation Protocol",
        content: "This proposal introduces a standardized Animation protocol.",
        filePath: "/test/se-0392.md",
        contentHash: "hash4",
        lastCrawled: Date(),
        sourceType: "swift-evolution"
    )

    // Swift.org
    try await index.indexDocument(
        uri: "swift-org://docs/animation",
        source: Shared.Constants.SourcePrefix.swiftOrg,
        framework: nil,
        title: "Swift Animation Documentation",
        content: "Documentation about using animation in Swift applications.",
        filePath: "/test/swift-org-animation.md",
        contentHash: "hash5",
        lastCrawled: Date(),
        sourceType: "swift-org"
    )

    // Swift Book
    try await index.indexDocument(
        uri: "swift-book://chapter/animation",
        source: Shared.Constants.SourcePrefix.swiftBook,
        framework: nil,
        title: "Swift Book: Animation Chapter",
        content: "Learn how to implement animation patterns in Swift.",
        filePath: "/test/swift-book-animation.md",
        contentHash: "hash6",
        lastCrawled: Date(),
        sourceType: "swift-book"
    )

    // Packages
    try await index.indexDocument(
        uri: "packages://swift-animations",
        source: Shared.Constants.SourcePrefix.packages,
        framework: nil,
        title: "Swift Animations Package",
        content: "A powerful animation library for Swift developers.",
        filePath: "/test/packages-animation.md",
        contentHash: "hash7",
        lastCrawled: Date(),
        sourceType: "packages"
    )

    return (index, cleanup)
}

/// Creates a temporary sample database for testing
func createTestSampleDatabase() async throws -> (database: SampleIndex.Database, cleanup: () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sample-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("samples.db")
    let database = try await SampleIndex.Database(dbPath: dbPath)

    // Add sample project using correct API
    let project = SampleIndex.Project(
        id: "animating-views-sample",
        title: "Animating Views in SwiftUI",
        description: "Learn how to animate views using SwiftUI.",
        frameworks: ["SwiftUI", "Combine"],
        readme: "# Animation Sample\n\nShows how to animate views.",
        webURL: "https://developer.apple.com/documentation/swiftui/animating-views",
        zipFilename: "animating-views-sample.zip",
        fileCount: 10,
        totalSize: 50000
    )
    try await database.indexProject(project)

    // Add sample file using correct API
    let file = SampleIndex.File(
        projectId: "animating-views-sample",
        path: "ContentView.swift",
        content: "import SwiftUI\n\nstruct ContentView: View {\n    @State var isAnimating = false\n}"
    )
    try await database.indexFile(file)

    let cleanup: () -> Void = {
        try? FileManager.default.removeItem(at: tempDir)
    }

    return (database, cleanup)
}

// MARK: - CompositeToolProvider Initialization Tests

@Suite("CompositeToolProvider Initialization", .serialized)
struct CompositeToolProviderInitTests {
    @Test("Provider initializes with search index only")
    func initWithSearchIndexOnly() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let result = try await provider.listTools(cursor: nil)

        // Should have search, list_frameworks, read_document
        #expect(result.tools.count >= 3)
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolSearch })
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListFrameworks })
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolReadDocument })

        await index.disconnect()
    }

    @Test("Provider initializes with sample database only")
    func initWithSampleDatabaseOnly() async throws {
        let (database, cleanup) = try await createTestSampleDatabase()
        defer { cleanup() }

        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: database)
        let result = try await provider.listTools(cursor: nil)

        // Should have sample tools
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolSearch })
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListSamples })
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolReadSample })
        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolReadSampleFile })
    }

    @Test("Provider initializes with both search index and sample database")
    func initWithBoth() async throws {
        let (index, indexCleanup) = try await createTestSearchIndex()
        defer { try? indexCleanup() }
        let (database, dbCleanup) = try await createTestSampleDatabase()
        defer { dbCleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: database)
        let result = try await provider.listTools(cursor: nil)

        // Should have all tools
        #expect(result.tools.count >= 6)

        await index.disconnect()
    }
}

// MARK: - Search Tool Source Routing Tests

@Suite("Search Tool Source Routing", .serialized)
struct SearchToolSourceRoutingTests {
    @Test("Search routes to ALL sources by default")
    func searchDefaultSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            // Default search (unified) includes all sources - should contain apple-docs content
            #expect(textContent.text.contains("SwiftUI"))
            // Unified search header indicates all sources searched
            #expect(textContent.text.contains("Unified Search"))
        }

        await index.disconnect()
    }

    @Test("Search routes to samples source")
    func searchSamplesSource() async throws {
        let (index, indexCleanup) = try await createTestSearchIndex()
        defer { try? indexCleanup() }
        let (database, dbCleanup) = try await createTestSampleDatabase()
        defer { dbCleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: database)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.samples),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("Animating Views"))
        }

        await index.disconnect()
    }

    @Test("Search routes to HIG source")
    func searchHIGSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.hig),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("HIG"))
            #expect(textContent.text.contains("Motion"))
        }

        await index.disconnect()
    }

    @Test("Search routes to apple-archive source")
    func searchArchiveSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.appleArchive),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("Core Animation"))
        }

        await index.disconnect()
    }

    @Test("Search routes to swift-evolution source")
    func searchEvolutionSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.swiftEvolution),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("SE-0392"))
        }

        await index.disconnect()
    }

    @Test("Search routes to swift-org source")
    func searchSwiftOrgSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.swiftOrg),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("Swift Animation Documentation"))
        }

        await index.disconnect()
    }

    @Test("Search routes to swift-book source")
    func searchSwiftBookSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.swiftBook),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("Swift Book"))
        }

        await index.disconnect()
    }

    @Test("Search routes to packages source")
    func searchPackagesSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.packages),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("Swift Animations Package"))
        }

        await index.disconnect()
    }
}

// MARK: - Unified Search (source: all) Tests

@Suite("Unified Search All Sources", .serialized)
struct UnifiedSearchTests {
    @Test("Search all sources returns results from every source")
    func searchAllSources() async throws {
        let (index, indexCleanup) = try await createMultiSourceSearchIndex()
        defer { try? indexCleanup() }
        let (database, dbCleanup) = try await createTestSampleDatabase()
        defer { dbCleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: database)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.all),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)
        #expect(!result.content.isEmpty)

        if case let .text(textContent) = result.content.first {
            let text = textContent.text
            // Verify results from all 8 sources
            #expect(text.contains("Apple Documentation"))
            #expect(text.contains("Sample Code"))
            #expect(text.contains("Human Interface Guidelines"))
            #expect(text.contains("Apple Archive"))
            #expect(text.contains("Swift Evolution"))
            #expect(text.contains("Swift.org"))
            #expect(text.contains("Swift Book"))
            #expect(text.contains("Swift Packages"))
        }

        await index.disconnect()
    }

    @Test("Search all includes tip about narrowing scope")
    func searchAllIncludesNarrowingTip() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.all),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("To narrow results"))
            #expect(textContent.text.contains("source"))
        }

        await index.disconnect()
    }

    @Test("Search all does not include teasers")
    func searchAllNoTeasers() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.all),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // "Also in" is the teaser indicator - should NOT be present in "all" search
            #expect(!textContent.text.contains("Also in Sample Code"))
            #expect(!textContent.text.contains("Also in Apple Archive"))
        }

        await index.disconnect()
    }

    @Test("Search all only shows sections with results")
    func searchAllOnlyShowsSectionsWithResults() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        // Only index apple-docs
        try await index.indexDocument(
            uri: "apple-docs://swift/string",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swift",
            title: "String",
            content: "A Unicode string value.",
            filePath: "/test/string.md",
            contentHash: "hash",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("string"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.all),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // Should show Apple Documentation section
            #expect(textContent.text.contains("Apple Documentation"))
            // Should NOT show empty sections like HIG or Swift Evolution
            #expect(!textContent.text.contains("Human Interface Guidelines (0)"))
            #expect(!textContent.text.contains("Swift Evolution (0)"))
        }

        await index.disconnect()
    }
}

// MARK: - Teaser Functionality Tests

@Suite("Teaser Results", .serialized)
struct TeaserResultsTests {
    @Test("Single source search includes teasers from other sources")
    func singleSourceIncludesTeasers() async throws {
        let (index, indexCleanup) = try await createMultiSourceSearchIndex()
        defer { try? indexCleanup() }
        let (database, dbCleanup) = try await createTestSampleDatabase()
        defer { dbCleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: database)

        // Search apple-docs only
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.appleDocs),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // Should include teaser sections from other sources
            #expect(textContent.text.contains("Also in"))
        }

        await index.disconnect()
    }

    @Test("Teasers are limited to configured limit")
    func teasersRespectLimit() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        // Add multiple archive docs
        for docNumber in 1...5 {
            try await index.indexDocument(
                uri: "apple-archive://doc\(docNumber)",
                source: Shared.Constants.SourcePrefix.appleArchive,
                framework: nil,
                title: "Archive Animation Doc \(docNumber)",
                content: "Animation content for document \(docNumber)",
                filePath: "/test/archive\(docNumber).md",
                contentHash: "hash\(docNumber)",
                lastCrawled: Date(),
                sourceType: "archive"
            )
        }

        // Add apple-docs to search
        try await index.indexDocument(
            uri: "apple-docs://animation",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "SwiftUI Animation",
            content: "Animation in SwiftUI",
            filePath: "/test/swiftui.md",
            contentHash: "hashMain",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            let text = textContent.text
            // Count archive results in teaser - should be limited to teaserLimit (2)
            let archiveSection = text.components(separatedBy: "Also in Apple Archive:")
            if archiveSection.count > 1 {
                let teaserContent = archiveSection[1].components(separatedBy: "---").first ?? ""
                let lineCount = teaserContent.components(separatedBy: "\n")
                    .filter { $0.starts(with: "- ") }
                    .count
                #expect(lineCount <= Shared.Constants.Limit.teaserLimit)
            }
        }

        await index.disconnect()
    }

    @Test("Teasers use same search query")
    func teasersUseSameQuery() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        // Add docs for "networking" query
        try await index.indexDocument(
            uri: "apple-docs://networking",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "foundation",
            title: "Networking Guide",
            content: "Learn how to implement networking in your app",
            filePath: "/test/networking.md",
            contentHash: "hash1",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        // Add archive doc that matches "networking"
        try await index.indexDocument(
            uri: "apple-archive://network-guide",
            source: Shared.Constants.SourcePrefix.appleArchive,
            framework: nil,
            title: "Network Programming Guide",
            content: "Learn about networking protocols",
            filePath: "/test/archive-network.md",
            contentHash: "hash2",
            lastCrawled: Date(),
            sourceType: "archive"
        )

        // Add archive doc about "graphics" - completely different topic
        try await index.indexDocument(
            uri: "apple-archive://graphics-guide",
            source: Shared.Constants.SourcePrefix.appleArchive,
            framework: nil,
            title: "Graphics Programming Guide",
            content: "Learn about Core Graphics and drawing",
            filePath: "/test/archive-graphics.md",
            contentHash: "hash3",
            lastCrawled: Date(),
            sourceType: "archive"
        )

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        // Search for "networking" specifically
        let args: [String: AnyCodable] = [
            "query": AnyCodable("networking"),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // Teaser should show "Network Programming Guide" (matches "networking" query)
            // but NOT "Graphics Programming Guide" (doesn't match query)
            if textContent.text.contains("Also in Apple Archive") {
                #expect(textContent.text.contains("Network"))
                #expect(!textContent.text.contains("Graphics Programming Guide"))
            }
        }

        await index.disconnect()
    }

    @Test("Teaser excludes current source")
    func teaserExcludesCurrentSource() async throws {
        let (index, cleanup) = try await createMultiSourceSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        // Search HIG source
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.hig),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // Should NOT have "Also in Human Interface Guidelines" since that's the current source
            #expect(!textContent.text.contains("Also in Human Interface Guidelines"))
        }

        await index.disconnect()
    }

    @Test("Empty teasers are not shown")
    func emptyTeasersNotShown() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        // Only add apple-docs
        try await index.indexDocument(
            uri: "apple-docs://unique-topic",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "foundation",
            title: "Unique Topic",
            content: "This unique topic exists only in apple-docs",
            filePath: "/test/unique.md",
            contentHash: "hash",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("unique"),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // Should NOT show any "Also in" sections since no other sources have results
            #expect(!textContent.text.contains("Also in"))
        }

        await index.disconnect()
    }
}

// MARK: - Search Filtering Tests

@Suite("Search Filtering", .serialized)
struct SearchFilteringTests {
    @Test("Framework filter works correctly")
    func frameworkFilter() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        try await index.indexDocument(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "SwiftUI View",
            content: "A view protocol in SwiftUI",
            filePath: "/test/view.md",
            contentHash: "hash1",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        try await index.indexDocument(
            uri: "apple-docs://uikit/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "uikit",
            title: "UIKit View",
            content: "A view class in UIKit",
            filePath: "/test/uiview.md",
            contentHash: "hash2",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("view"),
            "framework": AnyCodable("swiftui"),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            #expect(textContent.text.contains("SwiftUI View"))
            #expect(!textContent.text.contains("UIKit View"))
        }

        await index.disconnect()
    }

    @Test("Limit parameter works correctly")
    func limitParameter() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        // Add multiple docs
        for docNumber in 1...10 {
            try await index.indexDocument(
                uri: "apple-docs://swift\(docNumber)",
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: "swift",
                title: "Swift Doc \(docNumber)",
                content: "Swift content number \(docNumber)",
                filePath: "/test/swift\(docNumber).md",
                contentHash: "hash\(docNumber)",
                lastCrawled: Date(),
                sourceType: "apple"
            )
        }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("swift"),
            "source": AnyCodable("apple-docs"), // Specify source to get numbered results format
            "limit": AnyCodable(3),
        ]

        let result = try await provider.callTool(name: "search", arguments: args)

        if case let .text(textContent) = result.content.first {
            // Count numbered results (##1., ##2., etc.)
            let pattern = #"## \d+\."#
            let regex = try Regex(pattern)
            let matches = textContent.text.matches(of: regex)
            #expect(matches.count == 3)
        }

        await index.disconnect()
    }

    @Test("Include archive parameter works")
    func includeArchiveParameter() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        try await index.indexDocument(
            uri: "apple-docs://swift/string",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swift",
            title: "String",
            content: "Swift String type",
            filePath: "/test/string.md",
            contentHash: "hash1",
            lastCrawled: Date(),
            sourceType: "apple"
        )

        try await index.indexDocument(
            uri: "apple-archive://string-guide",
            source: Shared.Constants.SourcePrefix.appleArchive,
            framework: nil,
            title: "String Programming Guide",
            content: "Legacy string programming guide",
            filePath: "/test/archive-string.md",
            contentHash: "hash2",
            lastCrawled: Date(),
            sourceType: "archive"
        )

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        // Without include_archive
        let argsWithout: [String: AnyCodable] = [
            "query": AnyCodable("string"),
        ]
        let resultWithout = try await provider.callTool(name: "search", arguments: argsWithout)

        // With include_archive
        let argsWith: [String: AnyCodable] = [
            "query": AnyCodable("string"),
            "include_archive": AnyCodable(true),
        ]
        let resultWith = try await provider.callTool(name: "search", arguments: argsWith)

        if case let .text(textWithout) = resultWithout.content.first,
           case let .text(textWith) = resultWith.content.first {
            // Both should have the main result, but archive should appear differently
            #expect(textWithout.text.contains("String"))
            #expect(textWith.text.contains("String"))
        }

        await index.disconnect()
    }
}

// MARK: - Error Handling Tests

@Suite("Search Error Handling", .serialized)
struct SearchErrorHandlingTests {
    @Test("Unknown tool throws error")
    func unknownToolThrows() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        await #expect(throws: ToolError.self) {
            _ = try await provider.callTool(name: "nonexistent_tool", arguments: nil)
        }

        await index.disconnect()
    }

    @Test("Missing required parameter throws error")
    func missingRequiredParamThrows() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        await #expect(throws: ToolError.self) {
            _ = try await provider.callTool(name: "search", arguments: [:])
        }

        await index.disconnect()
    }

    @Test("Search samples without database throws error")
    func searchSamplesWithoutDBThrows() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let args: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable(Shared.Constants.SourcePrefix.samples),
        ]

        await #expect(throws: ToolError.self) {
            _ = try await provider.callTool(name: "search", arguments: args)
        }

        await index.disconnect()
    }
}

// MARK: - Formatter Tests

@Suite("Unified Search Formatter", .serialized)
struct UnifiedSearchFormatterTests {
    @Test("UnifiedSearchInput calculates total count correctly")
    func totalCountCalculation() {
        let input = UnifiedSearchInput(
            docResults: [makeResult(title: "Doc1"), makeResult(title: "Doc2")],
            archiveResults: [makeResult(title: "Archive1")],
            sampleResults: [makeSampleProject()],
            higResults: [makeResult(title: "HIG1")],
            swiftEvolutionResults: [],
            swiftOrgResults: [makeResult(title: "SwiftOrg1")],
            swiftBookResults: [],
            packagesResults: [makeResult(title: "Package1")]
        )

        #expect(input.totalCount == 7)
    }

    @Test("UnifiedSearchInput empty state")
    func emptyState() {
        let input = UnifiedSearchInput()
        #expect(input.totalCount == 0)
    }

    @Test("Formatter outputs correct markdown structure")
    func formatterMarkdownStructure() {
        let input = UnifiedSearchInput(
            docResults: [makeResult(title: "SwiftUI View")],
            archiveResults: [],
            sampleResults: [],
            higResults: [],
            swiftEvolutionResults: [],
            swiftOrgResults: [],
            swiftBookResults: [],
            packagesResults: []
        )

        let formatter = UnifiedSearchMarkdownFormatter(query: "view")
        let output = formatter.format(input)

        #expect(output.contains("# Unified Search"))
        #expect(output.contains("\"view\""))
        #expect(output.contains("Apple Documentation"))
        #expect(output.contains("SwiftUI View"))
    }

    @Test("Formatter hides empty sections")
    func formatterHidesEmptySections() {
        let input = UnifiedSearchInput(
            docResults: [makeResult(title: "Doc1")],
            archiveResults: [],
            sampleResults: [],
            higResults: [],
            swiftEvolutionResults: [],
            swiftOrgResults: [],
            swiftBookResults: [],
            packagesResults: []
        )

        let formatter = UnifiedSearchMarkdownFormatter(query: "test")
        let output = formatter.format(input)

        #expect(!output.contains("Apple Archive (0)"))
        #expect(!output.contains("Human Interface Guidelines (0)"))
    }

    // Helper functions
    private func makeResult(title: String) -> Search.Result {
        Search.Result(
            uri: "test://\(title.lowercased().replacingOccurrences(of: " ", with: "-"))",
            source: "test",
            framework: "test",
            title: title,
            summary: "Test summary for \(title)",
            filePath: "/test.md",
            wordCount: 100,
            rank: -1.0
        )
    }

    private func makeSampleProject() -> SampleIndex.Project {
        SampleIndex.Project(
            id: "test-sample",
            title: "Test Sample",
            description: "A test sample project",
            frameworks: ["SwiftUI"],
            readme: nil,
            webURL: "https://example.com",
            zipFilename: "test-sample.zip",
            fileCount: 5,
            totalSize: 10000
        )
    }
}

// MARK: - Integration Tests

@Suite("Search Integration", .tags(.integration), .serialized)
struct SearchIntegrationTests {
    @Test("Complete search workflow with all sources", .tags(.slow))
    func completeSearchWorkflow() async throws {
        let (index, indexCleanup) = try await createMultiSourceSearchIndex()
        defer { try? indexCleanup() }
        let (database, dbCleanup) = try await createTestSampleDatabase()
        defer { dbCleanup() }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: database)

        // Test 1: Default search (apple-docs)
        let defaultArgs: [String: AnyCodable] = ["query": AnyCodable("animation")]
        let defaultResult = try await provider.callTool(name: "search", arguments: defaultArgs)
        #expect(!defaultResult.content.isEmpty)

        // Test 2: Unified search (all)
        let allArgs: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable("all"),
        ]
        let allResult = try await provider.callTool(name: "search", arguments: allArgs)
        if case let .text(content) = allResult.content.first {
            #expect(content.text.contains("Total:"))
        }

        // Test 3: Sample search
        let sampleArgs: [String: AnyCodable] = [
            "query": AnyCodable("animation"),
            "source": AnyCodable("samples"),
        ]
        let sampleResult = try await provider.callTool(name: "search", arguments: sampleArgs)
        #expect(!sampleResult.content.isEmpty)

        // Test 4: List frameworks
        let frameworksResult = try await provider.callTool(name: "list_frameworks", arguments: nil)
        #expect(!frameworksResult.content.isEmpty)

        await index.disconnect()
    }
}

import Foundation
@testable import Shared
import Testing

// MARK: - DocumentationPage Tests

@Test("DocumentationPage initializes with all required fields")
func documentationPageInitialization() {
    let page = DocumentationPage(
        url: URL(string: "https://developer.apple.com/documentation/swift")!,
        framework: "Swift",
        title: "Swift Documentation",
        filePath: URL(fileURLWithPath: "/docs/swift.md"),
        contentHash: "abc123",
        depth: 2
    )

    #expect(page.url.absoluteString.contains("swift"))
    #expect(page.framework == "Swift")
    #expect(page.title == "Swift Documentation")
    #expect(page.contentHash == "abc123")
    #expect(page.depth == 2)
}

@Test("DocumentationPage is Codable")
func documentationPageCodable() throws {
    let originalPage = DocumentationPage(
        url: URL(string: "https://developer.apple.com/documentation/swift/array")!,
        framework: "Swift",
        title: "Array",
        filePath: URL(fileURLWithPath: "/docs/array.md"),
        contentHash: "hash123",
        depth: 3
    )

    // Encode
    let encoder = JSONEncoder()
    let data = try encoder.encode(originalPage)

    // Decode
    let decoder = JSONDecoder()
    let decodedPage = try decoder.decode(DocumentationPage.self, from: data)

    #expect(decodedPage.url == originalPage.url)
    #expect(decodedPage.framework == originalPage.framework)
    #expect(decodedPage.title == originalPage.title)
    #expect(decodedPage.contentHash == originalPage.contentHash)
    #expect(decodedPage.depth == originalPage.depth)
}

@Test("DocumentationPage generates unique IDs")
func documentationPageUniqueIDs() {
    let page1 = DocumentationPage(
        url: URL(string: "https://example.com/doc1")!,
        framework: "Test",
        title: "Doc 1",
        filePath: URL(fileURLWithPath: "/test.md"),
        contentHash: "hash1",
        depth: 0
    )

    let page2 = DocumentationPage(
        url: URL(string: "https://example.com/doc2")!,
        framework: "Test",
        title: "Doc 2",
        filePath: URL(fileURLWithPath: "/test.md"),
        contentHash: "hash2",
        depth: 0
    )

    #expect(page1.id != page2.id, "Each page should have unique ID")
}

// MARK: - CrawlMetadata Tests

@Test("CrawlMetadata initializes with empty state")
func crawlMetadataInitialization() {
    let metadata = CrawlMetadata()

    #expect(metadata.pages.isEmpty)
    #expect(metadata.lastCrawl == nil)
    #expect(metadata.stats.totalPages == 0)
    #expect(metadata.crawlState == nil)
}

@Test("CrawlMetadata is Codable")
func crawlMetadataCodable() throws {
    var metadata = CrawlMetadata()
    metadata.pages["https://example.com"] = PageMetadata(
        url: "https://example.com",
        framework: "test",
        filePath: "/test.md",
        contentHash: "hash",
        depth: 0
    )
    metadata.lastCrawl = Date()
    metadata.stats.totalPages = 10

    let encoder = JSONEncoder()
    let data = try encoder.encode(metadata)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(CrawlMetadata.self, from: data)

    #expect(decoded.pages.count == 1)
    #expect(decoded.stats.totalPages == 10)
}

@Test("CrawlMetadata saves and loads from file")
func crawlMetadataSaveLoad() throws {
    let tempFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tempFile) }

    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc1"] = PageMetadata(
        url: "https://example.com/doc1",
        framework: "swift",
        filePath: "/docs/doc1.md",
        contentHash: "hash1",
        depth: 1
    )
    metadata.pages["https://example.com/doc2"] = PageMetadata(
        url: "https://example.com/doc2",
        framework: "uikit",
        filePath: "/docs/doc2.md",
        contentHash: "hash2",
        depth: 2
    )
    metadata.stats.totalPages = 2
    metadata.stats.newPages = 2

    // Save
    try metadata.save(to: tempFile)

    // Verify file exists
    #expect(FileManager.default.fileExists(atPath: tempFile.path))

    // Load
    let loaded = try CrawlMetadata.load(from: tempFile)

    #expect(loaded.pages.count == 2)
    #expect(loaded.stats.totalPages == 2)
    #expect(loaded.pages["https://example.com/doc1"]?.framework == "swift")
    #expect(loaded.pages["https://example.com/doc2"]?.framework == "uikit")
}

// MARK: - PageMetadata Tests

@Test("PageMetadata initializes correctly")
func pageMetadataInitialization() {
    let metadata = PageMetadata(
        url: "https://developer.apple.com/documentation/swift/array",
        framework: "Swift",
        filePath: "/docs/swift/array.md",
        contentHash: "abc123def",
        depth: 3
    )

    #expect(metadata.url == "https://developer.apple.com/documentation/swift/array")
    #expect(metadata.framework == "Swift")
    #expect(metadata.filePath == "/docs/swift/array.md")
    #expect(metadata.contentHash == "abc123def")
    #expect(metadata.depth == 3)
}

@Test("PageMetadata is Codable")
func pageMetadataCodable() throws {
    let original = PageMetadata(
        url: "https://example.com",
        framework: "test",
        filePath: "/test.md",
        contentHash: "hash",
        depth: 0
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(PageMetadata.self, from: data)

    #expect(decoded.url == original.url)
    #expect(decoded.framework == original.framework)
    #expect(decoded.filePath == original.filePath)
    #expect(decoded.contentHash == original.contentHash)
    #expect(decoded.depth == original.depth)
}

// MARK: - CrawlStatistics Tests

@Test("CrawlStatistics initializes with zeros")
func crawlStatisticsInitialization() {
    let stats = CrawlStatistics()

    #expect(stats.totalPages == 0)
    #expect(stats.newPages == 0)
    #expect(stats.updatedPages == 0)
    #expect(stats.skippedPages == 0)
    #expect(stats.errors == 0)
}

@Test("CrawlStatistics is Codable")
func crawlStatisticsCodable() throws {
    let stats = CrawlStatistics(
        totalPages: 100,
        newPages: 50,
        updatedPages: 30,
        skippedPages: 20,
        errors: 5,
        startTime: Date(),
        endTime: Date()
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(stats)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(CrawlStatistics.self, from: data)

    #expect(decoded.totalPages == 100)
    #expect(decoded.newPages == 50)
    #expect(decoded.updatedPages == 30)
    #expect(decoded.skippedPages == 20)
    #expect(decoded.errors == 5)
}

@Test("CrawlStatistics calculates duration")
func crawlStatisticsDuration() {
    let startTime = Date()
    let endTime = startTime.addingTimeInterval(300) // 5 minutes

    let stats = CrawlStatistics(
        totalPages: 10,
        newPages: 10,
        updatedPages: 0,
        skippedPages: 0,
        errors: 0,
        startTime: startTime,
        endTime: endTime
    )

    // Duration should be ~300 seconds
    let duration = stats.duration ?? 0
    #expect(duration >= 299 && duration <= 301, "Duration should be approximately 300 seconds")
}

@Test("CrawlStatistics duration is nil when times not set")
func crawlStatisticsNoDuration() {
    let stats = CrawlStatistics(
        totalPages: 10,
        newPages: 10,
        updatedPages: 0,
        skippedPages: 0,
        errors: 0,
        startTime: nil,
        endTime: nil
    )

    #expect(stats.duration == nil)
}

// Note: CrawlSessionState, SwiftPackageEntry, SampleCodeEntry, and PriorityPackageCatalogData
// have more complex tests in Core module

// MARK: - StructuredDocumentationPage Declaration and Kind Tests

// Helper type alias for brevity
private typealias Page = StructuredDocumentationPage
private typealias Kind = StructuredDocumentationPage.Kind

@Test("StructuredDocumentationPage extracts @attributes from declaration")
func structuredPageExtractsAttributes() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Test",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "@MainActor @preconcurrency struct MyView"
        )
    )

    let attrs = page.extractedAttributes
    #expect(attrs.contains("@MainActor"))
    #expect(attrs.contains("@preconcurrency"))
    #expect(attrs.count == 2)
}

@Test("StructuredDocumentationPage extracts @attributes with arguments")
func structuredPageExtractsAttributesWithArgs() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Test",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "@backDeployed(before: iOS 18.0, macOS 15.0) static var monthly: Period { get }"
        )
    )

    let attrs = page.extractedAttributes
    #expect(attrs.count == 1)
    #expect(attrs[0] == "@backDeployed(before: iOS 18.0, macOS 15.0)")
}

@Test("StructuredDocumentationPage normalizes declaration by stripping attributes")
func structuredPageNormalizesDeclaration() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Test",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "@MainActor @preconcurrency struct MyView"
        )
    )

    let normalized = page.normalizedDeclaration
    #expect(normalized == "struct MyView")
}

@Test("StructuredDocumentationPage normalizes multi-line declaration")
func structuredPageNormalizesMultilineDeclaration() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Test",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "@MainActor @preconcurrency\nstruct MyView"
        )
    )

    let normalized = page.normalizedDeclaration
    #expect(normalized == "struct MyView")
}

@Test("StructuredDocumentationPage inferredKind detects struct with @attributes")
func structuredPageInferredKindStructWithAttributes() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "MyView",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "@MainActor @preconcurrency struct MyView"
        )
    )

    #expect(page.inferredKind == Kind.struct)
}

@Test("StructuredDocumentationPage inferredKind detects static var with @backDeployed")
func structuredPageInferredKindStaticVarWithBackDeployed() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "monthly",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "@backDeployed(before: iOS 18.0, macOS 15.0) static var monthly: Period { get }"
        )
    )

    #expect(page.inferredKind == Kind.property)
}

@Test("StructuredDocumentationPage inferredKind detects subscript")
func structuredPageInferredKindSubscript() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "subscript",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "subscript<T>(dynamicMember keyPath: KeyPath<Product, T?>) -> T? { get }"
        )
    )

    #expect(page.inferredKind == Kind.method)
}

@Test("StructuredDocumentationPage inferredKind detects actor")
func structuredPageInferredKindActor() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "DataStore",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "actor DataStore"
        )
    )

    #expect(page.inferredKind == Kind.class)
}

@Test("StructuredDocumentationPage inferredKind detects associatedtype")
func structuredPageInferredKindAssociatedtype() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Element",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "associatedtype Element"
        )
    )

    #expect(page.inferredKind == Kind.typeAlias)
}

@Test("StructuredDocumentationPage inferredKind preserves non-unknown kinds")
func structuredPageInferredKindPreservesExisting() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Test",
        kind: .method, // Already classified
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "struct SomethingElse" // Declaration suggests struct
        )
    )

    // Should preserve original .method, not infer .struct
    #expect(page.inferredKind == Kind.method)
}

// MARK: - Modifier Prefix Handling Tests

@Test("StructuredDocumentationPage inferredKind detects public struct")
func structuredPageInferredKindPublicStruct() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "MyStruct",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "public struct MyStruct"
        )
    )

    #expect(page.inferredKind == Kind.struct)
}

@Test("StructuredDocumentationPage inferredKind detects final class")
func structuredPageInferredKindFinalClass() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "FinalClass",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "final class FinalClass"
        )
    )

    #expect(page.inferredKind == Kind.class)
}

@Test("StructuredDocumentationPage inferredKind detects open class")
func structuredPageInferredKindOpenClass() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "OpenClass",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "open class OpenClass"
        )
    )

    #expect(page.inferredKind == Kind.class)
}

@Test("StructuredDocumentationPage inferredKind detects nonisolated func")
func structuredPageInferredKindNonisolatedFunc() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "doWork",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "nonisolated func doWork()"
        )
    )

    #expect(page.inferredKind == Kind.method)
}

@Test("StructuredDocumentationPage inferredKind detects public actor")
func structuredPageInferredKindPublicActor() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "MyActor",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "public actor MyActor"
        )
    )

    #expect(page.inferredKind == Kind.class)
}

@Test("StructuredDocumentationPage inferredKind detects public typealias")
func structuredPageInferredKindPublicTypealias() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Handler",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "public typealias Handler = () -> Void"
        )
    )

    #expect(page.inferredKind == Kind.typeAlias)
}

@Test("StructuredDocumentationPage inferredKind detects indirect enum")
func structuredPageInferredKindIndirectEnum() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "Tree",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "indirect enum Tree<T>"
        )
    )

    #expect(page.inferredKind == Kind.enum)
}

// MARK: - Failable/Generic Initializer Tests

@Test("StructuredDocumentationPage inferredKind detects failable init?")
func structuredPageInferredKindFailableInit() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "init(mimeType:conformingTo:)",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "init?(mimeType: String, conformingTo supertype: UTType = .data)"
        )
    )

    #expect(page.inferredKind == Kind.method)
}

@Test("StructuredDocumentationPage inferredKind detects implicitly unwrapped init!")
func structuredPageInferredKindIUOInit() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "init(contentURL:)",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "init!(contentURL url: URL!)"
        )
    )

    #expect(page.inferredKind == Kind.method)
}

@Test("StructuredDocumentationPage inferredKind detects generic init<T>")
func structuredPageInferredKindGenericInit() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "init(controlPoints:creationDate:)",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "init<T>(controlPoints: T, creationDate: Date) where T : Sequence"
        )
    )

    #expect(page.inferredKind == Kind.method)
}

@Test("StructuredDocumentationPage inferredKind detects convenience init?")
func structuredPageInferredKindConvenienceFailableInit() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "init(mimeType:)",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "convenience init?(mimeType: String)"
        )
    )

    #expect(page.inferredKind == Kind.method)
}

// MARK: - REST API Types

@Test("StructuredDocumentationPage inferredKind detects object as struct")
func structuredPageInferredKindObject() {
    let page = Page(
        url: URL(string: "https://example.com")!,
        title: "ErrorResponse",
        kind: .unknown,
        source: .appleJSON,
        declaration: Page.Declaration(
            code: "object ErrorResponse"
        )
    )

    #expect(page.inferredKind == Kind.struct)
}

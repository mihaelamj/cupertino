import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

/// Regression suite for the #274 walk + symbol-resolution helpers
/// (`walkInheritance`, `resolveSymbolURIs`). Pairs with
/// `Issue274InheritanceEdgeWritesTests` which covers the writer +
/// per-direction `parentsOf`/`childrenOf` shapes.
@Suite("#274 inheritance walk + symbol resolution", .serialized)
struct Issue274InheritanceWalkTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue274-walk-\(UUID().uuidString).db")
    }

    /// Seed a chain in the inheritance table for walk tests:
    /// UIButton → UIControl → UIView → UIResponder → NSObject.
    private static func seedUIButtonChain(_ idx: Search.Index) async throws {
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uibutton",
            inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uicontrol",
            inheritsFromURIs: ["apple-docs://uikit/uiview"],
            inheritedByURIs: ["apple-docs://uikit/uiswitch", "apple-docs://uikit/uistepper"]
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uiview",
            inheritsFromURIs: ["apple-docs://uikit/uiresponder"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uiresponder",
            inheritsFromURIs: ["apple-docs://objectivec/nsobject"],
            inheritedByURIs: nil
        )
    }

    /// Index a symbol under docs_metadata so `resolveSymbolURIs` can find it.
    private static func indexSymbol(
        _ idx: Search.Index,
        uri: String,
        framework: String,
        title: String
    ) async throws {
        let jsonData = """
        {"title":"\(title)","kind":"class","framework":"\(framework)","source":"apple-docs"}
        """
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            title: title,
            content: "stub content for \(title)",
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            jsonData: jsonData
        ))
    }

    // MARK: - walkInheritance up direction

    @Test("walkInheritance up returns the full ancestor chain (UIButton → ... → NSObject)")
    func walkUpFullChain() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await Self.seedUIButtonChain(idx)

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uibutton",
            direction: .up,
            maxDepth: 10
        )
        await idx.disconnect()

        #expect(tree.startURI == "apple-docs://uikit/uibutton")
        #expect(tree.descendants.isEmpty, "up walk should not collect descendants")
        try #require(tree.ancestors.count == 1)
        // First ancestor: UIControl.
        let control = try #require(tree.ancestors.first)
        #expect(control.uri == "apple-docs://uikit/uicontrol")
        // Then UIView nested inside UIControl.
        try #require(control.children.count == 1)
        let view = control.children[0]
        #expect(view.uri == "apple-docs://uikit/uiview")
        // Then UIResponder.
        try #require(view.children.count == 1)
        #expect(view.children[0].uri == "apple-docs://uikit/uiresponder")
        // Then NSObject (the chain terminus).
        try #require(view.children[0].children.count == 1)
        #expect(view.children[0].children[0].uri == "apple-docs://objectivec/nsobject")
    }

    @Test("walkInheritance up honours maxDepth (cuts the chain at the requested depth)")
    func walkUpHonoursDepth() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await Self.seedUIButtonChain(idx)

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uibutton",
            direction: .up,
            maxDepth: 1
        )
        await idx.disconnect()

        try #require(tree.ancestors.count == 1)
        #expect(
            tree.ancestors[0].children.isEmpty,
            "depth-1 walk should stop after one hop; got \(tree.ancestors[0].children)"
        )
    }

    // MARK: - walkInheritance down direction

    @Test("walkInheritance down returns immediate children of UIControl")
    func walkDownReturnsChildren() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await Self.seedUIButtonChain(idx)

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uicontrol",
            direction: .down,
            maxDepth: 1
        )
        await idx.disconnect()

        #expect(tree.ancestors.isEmpty)
        let childURIs = Set(tree.descendants.map(\.uri))
        #expect(childURIs == Set([
            "apple-docs://uikit/uibutton",
            "apple-docs://uikit/uiswitch",
            "apple-docs://uikit/uistepper",
        ]))
    }

    // MARK: - walkInheritance both

    @Test("walkInheritance both populates ancestors AND descendants from the middle node")
    func walkBothReturnsBothSides() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await Self.seedUIButtonChain(idx)

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uicontrol",
            direction: .both,
            maxDepth: 1
        )
        await idx.disconnect()

        #expect(tree.ancestors.map(\.uri) == ["apple-docs://uikit/uiview"])
        #expect(Set(tree.descendants.map(\.uri)) == Set([
            "apple-docs://uikit/uibutton",
            "apple-docs://uikit/uiswitch",
            "apple-docs://uikit/uistepper",
        ]))
    }

    @Test("walkInheritance on a node with no edges returns empty tree (isEmpty == true)")
    func walkEmptyForLeafNode() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://swiftui/text",
            direction: .both,
            maxDepth: 5
        )
        await idx.disconnect()

        #expect(tree.isEmpty)
    }

    // MARK: - resolveSymbolURIs

    @Test("resolveSymbolURIs returns one candidate for a unique title")
    func resolveUniqueTitle() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexSymbol(idx, uri: "apple-docs://uikit/uibutton", framework: "uikit", title: "UIButton")

        let candidates = try await idx.resolveSymbolURIs(title: "UIButton")
        await idx.disconnect()

        #expect(candidates.count == 1)
        #expect(candidates.first?.uri == "apple-docs://uikit/uibutton")
        #expect(candidates.first?.framework == "uikit")
    }

    @Test("resolveSymbolURIs returns multiple candidates for an ambiguous title (Color: SwiftUI + AppKit)")
    func resolveAmbiguousTitle() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexSymbol(idx, uri: "apple-docs://swiftui/color", framework: "swiftui", title: "Color")
        try await Self.indexSymbol(idx, uri: "apple-docs://appkit/nscolor", framework: "appkit", title: "Color")

        let candidates = try await idx.resolveSymbolURIs(title: "Color")
        await idx.disconnect()

        #expect(candidates.count == 2)
        let frameworks = Set(candidates.map(\.framework))
        #expect(frameworks == Set(["swiftui", "appkit"]))
    }

    @Test("resolveSymbolURIs is case-insensitive (`uibutton` matches `UIButton`)")
    func resolveCaseInsensitive() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexSymbol(idx, uri: "apple-docs://uikit/uibutton", framework: "uikit", title: "UIButton")

        let lower = try await idx.resolveSymbolURIs(title: "uibutton")
        let mixed = try await idx.resolveSymbolURIs(title: "UIBUTTON")
        await idx.disconnect()

        #expect(lower.count == 1)
        #expect(mixed.count == 1)
    }

    @Test("resolveSymbolURIs returns empty when title doesn't match any apple-docs row")
    func resolveEmptyForUnknownTitle() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        let candidates = try await idx.resolveSymbolURIs(title: "ThisClassDoesNotExist")
        await idx.disconnect()

        #expect(candidates.isEmpty)
    }
}

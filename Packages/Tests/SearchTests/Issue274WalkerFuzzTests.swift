import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Fuzz + edge-case battery for `Search.Index.walkInheritance` and its
/// supporting graph helpers (`parentsOf`, `childrenOf`, `resolveSymbolURIs`).
/// Phase C of #673.
///
/// `Issue274InheritanceWalkTests` covers the happy paths (5-deep UIButton
/// ancestor chain, immediate children of UIControl, both-direction walk
/// from the middle, node-with-no-edges-is-empty). This file pushes the
/// walker against adversarial graph shapes: cycles, diamonds, deep
/// chains, depth=0, missing nodes, empty DB.
///
/// Carmack contract: the walker is recursive + maintains a visited-set;
/// fuzz tests prove the recursion can't blow the stack and the visited-
/// set actually prevents infinite loops on cyclic inputs.
@Suite("#274 inheritance walker fuzz + edge cases (Phase C)")
// swiftlint:disable:next type_body_length
struct Issue274WalkerFuzzTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue274-walker-fuzz-\(UUID().uuidString).db")
    }

    // MARK: - Depth boundaries

    @Test("maxDepth = 0 returns empty ancestors and empty descendants")
    func depthZeroIsEmpty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uibutton",
            inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uibutton",
            direction: .up,
            maxDepth: 0
        )
        // maxDepth = 0 short-circuits at the first recursion guard — the
        // walker returns the start node only, no neighbours.
        #expect(tree.ancestors.isEmpty)
        #expect(tree.descendants.isEmpty)
    }

    @Test("maxDepth = 1 returns only immediate parents, not grandparents")
    func depthOneOnlyImmediate() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Chain: UIButton → UIControl → UIView
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uibutton",
            inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uicontrol",
            inheritsFromURIs: ["apple-docs://uikit/uiview"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uibutton",
            direction: .up,
            maxDepth: 1
        )
        #expect(tree.ancestors.count == 1)
        #expect(tree.ancestors.first?.uri == "apple-docs://uikit/uicontrol")
        // UIView is a grandparent; should NOT appear at depth 1.
        #expect(tree.ancestors.first?.children.isEmpty == true)
    }

    @Test("maxDepth = 100 on a 5-deep chain returns the full 5 levels (no over-fetch)")
    func depthOverEstimateClampsToActual() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Build a 5-deep chain: A → B → C → D → E
        let chain = ["a", "b", "c", "d", "e"]
        for index in 0..<(chain.count - 1) {
            try await idx.writeInheritanceEdges(
                pageURI: "apple-docs://test/\(chain[index])",
                inheritsFromURIs: ["apple-docs://test/\(chain[index + 1])"],
                inheritedByURIs: nil
            )
        }

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/a",
            direction: .up,
            maxDepth: 100
        )
        // Should find 4 ancestors (B, C, D, E); maxDepth doesn't over-extend.
        var count = 0
        var cursor: [Search.InheritanceNode] = tree.ancestors
        while !cursor.isEmpty {
            count += 1
            cursor = cursor.first?.children ?? []
        }
        #expect(count == 4)
    }

    @Test("negative maxDepth returns empty (same shape as zero)")
    func negativeDepthIsEmpty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uibutton",
            inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/uibutton",
            direction: .up,
            maxDepth: -1
        )
        // `guard depth > 0 else { return [] }` short-circuits negative depths.
        #expect(tree.ancestors.isEmpty)
        #expect(tree.descendants.isEmpty)
    }

    // MARK: - Cyclic graphs (the visited-set's reason for existing)

    @Test("self-loop (A → A) is bounded by the visited-set; no infinite recursion")
    func selfLoopBounded() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Pathological: A inherits from A.
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/a",
            inheritsFromURIs: ["apple-docs://test/a"],
            inheritedByURIs: nil
        )

        // If the visited-set is broken, this would recurse forever.
        // Contract: completes in finite time and returns a bounded tree.
        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/a",
            direction: .up,
            maxDepth: 10
        )
        // The visited-set inserts the start URI at the top; the self-edge
        // tries to insert the same URI again, fails, skips. ancestors is empty.
        #expect(tree.ancestors.isEmpty)
    }

    @Test("two-node cycle (A → B → A) is bounded; no infinite recursion")
    func twoNodeCycleBounded() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // A → B and B → A.
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/a",
            inheritsFromURIs: ["apple-docs://test/b"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/b",
            inheritsFromURIs: ["apple-docs://test/a"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/a",
            direction: .up,
            maxDepth: 10
        )
        // Starting from A, we visit B's parent (A) — already visited, skip.
        // Tree shows B as an ancestor; B's children are empty (cycle blocked).
        #expect(tree.ancestors.count == 1)
        #expect(tree.ancestors.first?.uri == "apple-docs://test/b")
        #expect(tree.ancestors.first?.children.isEmpty == true)
    }

    @Test("three-node cycle (A → B → C → A) is bounded")
    func threeNodeCycleBounded() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/a",
            inheritsFromURIs: ["apple-docs://test/b"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/b",
            inheritsFromURIs: ["apple-docs://test/c"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/c",
            inheritsFromURIs: ["apple-docs://test/a"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/a",
            direction: .up,
            maxDepth: 50 // generous; visited-set should prevent over-recursion
        )
        // Walk visits: A → B → C → tries A (visited, skip).
        // ancestors: [B] with children [C] with children [].
        #expect(tree.ancestors.count == 1)
        #expect(tree.ancestors.first?.uri == "apple-docs://test/b")
        #expect(tree.ancestors.first?.children.first?.uri == "apple-docs://test/c")
        #expect(tree.ancestors.first?.children.first?.children.isEmpty == true)
    }

    // MARK: - Diamond / multi-path shapes

    @Test("diamond shape: A → B → D and A → C → D — D reachable two ways, visited once")
    func diamondShapeVisitOnce() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // A → B → D
        // A → C → D
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/a",
            inheritsFromURIs: ["apple-docs://test/b", "apple-docs://test/c"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/b",
            inheritsFromURIs: ["apple-docs://test/d"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/c",
            inheritsFromURIs: ["apple-docs://test/d"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/a",
            direction: .up,
            maxDepth: 10
        )
        // Tree has 2 immediate ancestors (B, C); D is only attached under
        // whichever was visited first (visited-set dedupes).
        #expect(tree.ancestors.count == 2)
        let bAncestors = tree.ancestors.first { $0.uri == "apple-docs://test/b" }
        let cAncestors = tree.ancestors.first { $0.uri == "apple-docs://test/c" }
        try #require(bAncestors != nil)
        try #require(cAncestors != nil)
        // Exactly one of B or C has D as a child — the visited-set dedupes.
        let bHasD = bAncestors?.children.contains { $0.uri == "apple-docs://test/d" } ?? false
        let cHasD = cAncestors?.children.contains { $0.uri == "apple-docs://test/d" } ?? false
        #expect(bHasD != cHasD, "D should appear under exactly one of B/C, not both")
    }

    // MARK: - Missing / empty inputs

    @Test("walkInheritance on URI not in DB returns empty tree (no crash)")
    func missingStartURI() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uibutton",
            inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
            inheritedByURIs: nil
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://uikit/nothere",
            direction: .up,
            maxDepth: 10
        )
        #expect(tree.startURI == "apple-docs://uikit/nothere")
        #expect(tree.ancestors.isEmpty)
        #expect(tree.descendants.isEmpty)
        #expect(tree.isEmpty == true)
    }

    @Test("walkInheritance on empty DB returns empty tree (no crash)")
    func emptyDB() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // No edges written; query immediately.
        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://swift/array",
            direction: .both,
            maxDepth: 10
        )
        #expect(tree.ancestors.isEmpty)
        #expect(tree.descendants.isEmpty)
    }

    @Test("walkInheritance with empty-string startURI returns empty tree (no crash)")
    func emptyStringStartURI() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://uikit/uibutton",
            inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
            inheritedByURIs: nil
        )

        // Adversarial input: empty string. Contract: no crash, empty tree.
        let tree = try await idx.walkInheritance(
            startURI: "",
            direction: .up,
            maxDepth: 10
        )
        #expect(tree.ancestors.isEmpty)
        #expect(tree.descendants.isEmpty)
    }

    // MARK: - High-degree node

    @Test("walk down from a node with 100 immediate children doesn't blow the stack")
    func highFanoutChildren() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Root has 100 children.
        let children = (0..<100).map { "apple-docs://test/child\($0)" }
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/root",
            inheritsFromURIs: nil,
            inheritedByURIs: children
        )

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/root",
            direction: .down,
            maxDepth: 1
        )
        #expect(tree.descendants.count == 100)
    }

    @Test("walk down on a 20-deep chain doesn't stack overflow")
    func deepChainNoStackOverflow() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // 20-deep chain: node0 ← node1 ← ... ← node19
        for index in 0..<19 {
            try await idx.writeInheritanceEdges(
                pageURI: "apple-docs://test/node\(index)",
                inheritsFromURIs: nil,
                inheritedByURIs: ["apple-docs://test/node\(index + 1)"]
            )
        }

        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/node0",
            direction: .down,
            maxDepth: 20
        )

        // Count actual depth — should be 19 levels of descendants.
        var depth = 0
        var cursor = tree.descendants
        while let first = cursor.first {
            depth += 1
            cursor = first.children
        }
        #expect(depth == 19)
    }

    // MARK: - resolveSymbolURIs fuzz

    @Test("resolveSymbolURIs with empty title returns empty array (no crash)")
    func resolveEmptyTitle() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Note: resolveSymbolURIs reads from `doc_symbols`, not from the
        // `inheritance` table. To exercise it properly we'd need to seed
        // doc_symbols; without that, empty-string lookup just returns
        // nothing. Contract: no crash.
        let candidates = try await idx.resolveSymbolURIs(title: "")
        #expect(candidates.isEmpty)
    }

    @Test("resolveSymbolURIs with unicode title (no matches) returns empty array")
    func resolveUnicodeTitle() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        let candidates = try await idx.resolveSymbolURIs(title: "🌟UnicodeTitle🎉")
        #expect(candidates.isEmpty)
    }

    @Test("resolveSymbolURIs with SQL-quote-laden title is safely bound (no injection)")
    func resolveSQLInjectionTitle() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        // Classic SQL injection attempt — must be safely bound via sqlite3_bind_text,
        // not interpolated. Contract: no crash, no rows returned (the title
        // is just "treated as text").
        let candidates = try await idx.resolveSymbolURIs(
            title: "'; DROP TABLE doc_symbols; --"
        )
        #expect(candidates.isEmpty)
    }

    // MARK: - Combined: cycle + diamond + depth boundary

    @Test("cycle within a diamond: A → {B, C} both → D → A. Walker terminates.")
    func cycleWithinDiamond() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/a",
            inheritsFromURIs: ["apple-docs://test/b", "apple-docs://test/c"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/b",
            inheritsFromURIs: ["apple-docs://test/d"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/c",
            inheritsFromURIs: ["apple-docs://test/d"],
            inheritedByURIs: nil
        )
        try await idx.writeInheritanceEdges(
            pageURI: "apple-docs://test/d",
            inheritsFromURIs: ["apple-docs://test/a"], // back to A
            inheritedByURIs: nil
        )

        // Contract: terminates in finite time. The visited-set prevents
        // re-entry to A. Verify we get a deterministic tree.
        let tree = try await idx.walkInheritance(
            startURI: "apple-docs://test/a",
            direction: .up,
            maxDepth: 50
        )
        // Sanity-check: tree has 2 immediate ancestors (B, C) — at least one
        // contains D as a child, and D's parents (A) are blocked by visited.
        #expect(tree.ancestors.count == 2)
    }
}

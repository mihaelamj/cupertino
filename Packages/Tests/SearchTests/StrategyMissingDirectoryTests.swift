import Foundation
@testable import Search
import SearchModels
import SharedConstants
import Testing

// Unit tests for the "directory not found" fast path of each concrete
// SourceIndexingStrategy type.  These tests exercise the guard at the top of
// every indexItems(into:progress:) implementation that returns early when the
// configured directory is absent — ensuring strategies return cleanly with
// zero counts rather than throwing or crashing.
//
// SampleCodeStrategy and SwiftPackagesStrategy have no directory parameter and
// are intentionally excluded from this suite; their empty-catalog fast path is
// covered by the existing SearchTests integration suite.

@Suite("SourceIndexingStrategy missing-directory fast paths", .serialized)
struct StrategyMissingDirectoryTests {
    // MARK: - Helpers

    /// A temporary Search.Index backed by an in-memory-style path unique per test.
    private func makeIndex(in tempRoot: URL) async throws -> Search.Index {
        try await Search.Index(dbPath: tempRoot.appendingPathComponent("search.db"))
    }

    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("strategy-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - AppleDocsStrategy

    @Test("AppleDocsStrategy returns zero counts when docsDirectory is absent")
    func appleDocsMissingDirectory() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let missingDir = tempRoot.appendingPathComponent("docs")
        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.AppleDocsStrategy(
            docsDirectory: missingDir,
            markdownToStructuredPage: { _, _ in nil }
        )

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 0)
        #expect(stats.skipped == 0)
        #expect(try await index.documentCount() == 0)
    }

    @Test("AppleDocsStrategy returns zero counts when docsDirectory is empty")
    func appleDocsEmptyDirectory() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let emptyDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.AppleDocsStrategy(
            docsDirectory: emptyDir,
            markdownToStructuredPage: { _, _ in nil }
        )

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 0)
        #expect(stats.skipped == 0)
    }

    // MARK: - AppleArchiveStrategy

    @Test("AppleArchiveStrategy returns zero counts when archiveDirectory is absent")
    func appleArchiveMissingDirectory() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let missingDir = tempRoot.appendingPathComponent("archive")
        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.AppleArchiveStrategy(archiveDirectory: missingDir)

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 0)
        #expect(stats.skipped == 0)
    }

    // MARK: - HIGStrategy

    @Test("HIGStrategy returns zero counts when higDirectory is absent")
    func higMissingDirectory() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let missingDir = tempRoot.appendingPathComponent("hig")
        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.HIGStrategy(higDirectory: missingDir)

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 0)
        #expect(stats.skipped == 0)
    }

    // MARK: - SwiftEvolutionStrategy

    @Test("SwiftEvolutionStrategy returns zero counts when evolutionDirectory is absent")
    func swiftEvolutionMissingDirectory() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let missingDir = tempRoot.appendingPathComponent("swift-evolution")
        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.SwiftEvolutionStrategy(evolutionDirectory: missingDir)

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 0)
        #expect(stats.skipped == 0)
    }

    @Test("SwiftEvolutionStrategy skips non-accepted proposals")
    func swiftEvolutionSkipsWithdrawnProposals() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let evolutionDir = tempRoot.appendingPathComponent("swift-evolution")
        try FileManager.default.createDirectory(at: evolutionDir, withIntermediateDirectories: true)
        // A withdrawn proposal — should not be indexed.
        let withdrawnContent = """
        # SE-9999 Withdrawn Feature
        * Status: **Withdrawn**
        This proposal has been withdrawn.
        """
        try withdrawnContent.write(
            to: evolutionDir.appendingPathComponent("SE-9999-withdrawn.md"),
            atomically: true, encoding: .utf8
        )

        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.SwiftEvolutionStrategy(evolutionDirectory: evolutionDir)
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.skipped == 1)
        #expect(stats.indexed == 0)
        #expect(try await index.documentCount() == 0)
    }

    // MARK: - SwiftOrgStrategy

    @Test("SwiftOrgStrategy returns zero counts when swiftOrgDirectory is absent")
    func swiftOrgMissingDirectory() async throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let missingDir = tempRoot.appendingPathComponent("swift-org")
        let index = try await makeIndex(in: tempRoot)
        let strategy = Search.SwiftOrgStrategy(
            swiftOrgDirectory: missingDir,
            markdownToStructuredPage: { _, _ in nil }
        )

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 0)
        #expect(stats.skipped == 0)
    }
}

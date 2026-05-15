import Foundation
@testable import Indexer
import SharedConstants
import Testing

// MARK: - Preflight (#232, lifted to Indexer in #244)

@Suite("Indexer.Preflight.preflightLines (#232)")
struct IndexerPreflightLinesTests {
    @Test("Empty base dir — all three scopes report missing")
    func emptyBaseAllMissing() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = Indexer.Preflight.preflightLines(
            paths: Shared.Paths(baseDirectory: dir),
            buildDocs: true,
            buildPackages: true,
            buildSamples: true,
            baseDir: dir.path,
            docsDir: nil,
            samplesDir: dir.appendingPathComponent("sample-code").path
        )

        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("Docs (search.db)"))
        #expect(joined.contains("Packages (packages.db)"))
        #expect(joined.contains("Samples (samples.db)"))
        #expect(joined.contains("missing"))
    }

    @Test("Skipped scopes don't appear in output")
    func skippedScopesAbsent() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = Indexer.Preflight.preflightLines(
            paths: Shared.Paths(baseDirectory: dir),
            buildDocs: false,
            buildPackages: true,
            buildSamples: false,
            baseDir: dir.path,
            docsDir: nil,
            samplesDir: nil
        )

        let joined = lines.joined(separator: "\n")
        #expect(!joined.contains("Docs (search.db)"))
        #expect(joined.contains("Packages (packages.db)"))
        #expect(!joined.contains("Samples (samples.db)"))
    }

    @Test("Packages dir with sidecars reports full coverage")
    func packagesWithSidecars() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pkgRoot = dir.appendingPathComponent("packages/apple/swift-nio")
        try FileManager.default.createDirectory(at: pkgRoot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pkgRoot.appendingPathComponent("availability.json"))

        let lines = Indexer.Preflight.preflightLines(
            paths: Shared.Paths(baseDirectory: dir),
            buildDocs: false,
            buildPackages: true,
            buildSamples: false,
            baseDir: dir.path
        )
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("(1 packages)"))
        #expect(joined.contains("(1/1)"))
    }

    @Test("Packages dir without sidecars flags missing annotations")
    func packagesWithoutSidecars() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pkgRoot = dir.appendingPathComponent("packages/apple/swift-nio")
        try FileManager.default.createDirectory(at: pkgRoot, withIntermediateDirectories: true)
        // No availability.json

        let lines = Indexer.Preflight.preflightLines(
            paths: Shared.Paths(baseDirectory: dir),
            buildDocs: false,
            buildPackages: true,
            buildSamples: false,
            baseDir: dir.path
        )
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("(0/1)"))
        #expect(joined.contains("backfill"))
    }

    private static func makeEmptyTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexer-preflight-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

@Suite("Indexer.Preflight.countPackagesAndSidecars")
struct IndexerCountPackagesTests {
    @Test("Counts owner/repo dirs and matching availability.json sidecars")
    func countsCorrectly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexer-count-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (owner, repo, hasSidecar) in [
            ("apple", "swift-nio", true),
            ("apple", "swift-collections", false),
            ("vapor", "vapor", true),
        ] {
            let pkg = dir.appendingPathComponent("\(owner)/\(repo)")
            try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
            if hasSidecar {
                try Data("{}".utf8).write(to: pkg.appendingPathComponent("availability.json"))
            }
        }

        let stats = Indexer.Preflight.countPackagesAndSidecars(at: dir)
        #expect(stats.packages == 3)
        #expect(stats.sidecars == 2)
    }
}

@Suite("Indexer.Preflight.checkDocsHaveAvailability")
struct IndexerCheckDocsAvailabilityTests {
    @Test("Empty docs dir returns false")
    func emptyDocsReturnsFalse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexer-docs-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(Indexer.Preflight.checkDocsHaveAvailability(docsDir: dir) == false)
    }

    @Test("Missing docs dir returns false")
    func missingDocsReturnsFalse() {
        let nowhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexer-docs-nowhere-\(UUID().uuidString)")
        #expect(Indexer.Preflight.checkDocsHaveAvailability(docsDir: nowhere) == false)
    }
}

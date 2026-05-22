import Foundation
@testable import SearchStrategies
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

// MARK: - #779 / optional source dir symlink resolution

//
// Integration tests for the #779 fix. The fix lives in
// `Indexer.DocsService.optionalDir`, which now returns
// `url.resolvingSymlinksInPath()` before handing the URL to the source
// strategies. Without that resolution, `FileManager.contentsOfDirectory(at:)`
// (URL variant) does not follow a leaf directory-symlink: the kernel returns
// `ENOTDIR` (POSIX 20), Foundation wraps as `NSCocoaErrorDomain` code 256
// (`NSFileReadUnknownError`) with the bare "couldn't be opened" string. This
// was the root cause of the 2026-05-18 11h15m reindex crash.
//
// The fix is at the composition root (optionalDir is `private static`, so it
// is not directly addressable from tests). These tests cover the observable
// behaviour:
//
//   Positive: when the strategy receives a URL that HAS been resolved (the
//   post-fix path), it indexes through the leaf symlink cleanly.
//
//   Negative: when the strategy receives the raw symlink URL (the pre-fix
//   path), it throws NSCocoa 256 with the documented ENOTDIR signature. This
//   pins the bug as a regression sentinel: any future change that breaks
//   resolvingSymlinksInPath() at the composition root will surface here.

@Suite("#779 / SwiftEvolutionStrategy through a leaf directory-symlink", .serialized)
struct Issue779OptionalDirSymlinkTests {
    private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
        func convert(markdown: String, url: URL?) -> Shared.Models.StructuredDocumentationPage? {
            nil
        }
    }

    private func makeIndex(in tempRoot: URL) async throws -> Search.Index {
        try await Search.Index(
            dbPath: tempRoot.appendingPathComponent("search.db"),
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
    }

    /// Stage a tmp dir with:
    ///  - `real-swift-evolution/SE-0001-test.md` (one accepted-status proposal)
    ///  - `swift-evolution -> real-swift-evolution` (leaf directory-symlink)
    /// Returns (tmpRoot, realDir, symlink). Caller cleans up via tmpRoot.
    private func makeSymlinkFixture() throws -> (tmpRoot: URL, realDir: URL, symlink: URL) {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue-779-optionaldir-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        let realDir = tmpRoot.appendingPathComponent("real-swift-evolution")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)

        // SE proposal with an Implemented status so the strategy's accepted-status
        // filter (`Search.StrategyHelpers.isAcceptedProposal`) does not drop it.
        let acceptedContent = """
        # SE-0001 Test Proposal (Issue779OptionalDirSymlinkTests fixture)

        * Proposal: [SE-0001](0001-test.md)
        * Status: **Implemented (Swift 5.0)**

        ## Introduction

        Fixture content for the #779 integration test.
        """
        try acceptedContent.write(
            to: realDir.appendingPathComponent("SE-0001-test.md"),
            atomically: true, encoding: .utf8
        )

        let symlink = tmpRoot.appendingPathComponent("swift-evolution")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realDir)

        return (tmpRoot, realDir, symlink)
    }

    // MARK: - Positive: post-fix path indexes through the symlink

    @Test("Post-fix: SwiftEvolutionStrategy with URL.resolvingSymlinksInPath() indexes through the leaf symlink")
    func resolvedSymlinkIndexesSuccessfully() async throws {
        let fixture = try makeSymlinkFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmpRoot) }

        // What optionalDir does at the composition root. The strategy
        // receives the resolved URL, not the symlink.
        let resolvedURL = fixture.symlink.resolvingSymlinksInPath()

        let index = try await makeIndex(in: fixture.tmpRoot)
        let strategy = Search.SwiftEvolutionStrategy(
            evolutionDirectory: resolvedURL,
            logger: Logging.NoopRecording()
        )

        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 1, "should index the one accepted proposal; got \(stats.indexed)")
        #expect(stats.skipped == 0)
        #expect(stats.wasSkipped == false, "not a clean skip; the source IS available")
        #expect(stats.skipReason == nil)
        #expect(try await index.documentCount() == 1, "one row written to docs_metadata")
    }

    // MARK: - Negative: pre-fix path throws ENOTDIR (regression sentinel)

    @Test("Pre-fix sentinel: SwiftEvolutionStrategy with raw symlink URL throws NSCocoa 256 (ENOTDIR via NSPOSIX 20)")
    func rawSymlinkThrowsENOTDIRSentinel() async throws {
        let fixture = try makeSymlinkFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmpRoot) }

        // Pre-fix shape: hand the strategy the raw symlink URL directly,
        // bypassing optionalDir's resolvingSymlinksInPath(). The strategy's
        // contentsOfDirectory(at:) call must throw because the URL-variant API
        // does not follow leaf directory-symlinks. Any future regression that
        // breaks the composition-root resolution will fall through to this
        // path and crash here.
        let index = try await makeIndex(in: fixture.tmpRoot)
        let strategy = Search.SwiftEvolutionStrategy(
            evolutionDirectory: fixture.symlink, // NOT resolved
            logger: Logging.NoopRecording()
        )

        do {
            _ = try await strategy.indexItems(into: index, progress: nil)
            Issue.record("expected NSCocoa 256 (ENOTDIR) throw on raw symlink URL, got clean return")
        } catch {
            let ns = error as NSError
            #expect(ns.domain == NSCocoaErrorDomain, "unexpected domain: \(ns.domain)")
            #expect(ns.code == 256, "unexpected code: \(ns.code) (256 = NSFileReadUnknownError, the catch-all wrapper)")

            if let inner = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                #expect(inner.domain == NSPOSIXErrorDomain, "unexpected underlying domain: \(inner.domain)")
                #expect(inner.code == 20, "expected ENOTDIR (POSIX 20); got \(inner.code)")
            } else {
                Issue.record("expected NSUnderlyingError carrying NSPOSIXErrorDomain code 20 (ENOTDIR), got nil")
            }
        }

        #expect(try await index.documentCount() == 0, "no rows written when the strategy threw")
    }
}

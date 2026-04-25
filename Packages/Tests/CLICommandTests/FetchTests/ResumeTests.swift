@testable import CLI
@testable import Core
import Foundation
@testable import Shared
import Testing
import TestSupport

// MARK: - Auto-Resume + --start-clean Tests
//
// Regression tests for the v1.0 simplification of the fetch resume model.
//
// What changed:
//   - `--resume` flag removed (was a log-message switch only)
//   - Auto-resume is now the default — `cupertino fetch` picks up an active
//     `crawlState` from `metadata.json` whenever the start URL matches
//   - `--start-clean` flag added — wipes `crawlState` so the next run starts
//     from the seed URL with an empty queue
//
// These tests guard the two behaviors at the persistence layer (CrawlerState
// for auto-resume, FetchCommand.clearSavedSession for --start-clean), so a
// future refactor that breaks either path fails CI instead of silently
// stranding users on stale or non-resumable crawls.

@Suite("Auto-Resume and Start-Clean Tests")
struct ResumeAndStartCleanTests {
    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-resume-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func metadataFile(in dir: URL) -> URL {
        dir.appendingPathComponent(Shared.Constants.FileName.metadata)
    }

    private static func writeFixtureMetadata(
        at file: URL,
        startURL: String,
        outputDirectory: String,
        visited: Set<String>,
        queue: [(url: String, depth: Int)],
        isActive: Bool = true
    ) throws {
        let queued = queue.map { QueuedURL(url: $0.url, depth: $0.depth) }
        let crawlState = CrawlSessionState(
            visited: visited,
            queue: queued,
            startURL: startURL,
            outputDirectory: outputDirectory,
            sessionStartTime: Date(timeIntervalSince1970: 1_700_000_000),
            lastSaveTime: Date(timeIntervalSince1970: 1_700_000_500),
            isActive: isActive
        )
        var metadata = CrawlMetadata()
        metadata.crawlState = crawlState
        metadata.stats.totalPages = visited.count
        metadata.stats.newPages = visited.count
        try metadata.save(to: file)
    }

    // MARK: - --start-clean

    @Test("--start-clean is a no-op when no metadata.json exists")
    func startCleanNoMetadataIsNoOp() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Should not throw.
        try FetchCommand.clearSavedSession(at: tempDir)

        // Should not have created the file as a side effect.
        #expect(!FileManager.default.fileExists(atPath: Self.metadataFile(in: tempDir).path))
    }

    @Test("--start-clean wipes crawlState while preserving the rest of metadata.json")
    func startCleanWipesCrawlStateOnly() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        try Self.writeFixtureMetadata(
            at: file,
            startURL: "http://127.0.0.1:1/seed",
            outputDirectory: tempDir.path,
            visited: ["http://127.0.0.1:1/a", "http://127.0.0.1:1/b", "http://127.0.0.1:1/c"],
            queue: [
                (url: "http://127.0.0.1:1/q1", depth: 1),
                (url: "http://127.0.0.1:1/q2", depth: 2),
            ]
        )

        // Sanity: crawlState is there before the wipe.
        let before = try CrawlMetadata.load(from: file)
        #expect(before.crawlState != nil)
        #expect(before.crawlState?.isActive == true)
        #expect(before.crawlState?.visited.count == 3)
        #expect(before.crawlState?.queue.count == 2)
        #expect(before.stats.totalPages == 3)

        try FetchCommand.clearSavedSession(at: tempDir)

        // crawlState is gone; the other fields are intact (so we don't lose
        // accumulated stats / page hashes — those are what change-detection
        // uses to skip unchanged pages on the resumed run).
        let after = try CrawlMetadata.load(from: file)
        #expect(after.crawlState == nil)
        #expect(after.stats.totalPages == 3, "stats must survive --start-clean")
        #expect(after.stats.newPages == 3, "stats must survive --start-clean")
    }

    @Test("--start-clean leaves the file readable and re-runnable")
    func startCleanLeavesFileValidJSON() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        try Self.writeFixtureMetadata(
            at: file,
            startURL: "http://127.0.0.1:1/seed",
            outputDirectory: tempDir.path,
            visited: ["http://127.0.0.1:1/old"],
            queue: [(url: "http://127.0.0.1:1/q", depth: 0)]
        )

        try FetchCommand.clearSavedSession(at: tempDir)

        // The file must be valid JSON parsable as CrawlMetadata — if it's
        // truncated or corrupt, the next `cupertino fetch` will throw at
        // load time and the user is locked out of resume.
        let reloaded = try CrawlMetadata.load(from: file)
        #expect(reloaded.crawlState == nil)

        // And running --start-clean a second time on the already-cleaned file
        // is also a no-throw no-op.
        try FetchCommand.clearSavedSession(at: tempDir)
        let twiceCleaned = try CrawlMetadata.load(from: file)
        #expect(twiceCleaned.crawlState == nil)
    }

    // MARK: - Auto-resume (CrawlerState)

    @Test("Fresh CrawlerState picks up an active session from metadata.json")
    func crawlerStateAutoLoadsActiveSession() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        try Self.writeFixtureMetadata(
            at: file,
            startURL: "http://127.0.0.1:1/seed",
            outputDirectory: tempDir.path,
            visited: ["http://127.0.0.1:1/a", "http://127.0.0.1:1/b"],
            queue: [
                (url: "http://127.0.0.1:1/q1", depth: 0),
                (url: "http://127.0.0.1:1/q2", depth: 1),
                (url: "http://127.0.0.1:1/q3", depth: 1),
            ]
        )

        // A new CrawlerState (the only thing the Crawler instantiates on
        // startup before deciding whether to resume) reads the on-disk
        // session through its init / `getSavedSession`.
        let config = Shared.ChangeDetectionConfiguration(
            metadataFile: file,
            outputDirectory: tempDir
        )
        let state = CrawlerState(configuration: config)

        let hasSession = await state.hasActiveSession()
        #expect(hasSession, "auto-resume must observe isActive=true on disk")

        let session = await state.getSavedSession()
        #expect(session != nil)
        #expect(session?.isActive == true)
        #expect(session?.visited.count == 2)
        #expect(session?.queue.count == 3)
        #expect(session?.startURL == "http://127.0.0.1:1/seed")
    }

    @Test("Fresh CrawlerState reports no active session when metadata.json has no crawlState")
    func crawlerStateNoActiveSessionWhenMissing() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Empty metadata — no crawlState field.
        let file = Self.metadataFile(in: tempDir)
        let metadata = CrawlMetadata()
        try metadata.save(to: file)

        let config = Shared.ChangeDetectionConfiguration(
            metadataFile: file,
            outputDirectory: tempDir
        )
        let state = CrawlerState(configuration: config)

        let hasSession = await state.hasActiveSession()
        #expect(!hasSession)
        let session = await state.getSavedSession()
        #expect(session == nil)
    }

    @Test("--start-clean + fresh CrawlerState = no active session")
    func startCleanThenLoadHasNoActiveSession() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        try Self.writeFixtureMetadata(
            at: file,
            startURL: "http://127.0.0.1:1/seed",
            outputDirectory: tempDir.path,
            visited: ["http://127.0.0.1:1/a"],
            queue: [(url: "http://127.0.0.1:1/q", depth: 0)]
        )

        // Wipe via the same code path the CLI uses.
        try FetchCommand.clearSavedSession(at: tempDir)

        // The Crawler's resume read sees nothing, so it'll start fresh from
        // the seed URL — exactly what --start-clean should produce.
        let config = Shared.ChangeDetectionConfiguration(
            metadataFile: file,
            outputDirectory: tempDir
        )
        let state = CrawlerState(configuration: config)

        let hasSession = await state.hasActiveSession()
        #expect(!hasSession, "--start-clean must leave no resumable session")
    }

    // MARK: - Cross-machine portability (checkForSession)
    //
    // Regression for the path-resolution bug: `metadata.json.crawlState.outputDirectory`
    // stores an absolute path captured on the machine that ran the original
    // crawl. When the directory is rsynced to a second host (different home
    // dir, mounted volume), that saved path points at nothing on the new host.
    // `checkForSession` must return the directory where it *found* the
    // metadata.json — that's the live output directory by definition.

    @Test("checkForSession returns the directory where metadata.json was found, not the saved path")
    func checkForSessionReturnsFoundDirectoryNotSavedPath() async throws {
        let foundDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: foundDir) }

        // Simulate a metadata.json that was rsynced from a different machine —
        // the saved `outputDirectory` is some path that doesn't exist locally.
        let foreignPath = "/Users/some-other-user/.cupertino/docs"
        #expect(!FileManager.default.fileExists(atPath: foreignPath),
                "test premise: foreign path must not exist locally")

        try Self.writeFixtureMetadata(
            at: Self.metadataFile(in: foundDir),
            startURL: "https://developer.apple.com/documentation/",
            outputDirectory: foreignPath, // ← saved path from the other machine
            visited: ["https://developer.apple.com/documentation/swift"],
            queue: [(url: "https://developer.apple.com/documentation/foundation", depth: 0)]
        )

        let resolved = FetchCommand.checkForSession(
            at: foundDir,
            matching: URL(string: "https://developer.apple.com/documentation/")!
        )

        // BUG (pre-fix): would return URL(fileURLWithPath: foreignPath) —
        //   a path that doesn't exist on this host, so the crawler would then
        //   try to write into a phantom directory under the wrong home.
        // FIX: return foundDir — the live, on-disk location of the metadata.
        #expect(resolved == foundDir,
                "checkForSession must return the dir it inspected, not the saved path")
        #expect(resolved?.path != foreignPath,
                "must NOT return the foreign saved path")
        #expect(FileManager.default.fileExists(atPath: resolved?.path ?? "/__missing__"),
                "the returned dir must actually exist on this host")
    }

    @Test("checkForSession returns nil when start URL doesn't match")
    func checkForSessionReturnsNilOnStartURLMismatch() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.writeFixtureMetadata(
            at: Self.metadataFile(in: dir),
            startURL: "https://developer.apple.com/documentation/",
            outputDirectory: dir.path,
            visited: ["https://developer.apple.com/documentation/swift"],
            queue: []
        )

        // A different start URL (different framework crawl) — should not be
        // confused for a resumable session.
        let resolved = FetchCommand.checkForSession(
            at: dir,
            matching: URL(string: "https://docs.swift.org/swift-book")!
        )
        #expect(resolved == nil)
    }

    @Test("checkForSession returns nil when crawlState.isActive is false")
    func checkForSessionReturnsNilWhenInactive() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.writeFixtureMetadata(
            at: Self.metadataFile(in: dir),
            startURL: "https://developer.apple.com/documentation/",
            outputDirectory: dir.path,
            visited: ["https://developer.apple.com/documentation/swift"],
            queue: [],
            isActive: false // ← finished cleanly, no active session to resume
        )

        let resolved = FetchCommand.checkForSession(
            at: dir,
            matching: URL(string: "https://developer.apple.com/documentation/")!
        )
        #expect(resolved == nil)
    }

    @Test("checkForSession returns nil when no metadata.json exists")
    func checkForSessionReturnsNilWhenMissing() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolved = FetchCommand.checkForSession(
            at: dir,
            matching: URL(string: "https://developer.apple.com/documentation/")!
        )
        #expect(resolved == nil)
    }

    @Test("checkForSession is the right answer even when foreign path coincidentally exists")
    func checkForSessionStillReturnsFoundDirEvenIfForeignPathExists() async throws {
        // Belt-and-suspenders: even if a directory happens to exist at the
        // saved foreign path, `checkForSession` must still return the dir
        // where the metadata was actually located. Otherwise a stale
        // ~/.cupertino/docs left over from a previous install could swallow
        // a fresh crawl-data dir on a new mount point.
        let realFoundDir = try Self.makeTempDir()
        let coincidentalForeignDir = try Self.makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: realFoundDir)
            try? FileManager.default.removeItem(at: coincidentalForeignDir)
        }

        try Self.writeFixtureMetadata(
            at: Self.metadataFile(in: realFoundDir),
            startURL: "https://developer.apple.com/documentation/",
            outputDirectory: coincidentalForeignDir.path, // exists, but wrong
            visited: ["https://developer.apple.com/documentation/swift"],
            queue: []
        )

        let resolved = FetchCommand.checkForSession(
            at: realFoundDir,
            matching: URL(string: "https://developer.apple.com/documentation/")!
        )
        #expect(resolved == realFoundDir,
                "must return where we found metadata, not where the saved path happens to point")
        #expect(resolved != coincidentalForeignDir)
    }

    @Test("CrawlerState round-trip: save → reload via fresh instance restores all fields")
    func crawlerStateSaveReloadRoundTrip() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        let config = Shared.ChangeDetectionConfiguration(
            metadataFile: file,
            outputDirectory: tempDir
        )

        // Save through the real crawler API.
        let writer = CrawlerState(configuration: config)
        let visited: Set<String> = [
            "http://127.0.0.1:1/v1",
            "http://127.0.0.1:1/v2",
            "http://127.0.0.1:1/v3",
        ]
        let queue: [(url: URL, depth: Int)] = [
            (url: URL(string: "http://127.0.0.1:1/q1")!, depth: 0),
            (url: URL(string: "http://127.0.0.1:1/q2")!, depth: 1),
        ]
        try await writer.saveSessionState(
            visited: visited,
            queue: queue,
            startURL: URL(string: "http://127.0.0.1:1/seed")!,
            outputDirectory: tempDir
        )

        // Read through a *fresh* CrawlerState — the actual scenario when
        // the cupertino process is killed and re-launched.
        let reader = CrawlerState(configuration: config)
        let session = await reader.getSavedSession()
        #expect(session != nil)
        #expect(session?.isActive == true)
        #expect(session?.visited == visited)
        #expect(session?.queue.count == 2)
        #expect(session?.startURL == "http://127.0.0.1:1/seed")
    }
}

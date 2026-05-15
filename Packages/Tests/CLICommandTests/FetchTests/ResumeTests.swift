@testable import CLI
@testable import Core
import CoreProtocols
@testable import Crawler
import CrawlerModels
import Foundation
import LoggingModels
import Ingest
import SharedConstants
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
// These tests guard the two behaviors at the persistence layer (Crawler.AppleDocs.State
// for auto-resume, Ingest.Session.clearSavedSession for --start-clean), so a
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
        let queued = queue.map { Shared.Models.QueuedURL(url: $0.url, depth: $0.depth) }
        let crawlState = Shared.Models.CrawlSessionState(
            visited: visited,
            queue: queued,
            startURL: startURL,
            outputDirectory: outputDirectory,
            sessionStartTime: Date(timeIntervalSince1970: 1700000000),
            lastSaveTime: Date(timeIntervalSince1970: 1700000500),
            isActive: isActive
        )
        var metadata = Shared.Models.CrawlMetadata()
        metadata.crawlState = crawlState
        metadata.stats.totalPages = visited.count
        metadata.stats.newPages = visited.count
        try metadata.save(to: file)
    }

    // MARK: - --start-clean

    @Test("--start-clean is a no-op when no metadata.json exists")
    func startCleanNoMetadataIsNoOp() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Should not throw.
        try Ingest.Session.clearSavedSession(at: tempDir, logger: Logging.NoopRecording())

        // Should not have created the file as a side effect.
        #expect(!FileManager.default.fileExists(atPath: Self.metadataFile(in: tempDir).path))
    }

    @Test("--start-clean wipes crawlState while preserving the rest of metadata.json")
    func startCleanWipesCrawlStateOnly() throws {
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
        let before = try Shared.Models.CrawlMetadata.load(from: file)
        #expect(before.crawlState != nil)
        #expect(before.crawlState?.isActive == true)
        #expect(before.crawlState?.visited.count == 3)
        #expect(before.crawlState?.queue.count == 2)
        #expect(before.stats.totalPages == 3)

        try Ingest.Session.clearSavedSession(at: tempDir, logger: Logging.NoopRecording())

        // crawlState is gone; the other fields are intact (so we don't lose
        // accumulated stats / page hashes — those are what change-detection
        // uses to skip unchanged pages on the resumed run).
        let after = try Shared.Models.CrawlMetadata.load(from: file)
        #expect(after.crawlState == nil)
        #expect(after.stats.totalPages == 3, "stats must survive --start-clean")
        #expect(after.stats.newPages == 3, "stats must survive --start-clean")
    }

    @Test("--start-clean leaves the file readable and re-runnable")
    func startCleanLeavesFileValidJSON() throws {
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

        try Ingest.Session.clearSavedSession(at: tempDir, logger: Logging.NoopRecording())

        // The file must be valid JSON parsable as CrawlMetadata — if it's
        // truncated or corrupt, the next `cupertino fetch` will throw at
        // load time and the user is locked out of resume.
        let reloaded = try Shared.Models.CrawlMetadata.load(from: file)
        #expect(reloaded.crawlState == nil)

        // And running --start-clean a second time on the already-cleaned file
        // is also a no-throw no-op.
        try Ingest.Session.clearSavedSession(at: tempDir, logger: Logging.NoopRecording())
        let twiceCleaned = try Shared.Models.CrawlMetadata.load(from: file)
        #expect(twiceCleaned.crawlState == nil)
    }

    // MARK: - --retry-errors

    /// Build a fixture where some visited URLs lack a corresponding `pages` entry.
    /// These represent crawl-time errors (e.g. filename-too-long save failures)
    /// that need re-queueing for the resumed crawl to retry.
    private static func writeFixtureWithErroredPages(
        at file: URL,
        outputDirectory: String,
        savedURLs: [String],
        erroredURLs: [String]
    ) throws {
        var pages: [String: Shared.Models.PageMetadata] = [:]
        for url in savedURLs {
            pages[url] = Shared.Models.PageMetadata(
                url: url,
                framework: "test",
                filePath: "/tmp/foo.json",
                contentHash: "deadbeef",
                depth: 0
            )
        }
        let visited = Set(savedURLs + erroredURLs)
        let crawlState = Shared.Models.CrawlSessionState(
            visited: visited,
            queue: [],
            startURL: "https://example.com/",
            outputDirectory: outputDirectory
        )
        var metadata = Shared.Models.CrawlMetadata()
        metadata.crawlState = crawlState
        metadata.pages = pages
        try metadata.save(to: file)
    }

    @Test("--retry-errors is a no-op when no metadata.json exists")
    func retryErrorsNoMetadataIsNoOp() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Ingest.Session.requeueErroredURLs(at: tempDir, maxDepth: 15, logger: Logging.NoopRecording())
        #expect(!FileManager.default.fileExists(atPath: Self.metadataFile(in: tempDir).path))
    }

    @Test("--retry-errors does nothing when every visited URL is already in pages dict")
    func retryErrorsNoOpWhenAllSaved() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        try Self.writeFixtureWithErroredPages(
            at: file,
            outputDirectory: tempDir.path,
            savedURLs: [
                "https://example.com/a",
                "https://example.com/b",
                "https://example.com/c",
            ],
            erroredURLs: []
        )

        try Ingest.Session.requeueErroredURLs(at: tempDir, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: file)
        #expect(after.crawlState?.queue.isEmpty == true, "queue should remain empty")
        #expect(after.crawlState?.visited.count == 3)
    }

    @Test("--retry-errors re-queues visited URLs that aren't in pages dict")
    func retryErrorsRequeuesUnsavedURLs() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)

        // Two long URLs from the actual 2026-04-30 error log — exactly the
        // shape the filename-too-long bug would have produced.
        let erroredA = "https://developer.apple.com/documentation/metalperformanceshaders/mpssvgf/encodereprojection"
            + "(to:sourcetexture:previoustexture:destinationtexture:previousluminancemomentstexture:"
            + "destinationluminancemomentstexture:previousframecount:destinationframecount:"
            + "motionvectortexture:depthnormaltexture:previousdepthnormaltex-3k6zp"
        let erroredB = "https://developer.apple.com/documentation/accelerate/bnns/fusedconvolutionnormalizationlayer/"
            + "init(input:output:convolutionweights:convolutionbias:convolutionstride:"
            + "convolutiondilationstride:convolutionpadding:normalization:normalizationbeta:"
            + "normalizationgamma:normalizationmomentum:normalizationepsilon:normalizationactivation:filter-30cwy"

        try Self.writeFixtureWithErroredPages(
            at: file,
            outputDirectory: tempDir.path,
            savedURLs: [
                "https://developer.apple.com/documentation/swift/array",
                "https://developer.apple.com/documentation/swiftui/view",
            ],
            erroredURLs: [erroredA, erroredB]
        )

        try Ingest.Session.requeueErroredURLs(at: tempDir, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: file)
        let queueURLs = Set(after.crawlState?.queue.map(\.url) ?? [])
        #expect(queueURLs == [erroredA, erroredB])
        #expect(
            after.crawlState?.queue.allSatisfy { $0.depth == 15 } == true,
            "errored URLs should re-enter at maxDepth so children aren't re-crawled"
        )

        // Retries must be prepended (processed first), not appended after a
        // potentially huge existing queue.
        let firstTwo = Set((after.crawlState?.queue.prefix(2) ?? []).map(\.url))
        #expect(firstTwo == [erroredA, erroredB], "errored URLs must be at the front of the queue")

        // The errored URLs must come out of the visited set so the crawler
        // doesn't immediately skip them on dequeue.
        #expect(after.crawlState?.visited.contains(erroredA) == false)
        #expect(after.crawlState?.visited.contains(erroredB) == false)

        // Already-saved URLs stay in visited so they get skipped (no double-fetch).
        #expect(after.crawlState?.visited.contains("https://developer.apple.com/documentation/swift/array") == true)
        #expect(after.crawlState?.visited.contains("https://developer.apple.com/documentation/swiftui/view") == true)
    }

    // MARK: - --baseline

    /// Write a fake baseline file with a `url` field at <dir>/<framework>/<slug>.json.
    private static func writeBaselineFile(
        in dir: URL,
        framework: String,
        slug: String,
        url: String
    ) throws {
        let frameworkDir = dir.appendingPathComponent(framework)
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        let file = frameworkDir.appendingPathComponent("\(slug).json")
        let payload = "{ \"url\": \"\(url)\" }"
        try payload.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test("--baseline injects URLs that exist in baseline but not in claw's known set")
    func baselineInjectsMissingURLs() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselineDir = tempDir.appendingPathComponent("baseline")
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        try Self.writeBaselineFile(
            in: baselineDir,
            framework: "swift",
            slug: "array",
            url: "https://developer.apple.com/documentation/swift/array"
        )
        try Self.writeBaselineFile(
            in: baselineDir,
            framework: "swift",
            slug: "dictionary",
            url: "https://developer.apple.com/documentation/swift/dictionary"
        )
        try Self.writeBaselineFile(
            in: baselineDir,
            framework: "uikit",
            slug: "view",
            url: "https://developer.apple.com/documentation/uikit/view"
        )

        // Claw already has /swift/array; the other 2 should get injected.
        try Self.writeFixtureWithErroredPages(
            at: Self.metadataFile(in: tempDir),
            outputDirectory: tempDir.path,
            savedURLs: ["https://developer.apple.com/documentation/swift/array"],
            erroredURLs: []
        )

        try Ingest.Session.requeueFromBaseline(at: tempDir, baselineDir: baselineDir, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        let queueURLs = Set(after.crawlState?.queue.map(\.url) ?? [])
        #expect(queueURLs.count == 2)
        #expect(queueURLs.contains("https://developer.apple.com/documentation/swift/dictionary"))
        #expect(queueURLs.contains("https://developer.apple.com/documentation/uikit/view"))
        #expect(after.crawlState?.queue.allSatisfy { $0.depth == 15 } == true)
    }

    @Test("--baseline matching is case-insensitive on the documentation path")
    func baselineCaseInsensitiveMatching() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselineDir = tempDir.appendingPathComponent("baseline")
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        // Baseline has the capitalized form (HTML-extractor output)
        try Self.writeBaselineFile(
            in: baselineDir,
            framework: "swift",
            slug: "array",
            url: "https://developer.apple.com/documentation/Swift/Array"
        )

        // Claw has the lowercase form (JSON-extractor output)
        try Self.writeFixtureWithErroredPages(
            at: Self.metadataFile(in: tempDir),
            outputDirectory: tempDir.path,
            savedURLs: ["https://developer.apple.com/documentation/swift/array"],
            erroredURLs: []
        )

        try Ingest.Session.requeueFromBaseline(at: tempDir, baselineDir: baselineDir, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        // Already known case-insensitively → should NOT be injected.
        #expect(
            after.crawlState?.queue.isEmpty == true,
            "case-insensitive match should treat /Swift/Array == /swift/array as the same URL"
        )
    }

    @Test("--baseline is a no-op when baseline directory doesn't exist")
    func baselineMissingDirectoryIsNoOp() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Self.writeFixtureWithErroredPages(
            at: Self.metadataFile(in: tempDir),
            outputDirectory: tempDir.path,
            savedURLs: ["https://developer.apple.com/documentation/swift/array"],
            erroredURLs: []
        )

        let nonExistent = tempDir.appendingPathComponent("nope")
        try Ingest.Session.requeueFromBaseline(at: tempDir, baselineDir: nonExistent, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        #expect(after.crawlState?.queue.isEmpty == true)
    }

    @Test("--baseline is a no-op when baseline is empty")
    func baselineEmptyDirectoryIsNoOp() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselineDir = tempDir.appendingPathComponent("baseline")
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        try Self.writeFixtureWithErroredPages(
            at: Self.metadataFile(in: tempDir),
            outputDirectory: tempDir.path,
            savedURLs: ["https://developer.apple.com/documentation/swift/array"],
            erroredURLs: []
        )

        try Ingest.Session.requeueFromBaseline(at: tempDir, baselineDir: baselineDir, maxDepth: 15, logger: Logging.NoopRecording())
        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        #expect(after.crawlState?.queue.isEmpty == true)
    }

    @Test("--baseline skips files without a url field and non-JSON files")
    func baselineSkipsMalformedFiles() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselineDir = tempDir.appendingPathComponent("baseline")
        let frameworkDir = baselineDir.appendingPathComponent("swift")
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        // Valid file
        try Self.writeBaselineFile(
            in: baselineDir,
            framework: "swift",
            slug: "array",
            url: "https://developer.apple.com/documentation/swift/array"
        )
        // No-url JSON
        try "{ \"title\": \"no url here\" }".write(
            to: frameworkDir.appendingPathComponent("nourl.json"),
            atomically: true, encoding: .utf8
        )
        // Non-JSON file
        try "<html></html>".write(
            to: frameworkDir.appendingPathComponent("page.html"),
            atomically: true, encoding: .utf8
        )

        try Self.writeFixtureWithErroredPages(
            at: Self.metadataFile(in: tempDir),
            outputDirectory: tempDir.path,
            savedURLs: [],
            erroredURLs: []
        )

        try Ingest.Session.requeueFromBaseline(at: tempDir, baselineDir: baselineDir, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        let queueURLs = (after.crawlState?.queue ?? []).map(\.url)
        #expect(queueURLs == ["https://developer.apple.com/documentation/swift/array"])
    }

    @Test("--baseline injected items are prepended (queue front), not appended")
    func baselinePrependsToQueueFront() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselineDir = tempDir.appendingPathComponent("baseline")
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        try Self.writeBaselineFile(
            in: baselineDir,
            framework: "swift",
            slug: "array",
            url: "https://developer.apple.com/documentation/swift/array"
        )

        // Pre-populate queue with an existing item
        try Self.writeFixtureMetadata(
            at: Self.metadataFile(in: tempDir),
            startURL: "https://example.com/seed",
            outputDirectory: tempDir.path,
            visited: [],
            queue: [(url: "https://developer.apple.com/documentation/uikit/already-queued", depth: 0)]
        )

        try Ingest.Session.requeueFromBaseline(at: tempDir, baselineDir: baselineDir, maxDepth: 15, logger: Logging.NoopRecording())

        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        let queue = after.crawlState?.queue ?? []
        #expect(queue.count == 2)
        #expect(
            queue.first?.url == "https://developer.apple.com/documentation/swift/array",
            "baseline-injected URLs must be at the FRONT of the queue, not the back"
        )
    }

    @Test("--retry-errors gracefully handles missing crawlState")
    func retryErrorsHandlesMissingCrawlState() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a metadata.json with no crawlState (e.g. cleared by --start-clean).
        var metadata = Shared.Models.CrawlMetadata()
        try metadata.save(to: Self.metadataFile(in: tempDir))

        // Should not throw and should not synthesize a crawlState.
        try Ingest.Session.requeueErroredURLs(at: tempDir, maxDepth: 15, logger: Logging.NoopRecording())
        let after = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        #expect(after.crawlState == nil)
    }

    // MARK: - Auto-resume (Crawler.AppleDocs.State)

    @Test("Fresh Crawler.AppleDocs.State picks up an active session from metadata.json")
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

        // A new Crawler.AppleDocs.State (the only thing the Crawler instantiates on
        // startup before deciding whether to resume) reads the on-disk
        // session through its init / `getSavedSession`.
        let config = Shared.Configuration.ChangeDetection(
            metadataFile: file,
            outputDirectory: tempDir
        )
        let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

        let hasSession = await state.hasActiveSession()
        #expect(hasSession, "auto-resume must observe isActive=true on disk")

        let session = await state.getSavedSession()
        #expect(session != nil)
        #expect(session?.isActive == true)
        #expect(session?.visited.count == 2)
        #expect(session?.queue.count == 3)
        #expect(session?.startURL == "http://127.0.0.1:1/seed")
    }

    @Test("Fresh Crawler.AppleDocs.State reports no active session when metadata.json has no crawlState")
    func crawlerStateNoActiveSessionWhenMissing() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Empty metadata — no crawlState field.
        let file = Self.metadataFile(in: tempDir)
        let metadata = Shared.Models.CrawlMetadata()
        try metadata.save(to: file)

        let config = Shared.Configuration.ChangeDetection(
            metadataFile: file,
            outputDirectory: tempDir
        )
        let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

        let hasSession = await state.hasActiveSession()
        #expect(!hasSession)
        let session = await state.getSavedSession()
        #expect(session == nil)
    }

    @Test("--start-clean + fresh Crawler.AppleDocs.State = no active session")
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
        try Ingest.Session.clearSavedSession(at: tempDir, logger: Logging.NoopRecording())

        // The Crawler's resume read sees nothing, so it'll start fresh from
        // the seed URL — exactly what --start-clean should produce.
        let config = Shared.Configuration.ChangeDetection(
            metadataFile: file,
            outputDirectory: tempDir
        )
        let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

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
    func checkForSessionReturnsFoundDirectoryNotSavedPath() throws {
        let foundDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: foundDir) }

        // Simulate a metadata.json that was rsynced from a different machine —
        // the saved `outputDirectory` is some path that doesn't exist locally.
        let foreignPath = "/Users/some-other-user/.cupertino/docs"
        #expect(
            !FileManager.default.fileExists(atPath: foreignPath),
            "test premise: foreign path must not exist locally"
        )

        try Self.writeFixtureMetadata(
            at: Self.metadataFile(in: foundDir),
            startURL: "https://developer.apple.com/documentation/",
            outputDirectory: foreignPath, // ← saved path from the other machine
            visited: ["https://developer.apple.com/documentation/swift"],
            queue: [(url: "https://developer.apple.com/documentation/foundation", depth: 0)]
        )

        let resolved = try Ingest.Session.checkForSession(
            at: foundDir,
            matching: #require(URL(string: "https://developer.apple.com/documentation/")),
            logger: Logging.NoopRecording()
        )

        // BUG (pre-fix): would return URL(fileURLWithPath: foreignPath) —
        //   a path that doesn't exist on this host, so the crawler would then
        //   try to write into a phantom directory under the wrong home.
        // FIX: return foundDir — the live, on-disk location of the metadata.
        #expect(
            resolved == foundDir,
            "checkForSession must return the dir it inspected, not the saved path"
        )
        #expect(
            resolved?.path != foreignPath,
            "must NOT return the foreign saved path"
        )
        #expect(
            FileManager.default.fileExists(atPath: resolved?.path ?? "/__missing__"),
            "the returned dir must actually exist on this host"
        )
    }

    @Test("checkForSession returns nil when start URL doesn't match")
    func checkForSessionReturnsNilOnStartURLMismatch() throws {
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
        let resolved = try Ingest.Session.checkForSession(
            at: dir,
            matching: #require(URL(string: "https://docs.swift.org/swift-book")),
            logger: Logging.NoopRecording()
        )
        #expect(resolved == nil)
    }

    @Test("checkForSession returns nil when crawlState.isActive is false")
    func checkForSessionReturnsNilWhenInactive() throws {
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

        let resolved = try Ingest.Session.checkForSession(
            at: dir,
            matching: #require(URL(string: "https://developer.apple.com/documentation/")),
            logger: Logging.NoopRecording()
        )
        #expect(resolved == nil)
    }

    @Test("checkForSession returns nil when no metadata.json exists")
    func checkForSessionReturnsNilWhenMissing() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolved = try Ingest.Session.checkForSession(
            at: dir,
            matching: #require(URL(string: "https://developer.apple.com/documentation/")),
            logger: Logging.NoopRecording()
        )
        #expect(resolved == nil)
    }

    @Test("checkForSession is the right answer even when foreign path coincidentally exists")
    func checkForSessionStillReturnsFoundDirEvenIfForeignPathExists() throws {
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

        let resolved = try Ingest.Session.checkForSession(
            at: realFoundDir,
            matching: #require(URL(string: "https://developer.apple.com/documentation/")),
            logger: Logging.NoopRecording()
        )
        #expect(
            resolved == realFoundDir,
            "must return where we found metadata, not where the saved path happens to point"
        )
        #expect(resolved != coincidentalForeignDir)
    }

    // MARK: - Cross-machine page path rebasing

    //
    // `PageMetadata.filePath` is an absolute string captured on the writing
    // host. After rsync to a machine with a different home dir, those strings
    // point at nothing. Crawler.AppleDocs.State's load path now rebases them to the
    // current `metadataFile`'s parent directory + framework + basename, so:
    //   * `validateMetadata` doesn't false-negative and wipe the saved session
    //   * `SearchIndexBuilder` reads pages from the right place
    //   * `MCP.Support.DocsResourceProvider` resolves correctly

    private static func writeFixturePagesAndFile(
        outputDir: URL,
        framework: String,
        filename: String,
        foreignFilePath: String
    ) throws -> Shared.Models.PageMetadata {
        // Make the actual file on disk under outputDir/framework/.
        let frameworkDir = outputDir.appendingPathComponent(framework)
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        let filePath = frameworkDir.appendingPathComponent(filename)
        try Data("{}".utf8).write(to: filePath)

        // PageMetadata records the *foreign* path — same basename / framework
        // as the on-disk file, but a host-specific absolute prefix.
        return Shared.Models.PageMetadata(
            url: "https://developer.apple.com/documentation/\(framework)",
            framework: framework,
            filePath: foreignFilePath,
            contentHash: "abc123",
            depth: 0
        )
    }

    @Test("validateMetadata accepts rsynced metadata: foreign filePath but file exists at portable path")
    func validateMetadataRsynced() throws {
        let outputDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let metadataFile = Self.metadataFile(in: outputDir)

        // Build a metadata fixture: 3 pages whose `filePath` strings are from
        // a different machine, but whose actual files exist under outputDir.
        // This is the rsync-from-another-host scenario — exact bug we hit on Claw.
        var metadata = Shared.Models.CrawlMetadata()
        let frameworks = ["accessibility", "swiftui", "foundation"]
        for fw in frameworks {
            let page = try Self.writeFixturePagesAndFile(
                outputDir: outputDir,
                framework: fw,
                filename: "documentation_\(fw).json",
                foreignFilePath: "/Users/some-other-user/.cupertino/docs/\(fw)/documentation_\(fw).json"
            )
            metadata.pages[page.url] = page
        }
        try metadata.save(to: metadataFile)

        let result = Crawler.AppleDocs.State.validateMetadata(metadata, metadataFile: metadataFile, logger: Logging.NoopRecording())
        #expect(result, "validation must pass when the *portable* path (outputDir+framework+basename) resolves, even if filePath strings are foreign")
    }

    @Test("validateMetadata rejects metadata when no actual files exist (lying metadata)")
    func validateMetadataRejectsLies() throws {
        let outputDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // 5 page entries, but no files on disk → genuinely lying metadata
        var metadata = Shared.Models.CrawlMetadata()
        for fw in ["a", "b", "c", "d", "e"] {
            metadata.pages["https://x/\(fw)"] = Shared.Models.PageMetadata(
                url: "https://x/\(fw)",
                framework: fw,
                filePath: "/anywhere/\(fw)/file.json",
                contentHash: "h",
                depth: 0
            )
        }
        let metadataFile = Self.metadataFile(in: outputDir)
        try metadata.save(to: metadataFile)

        let result = Crawler.AppleDocs.State.validateMetadata(metadata, metadataFile: metadataFile, logger: Logging.NoopRecording())
        #expect(!result, "validation must reject metadata claiming pages that don't exist on this host at all")
    }

    @Test("rebasePagePaths rewrites foreign filePaths to the current outputDir")
    func rebasePathsRewrites() {
        // Use UUID-randomised paths so they're guaranteed not to exist on
        // the test host — rebasePagePaths only rewrites entries whose saved
        // path doesn't resolve. (A literal path like /Users/foo/.cupertino
        // could collide with an actual user's directory and skip the rewrite,
        // which is the right behavior at runtime but breaks this test.)
        let foreignRoot = "/__nonexistent-foreign-host-\(UUID().uuidString)"
        let outputDir = URL(fileURLWithPath: "/__nonexistent-target-host-\(UUID().uuidString)/cupertino/docs")
        var metadata = Shared.Models.CrawlMetadata()
        metadata.pages["u1"] = Shared.Models.PageMetadata(
            url: "u1",
            framework: "accessibility",
            filePath: "\(foreignRoot)/cupertino/docs/accessibility/documentation_accessibility.json",
            contentHash: "h1",
            depth: 0
        )
        metadata.pages["u2"] = Shared.Models.PageMetadata(
            url: "u2",
            framework: "swiftui",
            filePath: "\(foreignRoot)/some/swiftui/documentation_swiftui.json",
            contentHash: "h2",
            depth: 0
        )

        Crawler.AppleDocs.State.rebasePagePaths(in: &metadata, to: outputDir)

        let expectedU1 = outputDir.appendingPathComponent("accessibility")
            .appendingPathComponent("documentation_accessibility.json").path
        let expectedU2 = outputDir.appendingPathComponent("swiftui")
            .appendingPathComponent("documentation_swiftui.json").path
        #expect(metadata.pages["u1"]?.filePath == expectedU1)
        #expect(metadata.pages["u2"]?.filePath == expectedU2)
        // Other fields preserved
        #expect(metadata.pages["u1"]?.contentHash == "h1")
        #expect(metadata.pages["u2"]?.framework == "swiftui")
    }

    @Test("rebasePagePaths is idempotent — running twice does not change paths")
    func rebasePathsIdempotent() {
        let outputDir = URL(fileURLWithPath: "/Volumes/ClawSSD/.cupertino/docs")
        var metadata = Shared.Models.CrawlMetadata()
        metadata.pages["u1"] = Shared.Models.PageMetadata(
            url: "u1",
            framework: "accessibility",
            filePath: "/Volumes/ClawSSD/.cupertino/docs/accessibility/documentation_accessibility.json",
            contentHash: "h1",
            depth: 0
        )

        Crawler.AppleDocs.State.rebasePagePaths(in: &metadata, to: outputDir)
        let firstPass = metadata.pages["u1"]?.filePath
        Crawler.AppleDocs.State.rebasePagePaths(in: &metadata, to: outputDir)
        let secondPass = metadata.pages["u1"]?.filePath

        #expect(firstPass == secondPass)
        #expect(firstPass == "/Volumes/ClawSSD/.cupertino/docs/accessibility/documentation_accessibility.json")
    }

    @Test("End-to-end rsync scenario: foreign metadata + crawlState loads with full session restored")
    func crossMachineFullScenario() async throws {
        let outputDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let metadataFile = Self.metadataFile(in: outputDir)

        // Stage 1: build a metadata.json that looks like it came from another
        // host. crawlState marks the session active; pages dict has foreign
        // filePaths but the actual files exist under outputDir.
        var metadata = Shared.Models.CrawlMetadata()
        for fw in ["accessibility", "swiftui", "foundation"] {
            let page = try Self.writeFixturePagesAndFile(
                outputDir: outputDir,
                framework: fw,
                filename: "documentation_\(fw).json",
                foreignFilePath: "/Users/foreign/.cupertino/docs/\(fw)/documentation_\(fw).json"
            )
            metadata.pages[page.url] = page
        }
        metadata.crawlState = Shared.Models.CrawlSessionState(
            visited: [
                "https://developer.apple.com/documentation/accessibility",
                "https://developer.apple.com/documentation/swiftui",
            ],
            queue: [Shared.Models.QueuedURL(url: "https://developer.apple.com/documentation/foundation", depth: 0)],
            startURL: "https://developer.apple.com/documentation/",
            outputDirectory: "/Users/foreign/.cupertino/docs",
            sessionStartTime: Date(),
            lastSaveTime: Date(),
            isActive: true
        )
        try metadata.save(to: metadataFile)

        // Stage 2: a fresh Crawler.AppleDocs.State (the post-rsync simulation)
        let config = Shared.Configuration.ChangeDetection(
            metadataFile: metadataFile,
            outputDirectory: outputDir
        )
        let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

        // The session must survive — it would have been wiped pre-fix because
        // validateMetadata couldn't find any files at the foreign paths.
        let hasSession = await state.hasActiveSession()
        #expect(hasSession, "post-rsync metadata must keep crawlState alive")
        let session = await state.getSavedSession()
        #expect(session?.visited.count == 2)
        #expect(session?.queue.count == 1)
        let pageCount = await state.getPageCount()
        #expect(pageCount == 3)
    }

    @Test("Crawler.AppleDocs.State round-trip: save → reload via fresh instance restores all fields")
    func crawlerStateSaveReloadRoundTrip() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = Self.metadataFile(in: tempDir)
        let config = Shared.Configuration.ChangeDetection(
            metadataFile: file,
            outputDirectory: tempDir
        )

        // Save through the real crawler API.
        let writer = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())
        let visited: Set = [
            "http://127.0.0.1:1/v1",
            "http://127.0.0.1:1/v2",
            "http://127.0.0.1:1/v3",
        ]
        let queue: [(url: URL, depth: Int)] = try [
            (url: #require(URL(string: "http://127.0.0.1:1/q1")), depth: 0),
            (url: #require(URL(string: "http://127.0.0.1:1/q2")), depth: 1),
        ]
        try await writer.saveSessionState(
            visited: visited,
            queue: queue,
            startURL: #require(URL(string: "http://127.0.0.1:1/seed")),
            outputDirectory: tempDir
        )

        // Read through a *fresh* Crawler.AppleDocs.State — the actual scenario when
        // the cupertino process is killed and re-launched.
        let reader = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())
        let session = await reader.getSavedSession()
        #expect(session != nil)
        #expect(session?.isActive == true)
        #expect(session?.visited == visited)
        #expect(session?.queue.count == 2)
        #expect(session?.startURL == "http://127.0.0.1:1/seed")
    }

    // MARK: - --urls (#210)

    private static let seedURL = URL(string: "https://developer.apple.com/documentation/")!

    private static func writeURLsFile(in dir: URL, lines: [String]) throws -> URL {
        let file = dir.appendingPathComponent("urls.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test("--urls enqueues every URL at depth 0 into a fresh corpus (so descent follows up to maxDepth)")
    func urlsEnqueuesIntoFreshCorpus() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlsFile = try Self.writeURLsFile(in: tempDir, lines: [
            "https://developer.apple.com/documentation/swiftui",
            "https://developer.apple.com/documentation/visionos",
            "https://developer.apple.com/documentation/accessibility",
        ])

        try Ingest.Session.enqueueURLsFromFile(
            at: tempDir,
            urlsFile: urlsFile,
            maxDepth: 15,
            startURL: Self.seedURL,
            logger: Logging.NoopRecording()
        )

        let metadata = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        #expect(metadata.crawlState != nil)
        let queue = metadata.crawlState?.queue ?? []
        #expect(queue.count == 3)
        #expect(queue.allSatisfy { $0.depth == 0 })
        let queuedURLs = Set(queue.map(\.url))
        #expect(queuedURLs.contains("https://developer.apple.com/documentation/swiftui"))
        #expect(queuedURLs.contains("https://developer.apple.com/documentation/visionos"))
        #expect(queuedURLs.contains("https://developer.apple.com/documentation/accessibility"))
    }

    @Test("--urls skips blank lines and # comments")
    func urlsSkipsBlanksAndComments() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlsFile = try Self.writeURLsFile(in: tempDir, lines: [
            "# top-level frameworks rate-limited during 2026-04-30 crawl",
            "",
            "https://developer.apple.com/documentation/swiftui",
            "  # indented comment",
            "https://developer.apple.com/documentation/visionos",
            "",
            "  ",
        ])

        try Ingest.Session.enqueueURLsFromFile(
            at: tempDir,
            urlsFile: urlsFile,
            maxDepth: 15,
            startURL: Self.seedURL,
            logger: Logging.NoopRecording()
        )

        let metadata = try Shared.Models.CrawlMetadata.load(from: Self.metadataFile(in: tempDir))
        #expect(metadata.crawlState?.queue.count == 2)
    }

    @Test("--urls prepends to an existing crawlState queue")
    func urlsPrependsToExistingQueue() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metaFile = Self.metadataFile(in: tempDir)
        try Self.writeFixtureMetadata(
            at: metaFile,
            startURL: Self.seedURL.absoluteString,
            outputDirectory: tempDir.path,
            visited: [],
            queue: [
                (url: "https://developer.apple.com/documentation/existing-1", depth: 0),
                (url: "https://developer.apple.com/documentation/existing-2", depth: 1),
            ]
        )

        let urlsFile = try Self.writeURLsFile(in: tempDir, lines: [
            "https://developer.apple.com/documentation/new-a",
            "https://developer.apple.com/documentation/new-b",
        ])

        try Ingest.Session.enqueueURLsFromFile(
            at: tempDir,
            urlsFile: urlsFile,
            maxDepth: 15,
            startURL: Self.seedURL,
            logger: Logging.NoopRecording()
        )

        let metadata = try Shared.Models.CrawlMetadata.load(from: metaFile)
        let queue = metadata.crawlState?.queue ?? []
        #expect(queue.count == 4)
        // New URLs at the front, queued at depth 0 so descent follows
        #expect(queue[0].url.contains("new-a"))
        #expect(queue[0].depth == 0)
        #expect(queue[1].url.contains("new-b"))
        #expect(queue[1].depth == 0)
        // Existing URLs preserved at the tail with their original depths
        #expect(queue[2].url.contains("existing-1"))
        #expect(queue[2].depth == 0)
        #expect(queue[3].url.contains("existing-2"))
        #expect(queue[3].depth == 1)
    }

    @Test("--urls throws on a malformed line")
    func urlsThrowsOnInvalidLine() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlsFile = try Self.writeURLsFile(in: tempDir, lines: [
            "https://developer.apple.com/documentation/swiftui",
            "not a url at all just a bare phrase",
        ])

        var threw = false
        do {
            try Ingest.Session.enqueueURLsFromFile(
                at: tempDir,
                urlsFile: urlsFile,
                maxDepth: 15,
                startURL: Self.seedURL,
            logger: Logging.NoopRecording()
            )
        } catch is Ingest.FetchURLsError {
            threw = true
        }
        #expect(threw, "expected FetchURLsError on malformed input")
    }

    @Test("--urls is a no-op when the file has only blanks and comments")
    func urlsIsNoOpForEmptyEffectiveContent() throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlsFile = try Self.writeURLsFile(in: tempDir, lines: [
            "# nothing to see here",
            "",
            "  # also a comment",
        ])

        try Ingest.Session.enqueueURLsFromFile(
            at: tempDir,
            urlsFile: urlsFile,
            maxDepth: 15,
            startURL: Self.seedURL,
            logger: Logging.NoopRecording()
        )

        // Should NOT have created a metadata file as a side effect.
        #expect(!FileManager.default.fileExists(atPath: Self.metadataFile(in: tempDir).path))
    }
}

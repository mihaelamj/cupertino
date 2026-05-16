@testable import Cleanup
import Foundation
import LoggingModels
import SharedConstants
import Testing
import TestSupport

// MARK: - #656 — `cleanup --dry-run` defaults to stat-only (no zipinfo subprocess)

//
// Pre-fix every `--dry-run` archive ran `/usr/bin/zipinfo` in a
// subprocess, fanning out 627 fork+exec calls on the default sample-
// code corpus and turning a "preview" into ~3 minutes of work. PR #651
// throttled the stdout firehose but the underlying scan still ran.
//
// Post-#656, dry-run skips the per-archive zipinfo by default and the
// `Cleanup.Cleaner` reports `itemsRemoved: 0` for every archive in
// constant time. Operators who want the exact items-to-remove count
// pass `--verify` (`Cleaner.init(... verify: true)`), which restores
// the pre-#656 behaviour for the cases where it's actually wanted.
//
// This suite drives the actor with two real ZIP fixtures (one with a
// `.git` directory inside, one without) and pins:
//
// 1. Default `verify: false` returns `itemsRemoved: 0` for both, so
//    the slow path didn't run.
// 2. `verify: true` returns `itemsRemoved > 0` for the .git-bearing
//    fixture, so the slow path still works when opted in.
// 3. Real cleanup (`dryRun: false`) ignores `verify` entirely — it
//    always extracts + scans.

private func makeZip(at outURL: URL, withGit: Bool) throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-cleanup-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Always put a regular file in the zip so it isn't empty.
    let readme = tempDir.appendingPathComponent("README.md")
    try "# fixture".write(to: readme, atomically: true, encoding: .utf8)

    if withGit {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
    }

    // Build the zip with /usr/bin/zip (`-r` recursive, `-q` quiet) —
    // the CI image and macOS dev shells both ship it.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-rq", outURL.path, "."]
    process.currentDirectoryURL = tempDir
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        Issue.record("zip subprocess failed with status \(process.terminationStatus) for \(outURL.path)")
    }
}

private func makeSampleCorpus(withGitCount: Int, plainCount: Int) throws -> URL {
    let baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-cleanup-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    for i in 0..<withGitCount {
        let url = baseDir.appendingPathComponent("with-git-\(i).zip")
        try makeZip(at: url, withGit: true)
    }
    for i in 0..<plainCount {
        let url = baseDir.appendingPathComponent("plain-\(i).zip")
        try makeZip(at: url, withGit: false)
    }
    return baseDir
}

@Suite("Sample.Cleanup.Cleaner --verify flag (#656)", .serialized)
struct Issue656DryRunVerifyTests {
    @Test("Default dry-run (verify=false) skips zipinfo: itemsRemoved is zero across the corpus")
    func defaultDryRunSkipsZipinfo() async throws {
        let baseDir = try makeSampleCorpus(withGitCount: 2, plainCount: 1)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let cleaner = Sample.Cleanup.Cleaner(
            sampleCodeDirectory: baseDir,
            dryRun: true,
            keepOriginals: false,
            verify: false,
            logger: Logging.NoopRecording()
        )
        let stats = try await cleaner.cleanup()

        #expect(stats.totalArchives == 3)
        #expect(stats.errors == 0)
        // Every archive is reported with itemsRemoved=0 in the default
        // dry-run path. The .git fixtures aren't even opened.
        #expect(stats.totalItemsRemoved == 0)
        // No archive should be classified as "cleaned" — itemsRemoved=0
        // routes to the skipped bucket per the cleanup loop's logic.
        #expect(stats.cleanedArchives == 0)
        #expect(stats.skippedArchives == 3)
    }

    @Test("Opt-in --verify dry-run still runs zipinfo and counts .git fixtures")
    func verifyDryRunCountsItems() async throws {
        let baseDir = try makeSampleCorpus(withGitCount: 2, plainCount: 1)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let cleaner = Sample.Cleanup.Cleaner(
            sampleCodeDirectory: baseDir,
            dryRun: true,
            keepOriginals: false,
            verify: true,
            logger: Logging.NoopRecording()
        )
        let stats = try await cleaner.cleanup()

        #expect(stats.totalArchives == 3)
        #expect(stats.errors == 0)
        // Each `.git` fixture has at least one path component that
        // matches `cleanupPatterns` (the `.git` dir + the HEAD file
        // beneath it count); the plain fixture has zero. So the total
        // count must be >= 2 (one per git fixture).
        #expect(stats.totalItemsRemoved >= 2)
        // Both .git-bearing fixtures should be reported as having
        // items-to-remove (cleanedArchives counts those); the plain
        // one stays in skipped.
        #expect(stats.cleanedArchives == 2)
        #expect(stats.skippedArchives == 1)
    }

    @Test("Real cleanup (dryRun=false) ignores verify=false and still acts on .git fixtures")
    func realCleanupIgnoresVerifyFlag() async throws {
        // Use keepOriginals=true so the test doesn't destroy its own
        // fixtures across re-runs. Real cleanup with .git fixtures will
        // write .cleaned.zip alongside the originals.
        let baseDir = try makeSampleCorpus(withGitCount: 1, plainCount: 0)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let cleaner = Sample.Cleanup.Cleaner(
            sampleCodeDirectory: baseDir,
            dryRun: false,
            keepOriginals: true,
            verify: false, // explicitly false — must be ignored
            logger: Logging.NoopRecording()
        )
        let stats = try await cleaner.cleanup()

        #expect(stats.totalArchives == 1)
        #expect(stats.errors == 0)
        // The .git fixture had ≥ 1 path component matching the
        // cleanupPatterns set, so real cleanup must have found + removed
        // it regardless of verify.
        #expect(stats.totalItemsRemoved >= 1)
        #expect(stats.cleanedArchives == 1)
    }
}

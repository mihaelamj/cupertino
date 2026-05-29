import AppKit
import ArgumentParser
@testable import CLI
@testable import Core
@testable import CorePackageIndexing
import CoreProtocols
import Foundation
import LoggingModels
import Testing
import TestSupport

// MARK: - Fetch Command Tests

// Tests for the `cupertino fetch` command
// Verifies package fetching and sample code downloading

@Suite("Fetch Command Tests")
struct FetchCommandTests {
    @Test("Fetch Swift packages data")
    func fetchPackagesData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("🧪 Test: Fetch Swift packages")

        _ = Core.PackageIndexing.PackageFetcher(
            outputDirectory: tempDir,
            logger: Logging.NoopRecording()
        )

        // Note: This would require network access
        // For now, just verify the fetcher can be created
        // PackageFetcher doesn't expose outputDirectory publicly, so we just verify it compiles

        print("   ✅ Fetch initialization test passed!")
    }
}

// MARK: - #217 packages-merge tests

/// Coverage for #217 / #1108: `--source packages` runs the archive
/// download (stage 2) by default; stage 1 (SPI metadata + star-count
/// refresh) is opt-in via `--refresh-metadata`. These tests exercise
/// argument parsing and the empty-pipeline early-exit guard without
/// touching the network.
@Suite("Fetch Command — packages flags (#217 + #1108)")
struct FetchPackagesMergeTests {
    @Test("--refresh-metadata parses to true; archives flag defaults to false")
    func refreshMetadataParses() throws {
        let cmd = try CLIImpl.Command.Fetch.parse(["--source", "packages", "--refresh-metadata"])
        #expect(cmd.refreshMetadata == true)
        #expect(cmd.skipArchives == false)
    }

    @Test("--skip-archives parses to true; refresh flag defaults to false")
    func skipArchivesParses() throws {
        let cmd = try CLIImpl.Command.Fetch.parse(["--source", "packages", "--skip-archives"])
        #expect(cmd.refreshMetadata == false)
        #expect(cmd.skipArchives == true)
    }

    @Test("Default --source packages invocation runs stage 2 only (refreshMetadata + skipArchives both false)")
    func defaultsAreFalse() throws {
        let cmd = try CLIImpl.Command.Fetch.parse(["--source", "packages"])
        #expect(cmd.refreshMetadata == false)
        #expect(cmd.skipArchives == false)
    }

    @Test("#1108: removed --skip-metadata flag no longer parses")
    func skipMetadataNoLongerExists() {
        do {
            _ = try CLIImpl.Command.Fetch.parse(["--source", "packages", "--skip-metadata"])
            Issue.record("Expected --skip-metadata to fail parsing post-#1108; it was removed in favor of --refresh-metadata")
        } catch {
            // ArgumentParser raises an "unknown option" error. Any
            // thrown error here is the success path for this test.
        }
    }

    @Test("--request-delay parses and defaults to crawler default")
    func requestDelayParses() throws {
        let defaultCommand = try CLIImpl.Command.Fetch.parse(["--source", "apple-docs"])
        #expect(defaultCommand.requestDelay == 0.05)

        let delayedCommand = try CLIImpl.Command.Fetch.parse([
            "--source", "apple-docs",
            "--request-delay", "0.25",
        ])
        #expect(delayedCommand.requestDelay == 0.25)
    }

    @Test("--request-delay rejects negative values before fetching")
    func requestDelayRejectsNegativeValues() async throws {
        // Negative values must use the `--flag=value` form: ArgumentParser reads a
        // leading-dash token after a space as an option, not a value, so the space
        // form fails at parse before the guard can run.
        var cmd = try CLIImpl.Command.Fetch.parse([
            "--source", "apple-docs",
            "--request-delay=-0.1",
        ])

        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }
    }

    @Test("--skip-archives without --refresh-metadata or --annotate-availability exits with nothing-to-do")
    func skipArchivesWithoutPeersErrors() async throws {
        // Sandbox output dir so the guard's createDirectory doesn't write
        // into the user's real ~/.cupertino/packages/.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-skipboth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var cmd = try CLIImpl.Command.Fetch.parse([
            "--source", "packages",
            "--skip-archives",
            "--output-dir", tempDir.path,
        ])

        // Post-#1108 the empty-pipeline combo is `--skip-archives`
        // without either `--refresh-metadata` or `--annotate-
        // availability`. `PackagesFetchStrategy` throws
        // `FetchError.nothingToDo`; CLI surfaces this as a non-zero
        // exit. Any thrown Error is success.
        await #expect(throws: Error.self) {
            try await cmd.run()
        }
    }

    @Test("--source package-docs no longer parses (#217 dropped the case; #1031 dissolved FetchType enum)")
    func packageDocsRejected() async {
        // Pre-#1031: ArgumentParser surfaced invalid FetchType enum values
        // as a parse-time ValidationError (FetchType.init?(rawValue:) failed
        // for "package-docs"). Post-#1031: `--source` is a free-form String,
        // so parsing succeeds; the run() dispatch's `default:` arm throws
        // a ValidationError listing the valid source-ids. Test the new
        // run-time validation shape.
        let cmd = try? CLIImpl.Command.Fetch.parse(["--source", "package-docs"])
        guard var cmd else {
            Issue.record("Expected --source package-docs to parse successfully (Post-#1031 the validation happens at run-time, not parse-time).")
            return
        }
        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }
    }
}

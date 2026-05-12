import AppKit
import ArgumentParser
@testable import CLI
@testable import Core
@testable import CorePackageIndexing
import CoreProtocols
import Foundation
@testable import SharedCore
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

        _ = Core.PackageFetcher(
            outputDirectory: tempDir
        )

        // Note: This would require network access
        // For now, just verify the fetcher can be created
        // PackageFetcher doesn't expose outputDirectory publicly, so we just verify it compiles

        print("   ✅ Fetch initialization test passed!")
    }
}

// MARK: - #217 packages-merge tests

/// Coverage for #217: `--type packages` now runs metadata refresh + archive
/// download as two stages, gated by `--skip-metadata` / `--skip-archives`.
/// These tests exercise argument parsing and the both-skipped early-exit
/// guard without touching the network.
@Suite("Fetch Command — packages merge (#217)")
struct FetchPackagesMergeTests {
    @Test("--skip-metadata parses to true; archives flag defaults to false")
    func skipMetadataParses() throws {
        let cmd = try FetchCommand.parse(["--type", "packages", "--skip-metadata"])
        #expect(cmd.skipMetadata == true)
        #expect(cmd.skipArchives == false)
    }

    @Test("--skip-archives parses to true; metadata flag defaults to false")
    func skipArchivesParses() throws {
        let cmd = try FetchCommand.parse(["--type", "packages", "--skip-archives"])
        #expect(cmd.skipMetadata == false)
        #expect(cmd.skipArchives == true)
    }

    @Test("Default --type packages invocation has both skip flags false")
    func defaultsAreFalse() throws {
        let cmd = try FetchCommand.parse(["--type", "packages"])
        #expect(cmd.skipMetadata == false)
        #expect(cmd.skipArchives == false)
    }

    @Test("Both skip flags together exits with failure before any network call")
    func bothSkipsErrors() async throws {
        // Sandbox output dir so the guard's createDirectory doesn't write
        // into the user's real ~/.cupertino/packages/.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-skipboth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var cmd = try FetchCommand.parse([
            "--type", "packages",
            "--skip-metadata",
            "--skip-archives",
            "--output-dir", tempDir.path,
        ])

        await #expect(throws: ExitCode.self) {
            try await cmd.run()
        }
    }

    @Test("--type package-docs no longer parses (#217 dropped the case)")
    func packageDocsRejected() {
        // ArgumentParser surfaces invalid enum values as ValidationError.
        #expect(throws: (any Error).self) {
            _ = try FetchCommand.parse(["--type", "package-docs"])
        }
    }
}

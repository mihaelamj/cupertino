import Foundation
import Testing

@testable import CLI
@testable import Shared

// MARK: - URL Construction

@Suite("PackagesSetupCommand URL construction")
struct PackagesSetupCommandURLTests {
    @Test("Release tag prepends v")
    func releaseTag() {
        #expect(PackagesSetupCommand.makeReleaseTag(version: "0.1.0") == "v0.1.0")
        #expect(PackagesSetupCommand.makeReleaseTag(version: "1.2.3") == "v1.2.3")
    }

    @Test("Zip filename follows cupertino-packages-v<version>.zip pattern")
    func zipFilename() {
        #expect(PackagesSetupCommand.makeZipFilename(version: "0.1.0") == "cupertino-packages-v0.1.0.zip")
        #expect(PackagesSetupCommand.makeZipFilename(version: "1.0.0") == "cupertino-packages-v1.0.0.zip")
    }

    @Test("Release URL uses default base URL from Shared constants")
    func releaseURLDefault() {
        let url = PackagesSetupCommand.makeReleaseURL(version: "0.1.0")
        #expect(url == "https://github.com/mihaelamj/cupertino-packages/releases/download/v0.1.0")
    }

    @Test("Release URL honors a custom base URL")
    func releaseURLCustom() {
        let url = PackagesSetupCommand.makeReleaseURL(
            version: "0.1.0",
            baseURL: "http://localhost:8080/releases"
        )
        #expect(url == "http://localhost:8080/releases/v0.1.0")
    }

    @Test("Download URL composes release URL and zip filename")
    func downloadURL() {
        let url = PackagesSetupCommand.makeDownloadURL(version: "0.1.0")
        #expect(
            url
                == "https://github.com/mihaelamj/cupertino-packages/releases/download/v0.1.0/cupertino-packages-v0.1.0.zip"
        )
    }

    @Test("Download URL with custom base URL keeps the same filename pattern")
    func downloadURLCustom() {
        let url = PackagesSetupCommand.makeDownloadURL(
            version: "1.0.0",
            baseURL: "http://localhost:8080/releases"
        )
        #expect(url == "http://localhost:8080/releases/v1.0.0/cupertino-packages-v1.0.0.zip")
    }

    @Test("Resolved version falls back to Shared.Constants.App.packagesIndexVersion when no override")
    func resolvedVersionDefault() throws {
        let cmd = try PackagesSetupCommand.parse([])
        #expect(cmd.resolvedVersion == Shared.Constants.App.packagesIndexVersion)
    }

    @Test("--release-version overrides the default version")
    func resolvedVersionOverride() throws {
        let cmd = try PackagesSetupCommand.parse(["--release-version", "9.9.9"])
        #expect(cmd.resolvedVersion == "9.9.9")
    }
}

// MARK: - Error Descriptions

@Suite("PackagesSetupError error messages")
struct PackagesSetupErrorTests {
    @Test("invalidURL description includes the offending URL")
    func invalidURLDescription() {
        let error = PackagesSetupError.invalidURL("not a url")
        #expect(error.errorDescription == "invalid URL: not a url")
    }

    @Test("httpStatus description includes the HTTP code")
    func httpStatusDescription() {
        let error = PackagesSetupError.httpStatus(500)
        #expect(error.errorDescription == "HTTP 500 while downloading the packages release")
    }

    @Test("httpNotFound description is the 404 message")
    func httpNotFoundDescription() {
        #expect(PackagesSetupError.httpNotFound.errorDescription == "release not found (HTTP 404)")
    }

    @Test("missingFile description includes the missing filename")
    func missingFileDescription() {
        let error = PackagesSetupError.missingFile("packages.db")
        #expect(error.errorDescription == "expected packages.db in the release archive but didn't find it")
    }

    @Test("extractionFailed description is the unzip failure message")
    func extractionFailedDescription() {
        #expect(PackagesSetupError.extractionFailed.errorDescription == "unzip failed")
    }
}

// MARK: - Integration

@Suite("PackagesSetupCommand integration")
struct PackagesSetupIntegrationTests {
    private static func tempBaseDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("packages-setup-test-\(UUID().uuidString)")
    }

    @Test("Short-circuits when packages.db already exists and --force not set")
    func alreadyInstalledShortCircuit() async throws {
        let baseDir = Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: baseDir) }

        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let packagesDB = baseDir.appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)
        let original = Data("fake db sentinel \(UUID().uuidString)".utf8)
        try original.write(to: packagesDB)

        var cmd = try PackagesSetupCommand.parse(["--base-dir", baseDir.path])
        try await cmd.run()

        let afterRun = try Data(contentsOf: packagesDB)
        #expect(afterRun == original, "existing packages.db should not be touched without --force")
    }

    @Test("404 path: bogus --release-version throws (real 404 against GitHub)")
    func bogusReleaseVersion404() async throws {
        let baseDir = Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: baseDir) }

        var cmd = try PackagesSetupCommand.parse([
            "--base-dir", baseDir.path,
            "--release-version", "9999.99.99-nonexistent",
        ])

        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }

        let packagesDB = baseDir.appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)
        #expect(
            !FileManager.default.fileExists(atPath: packagesDB.path),
            "no packages.db should be produced on 404"
        )
    }

    // NOTE: Happy-path download + extract test is parked until T1 of #192 section B
    // creates the `mihaelamj/cupertino-packages` repo with a real v0.1.0 release.
    // Once that exists, add a `happyPathDownload()` test here that asserts:
    //   - packages.db exists under baseDir
    //   - --force overwrites an existing packages.db
    //   - zip intermediate is cleaned up
}

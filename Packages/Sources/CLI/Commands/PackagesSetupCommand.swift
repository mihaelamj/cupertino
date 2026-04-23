import ArgumentParser
import Foundation
import Logging
import Shared

// MARK: - Packages Setup Command (hidden)

/// Downloads a pre-built `packages.db` from `mihaelamj/cupertino-packages` releases
/// and places it at `~/.cupertino/packages.db`. Analogous to `SetupCommand` but
/// scoped to the package index (not advertised in `--help`). See issue #187.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct PackagesSetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "packages-setup",
        abstract: "Download the pre-built packages.db from cupertino-packages releases",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Base directory for the packages database")
    var baseDir: String?

    @Flag(name: .long, help: "Force re-download even if packages.db already exists")
    var force: Bool = false

    @Option(
        name: .long,
        help: "Override the cupertino-packages release tag (defaults to packagesIndexVersion from Constants)"
    )
    var releaseVersion: String?

    // MARK: - Constants

    /// The release version to use, honoring `--release-version` first and falling back
    /// to the pinned `Shared.Constants.App.packagesIndexVersion`. Internal for tests.
    var resolvedVersion: String {
        releaseVersion ?? Shared.Constants.App.packagesIndexVersion
    }

    private var releaseTag: String {
        Self.makeReleaseTag(version: resolvedVersion)
    }

    private var zipFilename: String {
        Self.makeZipFilename(version: resolvedVersion)
    }

    private var releaseURL: String {
        Self.makeReleaseURL(version: resolvedVersion)
    }

    private var downloadURL: String {
        Self.makeDownloadURL(version: resolvedVersion)
    }

    // MARK: - URL helpers (internal for testability)

    static func makeReleaseTag(version: String) -> String {
        "v\(version)"
    }

    static func makeZipFilename(version: String) -> String {
        "cupertino-packages-\(makeReleaseTag(version: version)).zip"
    }

    static func makeReleaseURL(
        version: String,
        baseURL: String = Shared.Constants.App.packagesReleaseBaseURL
    ) -> String {
        "\(baseURL)/\(makeReleaseTag(version: version))"
    }

    static func makeDownloadURL(
        version: String,
        baseURL: String = Shared.Constants.App.packagesReleaseBaseURL
    ) -> String {
        "\(makeReleaseURL(version: version, baseURL: baseURL))/\(makeZipFilename(version: version))"
    }

    // MARK: - Run

    mutating func run() async throws {
        Logging.ConsoleLogger.info("📦 Cupertino Packages Setup\n")

        let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let packagesDBURL = baseURL.appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)

        if !force, FileManager.default.fileExists(atPath: packagesDBURL.path) {
            Logging.ConsoleLogger.info("✅ Packages database already exists")
            Logging.ConsoleLogger.info("   Packages: \(packagesDBURL.path)")
            Logging.ConsoleLogger.info("\n💡 Use --force to overwrite with the latest release")
            Logging.ConsoleLogger.info("💡 Search with: cupertino package-search \"<question>\"  (hidden)")
            return
        }

        if force, FileManager.default.fileExists(atPath: packagesDBURL.path) {
            Logging.ConsoleLogger.info("⚠️  Existing packages.db will be overwritten\n")
        }

        let zipURL = baseURL.appendingPathComponent(zipFilename)

        do {
            try await downloadFile(name: "Packages database", from: downloadURL, to: zipURL)
        } catch PackagesSetupError.httpNotFound {
            Logging.ConsoleLogger.error("❌ Release \(releaseTag) not found at \(Shared.Constants.App.packagesReleaseBaseURL).")
            Logging.ConsoleLogger.error("   Check available versions at https://github.com/mihaelamj/cupertino-packages/releases")
            throw ExitCode.failure
        }

        Logging.ConsoleLogger.info("📂 Extracting packages.db...")
        try await extractZip(at: zipURL, to: baseURL)

        try? FileManager.default.removeItem(at: zipURL)

        guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
            throw PackagesSetupError.missingFile(Shared.Constants.FileName.packagesIndexDatabase)
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Packages setup complete!")
        Logging.ConsoleLogger.info("   Packages: \(packagesDBURL.path)")
        Logging.ConsoleLogger.info("   Version:  \(resolvedVersion)")
    }

    // MARK: - Download + extract

    private func downloadFile(name: String, from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw PackagesSetupError.invalidURL(urlString)
        }

        Logging.ConsoleLogger.info("⬇️  Downloading \(name) from \(urlString)...")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 1200  // 20 min ceiling for the whole transfer

        let session = URLSession(configuration: config)
        let (tempURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw PackagesSetupError.httpNotFound
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PackagesSetupError.httpStatus(http.statusCode)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size]) as? Int64 ?? 0
        Logging.ConsoleLogger.info("   ✓ \(name) (\(Shared.Formatting.formatBytes(size)))")
    }

    private func extractZip(at zipURL: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PackagesSetupError.extractionFailed
        }
        Logging.ConsoleLogger.info("   ✓ Extracted")
    }
}

// MARK: - Errors

enum PackagesSetupError: Error, LocalizedError {
    case invalidURL(String)
    case httpStatus(Int)
    case httpNotFound
    case missingFile(String)
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "invalid URL: \(url)"
        case .httpStatus(let code): return "HTTP \(code) while downloading the packages release"
        case .httpNotFound: return "release not found (HTTP 404)"
        case .missingFile(let name): return "expected \(name) in the release archive but didn't find it"
        case .extractionFailed: return "unzip failed"
        }
    }
}

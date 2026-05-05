import ArgumentParser
import Foundation
import Shared

// MARK: - Database Release Command (search.db + samples.db + packages.db → cupertino-docs)

//
// Generic publishing primitives live in `ReleasePublishingHelpers.swift`.
// This file owns only what's specific to a database release: which files to
// bundle, which repo to push to, and the release-notes template.
//
// All three databases ship in a single zip and a single GitHub release on
// `mihaelamj/cupertino-docs`, so `cupertino setup` is one download.

struct DatabaseReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "databases",
        abstract: "Package and upload search.db + samples.db + packages.db to GitHub Releases (cupertino-docs)"
    )

    @Option(
        name: .long,
        help: "Directory containing search.db, samples.db, and packages.db. Defaults to ~/.cupertino/."
    )
    var baseDir: String?

    @Option(name: .long, help: "GitHub repository (owner/repo)")
    var repo: String = "mihaelamj/cupertino-docs"

    @Flag(name: .long, help: "Create release without uploading (dry run)")
    var dryRun: Bool = false

    @Option(name: .long, help: "Path to repository root")
    var repoRoot: String?

    @Flag(
        name: .long,
        help: """
        Allow publishing without packages.db. By default the command refuses if any of the three
        databases is missing — a partial release would silently ship a stale packages corpus.
        """
    )
    var allowMissingPackages: Bool = false

    private static let searchDBFilename = Shared.Constants.FileName.searchDatabase
    private static let samplesDBFilename = Shared.Constants.FileName.samplesDatabase
    private static let packagesDBFilename = Shared.Constants.FileName.packagesIndexDatabase

    mutating func run() async throws {
        let root = try ReleasePublishing.findRepoRoot(override: repoRoot)
        let version = try ReleasePublishing.readCurrentVersion(from: root)

        Console.info("📦 Database Release \(version.tag)\n")

        let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        // Resolve the three database paths. search.db and samples.db are
        // always required; packages.db is required by default but the
        // operator can opt in to a partial release with --allow-missing-packages.
        let searchDBURL = baseURL.appendingPathComponent(Self.searchDBFilename)
        let samplesDBURL = baseURL.appendingPathComponent(Self.samplesDBFilename)
        let packagesDBURL = baseURL.appendingPathComponent(Self.packagesDBFilename)

        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            throw ReleasePublishingError.missingDatabase(Self.searchDBFilename, baseURL.path)
        }
        guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
            throw ReleasePublishingError.missingDatabase(Self.samplesDBFilename, baseURL.path)
        }
        let packagesDBPresent = FileManager.default.fileExists(atPath: packagesDBURL.path)
        if !packagesDBPresent, !allowMissingPackages {
            throw ReleasePublishingError.missingDatabase(Self.packagesDBFilename, baseURL.path)
        }

        // Sizes (informational)
        let searchSize = try ReleasePublishing.fileSize(at: searchDBURL)
        let samplesSize = try ReleasePublishing.fileSize(at: samplesDBURL)
        let packagesSize = try packagesDBPresent ? (ReleasePublishing.fileSize(at: packagesDBURL)) : 0
        Console.info("📊 Database sizes:")
        Console.substep("search.db:   \(Shared.Formatting.formatBytes(searchSize))")
        Console.substep("samples.db:  \(Shared.Formatting.formatBytes(samplesSize))")
        if packagesDBPresent {
            Console.substep("packages.db: \(Shared.Formatting.formatBytes(packagesSize))")
        } else {
            Console.warning("packages.db: missing (continuing because --allow-missing-packages was passed)")
        }

        // Bundle. The zip name still uses the historical "cupertino-databases-"
        // prefix so existing `cupertino setup` clients keep working.
        var bundled: [URL] = [searchDBURL, samplesDBURL]
        if packagesDBPresent {
            bundled.append(packagesDBURL)
        }
        let zipFilename = "cupertino-databases-\(version.tag).zip"
        let zipURL = baseURL.appendingPathComponent(zipFilename)
        Console.info("\n📁 Creating \(zipFilename)...")
        try ReleasePublishing.createZip(containing: bundled, at: zipURL)

        let zipSize = try ReleasePublishing.fileSize(at: zipURL)
        Console.substep("✓ Created (\(Shared.Formatting.formatBytes(zipSize)))")

        Console.info("\n🔐 Calculating SHA256...")
        let sha256 = try ReleasePublishing.calculateSHA256(of: zipURL)
        Console.substep(sha256)

        if dryRun {
            Console.info("\n🏃 Dry run - skipping upload")
            Console.substep("Zip file: \(zipURL.path)")
            return
        }

        let token = try ReleasePublishing.resolveToken()

        Console.info("\n🔍 Checking for existing release...")
        let releaseExists = try await ReleasePublishing.checkReleaseExists(
            repo: repo, tag: version.tag, token: token
        )
        if releaseExists {
            Console.substep("Release \(version.tag) exists, updating...")
            try await ReleasePublishing.deleteRelease(repo: repo, tag: version.tag, token: token)
        }

        Console.info("\n🚀 Creating release \(version.tag)...")
        let bundledNames = bundled.map(\.lastPathComponent).joined(separator: ", ")
        let body = """
        Pre-built databases for instant Cupertino setup. Bundled: \(bundledNames).

        ## Quick Install

        ```bash
        cupertino setup
        ```

        ## SHA256

        ```
        \(sha256)  \(zipFilename)
        ```
        """
        let uploadURL = try await ReleasePublishing.createRelease(
            repo: repo,
            tag: version.tag,
            token: token,
            name: "Pre-built Databases \(version.tag) (\(bundledNames))",
            body: body
        )
        Console.substep("✓ Release created")

        Console.info("\n⬆️  Uploading \(zipFilename)...")
        try await ReleasePublishing.uploadAsset(
            uploadURL: uploadURL,
            file: zipURL,
            filename: zipFilename,
            token: token
        )
        Console.substep("✓ Upload complete")

        try? FileManager.default.removeItem(at: zipURL)

        Console.success("Release \(version.tag) published!")
        Console.info("   https://github.com/\(repo)/releases/tag/\(version.tag)")
    }
}

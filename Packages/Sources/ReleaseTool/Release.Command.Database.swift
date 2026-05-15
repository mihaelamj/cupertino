import ArgumentParser
import Foundation
import SharedConstants
// MARK: - Database Release Command (search.db + samples.db + packages.db → cupertino-docs)

//
// Generic publishing primitives live in `ReleasePublishingHelpers.swift`.
// This file owns only what's specific to a database release: which files to
// bundle, which repo to push to, and the release-notes template.
//
// All three databases ship in a single zip and a single GitHub release on
// `mihaelamj/cupertino-docs`, so `cupertino setup` is one download.

extension Release.Command {
    struct Database: AsyncParsableCommand {
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
            let root = try Release.Publishing.findRepoRoot(override: repoRoot)
            let version = try Release.Publishing.readCurrentVersion(from: root)

            Release.Console.info("📦 Database Release \(version.tag)\n")

            // Path-DI composition sub-root (#535): ReleaseTool is its own
            // executableTarget binary. The `--base-dir` flag is the canonical
            // way to point it at the release artifacts; if not passed, fall
            // back to a `Shared.Paths.live()` resolution like the other
            // binaries (CLI/TUI) so the same BinaryConfig.json next to the
            // executable routes the path.
            let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Paths.live().baseDirectory

            // Resolve the three database paths. search.db and samples.db are
            // always required; packages.db is required by default but the
            // operator can opt in to a partial release with --allow-missing-packages.
            let searchDBURL = baseURL.appendingPathComponent(Self.searchDBFilename)
            let samplesDBURL = baseURL.appendingPathComponent(Self.samplesDBFilename)
            let packagesDBURL = baseURL.appendingPathComponent(Self.packagesDBFilename)

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                throw Release.Publishing.Error.missingDatabase(Self.searchDBFilename, baseURL.path)
            }
            guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
                throw Release.Publishing.Error.missingDatabase(Self.samplesDBFilename, baseURL.path)
            }
            let packagesDBPresent = FileManager.default.fileExists(atPath: packagesDBURL.path)
            if !packagesDBPresent, !allowMissingPackages {
                throw Release.Publishing.Error.missingDatabase(Self.packagesDBFilename, baseURL.path)
            }

            // Sizes (informational)
            let searchSize = try Release.Publishing.fileSize(at: searchDBURL)
            let samplesSize = try Release.Publishing.fileSize(at: samplesDBURL)
            let packagesSize = try packagesDBPresent ? (Release.Publishing.fileSize(at: packagesDBURL)) : 0
            Release.Console.info("📊 Database sizes:")
            Release.Console.substep("search.db:   \(Shared.Utils.Formatting.formatBytes(searchSize))")
            Release.Console.substep("samples.db:  \(Shared.Utils.Formatting.formatBytes(samplesSize))")
            if packagesDBPresent {
                Release.Console.substep("packages.db: \(Shared.Utils.Formatting.formatBytes(packagesSize))")
            } else {
                Release.Console.warning("packages.db: missing (continuing because --allow-missing-packages was passed)")
            }

            // #236: checkpoint-truncate each DB before bundling so
            // any pages still in a `.db-wal` sidecar are folded into
            // the main file. Without this step a release zip would
            // ship a `.db` that's missing the most recent index
            // pages, and `cupertino setup` users would silently
            // search a stale corpus.
            Release.Console.info("\n💾 Checkpoint-truncating WAL sidecars before bundle...")
            for (label, url) in [
                ("search.db", searchDBURL),
                ("samples.db", samplesDBURL),
            ] + (packagesDBPresent ? [("packages.db", packagesDBURL)] : []) {
                let outcome = try Release.Publishing.checkpointTruncate(at: url)
                let detail = outcome.walFileExisted
                    ? "folded \(outcome.framesWritten)/\(outcome.framesTotal) frames"
                    : "no WAL sidecar"
                let busyNote = outcome.busy ? " ⚠ SQLITE_BUSY (was another process touching the DB?)" : ""
                Release.Console.substep("✓ \(label): \(detail)\(busyNote)")
            }

            // Bundle. The zip name still uses the historical "cupertino-databases-"
            // prefix so existing `cupertino setup` clients keep working.
            var bundled: [URL] = [searchDBURL, samplesDBURL]
            if packagesDBPresent {
                bundled.append(packagesDBURL)
            }
            let zipFilename = "cupertino-databases-\(version.tag).zip"
            let zipURL = baseURL.appendingPathComponent(zipFilename)
            Release.Console.info("\n📁 Creating \(zipFilename)...")
            try Release.Publishing.createZip(containing: bundled, at: zipURL)

            let zipSize = try Release.Publishing.fileSize(at: zipURL)
            Release.Console.substep("✓ Created (\(Shared.Utils.Formatting.formatBytes(zipSize)))")

            Release.Console.info("\n🔐 Calculating SHA256...")
            let sha256 = try Release.Publishing.calculateSHA256(of: zipURL)
            Release.Console.substep(sha256)

            if dryRun {
                Release.Console.info("\n🏃 Dry run - skipping upload")
                Release.Console.substep("Zip file: \(zipURL.path)")
                return
            }

            let token = try Release.Publishing.resolveToken()

            Release.Console.info("\n🔍 Checking for existing release...")
            let releaseExists = try await Release.Publishing.checkReleaseExists(
                repo: repo, tag: version.tag, token: token
            )
            if releaseExists {
                Release.Console.substep("Release \(version.tag) exists, updating...")
                try await Release.Publishing.deleteRelease(repo: repo, tag: version.tag, token: token)
            }

            Release.Console.info("\n🚀 Creating release \(version.tag)...")
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
            let uploadURL = try await Release.Publishing.createRelease(
                repo: repo,
                tag: version.tag,
                token: token,
                name: "Pre-built Databases \(version.tag) (\(bundledNames))",
                body: body
            )
            Release.Console.substep("✓ Release created")

            Release.Console.info("\n⬆️  Uploading \(zipFilename)...")
            try await Release.Publishing.uploadAsset(
                uploadURL: uploadURL,
                file: zipURL,
                filename: zipFilename,
                token: token
            )
            Release.Console.substep("✓ Upload complete")

            try? FileManager.default.removeItem(at: zipURL)

            Release.Console.success("Release \(version.tag) published!")
            Release.Console.info("   https://github.com/\(repo)/releases/tag/\(version.tag)")
        }
    }
}

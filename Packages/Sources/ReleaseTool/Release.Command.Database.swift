import ArgumentParser
import CupertinoComposition
import Foundation
import SearchModels
import SharedConstants

// MARK: - Database Release Command (per-source DBs → cupertino-docs)

//
// Generic publishing primitives live in `ReleasePublishingHelpers.swift`.
// This file owns only what's specific to a database release: which files to
// bundle, which repo to push to, and the release-notes template.
//
// The bundled database set is NOT hardcoded. It is derived from the
// production source registry, exactly the manifest `cupertino setup`
// reconstructs via `CLIImpl.bundleRequiredDescriptors()`:
//
//     CupertinoComposition.makeProductionSourceRegistry()
//         .allEnabled.map(\.destinationDB)
//
// Each enabled source declares its own `destinationDB`
// (`Shared.Models.DatabaseDescriptor`); the bundle ships one
// zip-extractable SQLite file per declared destination, deduped by
// filename (today 1:1 source→DB, but co-location is permitted). Adding a
// new source (one `<X>Source.swift` + one `.register(<X>Source())` line in
// the composition root) automatically extends this bundle, no edit to
// this file. A legacy DB sitting in the base directory with no enabled
// source backing it (e.g. a stray pre-split `search.db`) is therefore
// never bundled.
//
// All databases ship in a single zip and a single GitHub release on
// `mihaelamj/cupertino-docs`, so `cupertino setup` is one download.

extension Release.Command {
    struct Database: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "databases",
            abstract: "Package and upload the per-source databases to GitHub Releases (cupertino-docs)"
        )

        @Option(
            name: .long,
            help: "Directory containing the per-source databases. Defaults to ~/.cupertino/."
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
            Allow publishing even when some derived databases are missing from the base directory. By
            default the command refuses if any registry-declared database is absent, because a partial release
            would silently ship an incomplete corpus.
            """
        )
        var allowMissing: Bool = false

        /// The ordered, deduped list of database descriptors the bundle
        /// must ship, derived from the production source registry, not a
        /// hardcoded filename list. Each enabled source declares its own
        /// `destinationDB`; co-located sources sharing a filename collapse
        /// to one entry (stable first-seen order preserved).
        ///
        /// This is the identical mechanism `cupertino setup` uses to know
        /// which extracted files to expect (`CLIImpl.bundleRequiredDescriptors()`),
        /// so the release bundle and the setup verifier can never drift.
        static func bundledDescriptors() -> [Shared.Models.DatabaseDescriptor] {
            let derived = CupertinoComposition.makeProductionSourceRegistry()
                .allEnabled
                .map(\.destinationDB)
            var seen = Set<String>()
            var deduped: [Shared.Models.DatabaseDescriptor] = []
            for descriptor in derived where seen.insert(descriptor.filename).inserted {
                deduped.append(descriptor)
            }
            return deduped
        }

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

            // Resolve each registry-derived database path. By default every
            // declared database is required; `--allow-missing` downgrades an
            // absent file to a warning and drops it from the bundle.
            let descriptors = Self.bundledDescriptors()
            var present: [(filename: String, url: URL)] = []
            var missing: [String] = []
            for descriptor in descriptors {
                let url = baseURL.appendingPathComponent(descriptor.filename)
                if FileManager.default.fileExists(atPath: url.path) {
                    present.append((descriptor.filename, url))
                } else {
                    missing.append(descriptor.filename)
                }
            }

            if !missing.isEmpty, !allowMissing {
                throw Release.Publishing.Error.missingDatabase(missing.joined(separator: ", "), baseURL.path)
            }

            // Sizes (informational)
            Release.Console.info("📊 Database sizes:")
            for entry in present {
                let size = try Release.Publishing.fileSize(at: entry.url)
                Release.Console.substep("\(entry.filename): \(Shared.Utils.Formatting.formatBytes(size))")
            }
            for filename in missing {
                Release.Console.warning("\(filename): missing (continuing because --allow-missing was passed)")
            }

            // #236: checkpoint-truncate each DB before bundling so
            // any pages still in a `.db-wal` sidecar are folded into
            // the main file. Without this step a release zip would
            // ship a `.db` that's missing the most recent index
            // pages, and `cupertino setup` users would silently
            // search a stale corpus.
            Release.Console.info("\n💾 Checkpoint-truncating WAL sidecars before bundle...")
            for entry in present {
                let outcome = try Release.Publishing.checkpointTruncate(at: entry.url)
                let detail = outcome.walFileExisted
                    ? "folded \(outcome.framesWritten)/\(outcome.framesTotal) frames"
                    : "no WAL sidecar"
                let busyNote = outcome.busy ? " ⚠ SQLITE_BUSY (was another process touching the DB?)" : ""
                Release.Console.substep("✓ \(entry.filename): \(detail)\(busyNote)")
            }

            // Bundle. The zip name still uses the historical "cupertino-databases-"
            // prefix so existing `cupertino setup` clients keep working.
            let bundled = present.map(\.url)
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
                name: "Pre-built Databases \(version.tag)",
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

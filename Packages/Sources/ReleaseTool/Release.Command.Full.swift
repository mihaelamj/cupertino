import ArgumentParser
import Foundation

// MARK: - Full Command

extension Release.Command {
    struct Full: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "full",
            abstract: "Run the complete release workflow"
        )

        @Argument(help: "New version (e.g., 0.5.0) or bump type (major, minor, patch)")
        var versionOrType: String

        @Flag(name: .long, help: "Preview all steps without executing")
        var dryRun: Bool = false

        @Flag(name: .long, help: "Skip waiting for GitHub Actions")
        var skipWait: Bool = false

        @Flag(name: .long, help: "Skip database upload")
        var skipDatabases: Bool = false

        @Flag(name: .long, help: "Skip Homebrew formula update")
        var skipHomebrew: Bool = false

        @Option(name: .long, help: "Path to repository root")
        var repoRoot: String?

        // MARK: - Run

        mutating func run() async throws {
            let root = try findRepoRoot()
            let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants/Shared.Constants.swift")

            // Get current version
            let currentVersion = try readCurrentVersion(from: constantsPath)

            // Determine new version
            let newVersion: Release.Version
            if let bumpType = Release.Version.BumpType(rawValue: versionOrType.lowercased()) {
                newVersion = currentVersion.bumped(bumpType)
            } else if let explicit = Release.Version(versionOrType) {
                newVersion = explicit
            } else {
                throw FullReleaseError.invalidVersion(versionOrType)
            }

            Release.Console.info("🚀 Cupertino Release Workflow")
            Release.Console.info("   Current: \(currentVersion) → New: \(newVersion)")
            Release.Console.info("")

            if dryRun {
                Release.Console.warning("DRY RUN - No changes will be made\n")
            }

            // Step 1: Bump version
            Release.Console.step(1, "Bump version in all files")
            var bumpCmd = Release.Command.Bump()
            bumpCmd.versionOrType = newVersion.description
            bumpCmd.dryRun = dryRun
            bumpCmd.repoRoot = root.path
            try await bumpCmd.run()

            // Step 2: Edit changelog (prompt user)
            Release.Console.step(2, "Edit CHANGELOG.md")
            if !dryRun {
                Release.Console.info("    Please edit CHANGELOG.md to add release notes.")
                Release.Console.info("    Press Enter when done...")
                _ = readLine()
            } else {
                Release.Console.substep("Would prompt user to edit CHANGELOG.md")
            }

            // Step 3: Create tag and push
            Release.Console.step(3, "Create git tag and push")
            var tagCmd = Release.Command.Tag()
            tagCmd.version = newVersion.description
            tagCmd.dryRun = dryRun
            tagCmd.push = true
            tagCmd.repoRoot = root.path
            try await tagCmd.run()

            // Step 4: Wait for GitHub Actions
            if !skipWait {
                Release.Console.step(4, "Wait for GitHub Actions build")
                if dryRun {
                    Release.Console.substep("Would wait for GitHub Actions to complete")
                } else {
                    try await waitForGitHubActions(version: newVersion)
                }
            } else {
                Release.Console.step(4, "Skipping GitHub Actions wait (--skip-wait)")
            }

            // Step 5: Upload databases
            if !skipDatabases {
                Release.Console.step(5, "Upload databases to cupertino-docs")
                var dbCmd = Release.Command.Database()
                dbCmd.dryRun = dryRun
                dbCmd.repoRoot = root.path
                try await dbCmd.run()
            } else {
                Release.Console.step(5, "Skipping database upload (--skip-databases)")
            }

            // Step 6: Update Homebrew
            if !skipHomebrew {
                Release.Console.step(6, "Update Homebrew formula")
                var brewCmd = Release.Command.Homebrew()
                brewCmd.version = newVersion.description
                brewCmd.dryRun = dryRun
                brewCmd.repoRoot = root.path
                try await brewCmd.run()
            } else {
                Release.Console.step(6, "Skipping Homebrew update (--skip-homebrew)")
            }

            // Done
            Release.Console.info("")
            Release.Console.success("Release \(newVersion) complete!")
            Release.Console.info("")
            Release.Console.info("Verify:")
            Release.Console.info("  • GitHub Release: https://github.com/mihaelamj/cupertino/releases/tag/\(newVersion.tag)")
            Release.Console.info("  • Databases: https://github.com/mihaelamj/cupertino-docs/releases/tag/\(newVersion.tag)")
            Release.Console.info("  • Homebrew: brew info cupertino")
        }

        // MARK: - Helpers

        private func findRepoRoot() throws -> URL {
            if let root = repoRoot {
                return URL(fileURLWithPath: root)
            }
            let output = try Release.Shell.run("git rev-parse --show-toplevel")
            return URL(fileURLWithPath: output)
        }

        private func readCurrentVersion(from url: URL) throws -> Release.Version {
            let content = try String(contentsOf: url, encoding: .utf8)
            let pattern = #"public\s+static\s+let\s+version\s*=\s*"(\d+\.\d+\.\d+)""#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let versionRange = Range(match.range(at: 1), in: content),
                  let version = Release.Version(String(content[versionRange])) else {
                throw FullReleaseError.versionNotFound
            }
            return version
        }

        private func waitForGitHubActions(version: Release.Version) async throws {
            Release.Console.substep("Waiting for GitHub Actions to build \(version.tag)...")

            let maxAttempts = 60 // 30 minutes max
            let delaySeconds: UInt64 = 30

            for attempt in 1...maxAttempts {
                // Check if release asset exists
                let assetURL = URL.knownGood(
                    "https://github.com/mihaelamj/cupertino/releases/download/\(version.tag)/cupertino-\(version.tag)-macos-universal.tar.gz"
                )

                var request = URLRequest(url: assetURL)
                request.httpMethod = "HEAD"

                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    Release.Console.substep("✓ Build complete!")
                    return
                }

                if attempt < maxAttempts {
                    Release.Console.substep("Attempt \(attempt)/\(maxAttempts) - build not ready, waiting 30s...")
                    try await Task.sleep(nanoseconds: delaySeconds * 1000000000)
                }
            }

            throw FullReleaseError.buildTimeout
        }
    }
}

// MARK: - Errors

enum FullReleaseError: Error, CustomStringConvertible {
    case invalidVersion(String)
    case versionNotFound
    case buildTimeout

    var description: String {
        switch self {
        case .invalidVersion(let version):
            return "Invalid version: '\(version)'. Expected X.Y.Z or bump type (major, minor, patch)"
        case .versionNotFound:
            return "Could not find version in Constants.swift"
        case .buildTimeout:
            return "Timed out waiting for GitHub Actions build. Check https://github.com/mihaelamj/cupertino/actions"
        }
    }
}

import ArgumentParser
import Foundation

// MARK: - Docs Update Command

extension Release.Command {
    struct DocsUpdate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "docs-update",
            abstract: "Update documentation databases and bump minor version",
            discussion: """
            Workflow for documentation-only updates (no code changes):
            1. Run 'cupertino save' to rebuild search index
            2. Query database for document/framework counts
            3. Update README.md with new counts
            4. Bump minor version (e.g., 0.4.0 → 0.5.0)
            5. Optionally continue with tag and database upload

            Use this after updating crawled documentation (fetch or manual copy).
            """
        )

        @Flag(name: .long, help: "Preview changes without executing")
        var dryRun: Bool = false

        @Flag(name: .long, help: "Skip running 'cupertino save'")
        var skipSave: Bool = false

        @Flag(name: .long, help: "Continue with tag and upload after bump")
        var release: Bool = false

        @Option(name: .long, help: "Path to repository root")
        var repoRoot: String?

        // MARK: - Run

        mutating func run() async throws {
            let root = try findRepoRoot()
            let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants.swift")
            let readmePath = root.appendingPathComponent("README.md")

            Release.Console.info("📚 Documentation Update Workflow")
            Release.Console.info("")

            if dryRun {
                Release.Console.warning("DRY RUN - No changes will be made\n")
            }

            // Step 1: Run cupertino save
            Release.Console.step(1, "Rebuild search index")
            if skipSave {
                Release.Console.substep("Skipping (--skip-save)")
            } else if dryRun {
                Release.Console.substep("Would run: cupertino save")
            } else {
                Release.Console.substep("Running 'cupertino save'...")
                try Release.Shell.runInteractive("cupertino save")
                Release.Console.substep("✓ Search index rebuilt")
            }

            // Step 2: Query database for counts
            Release.Console.step(2, "Query database statistics")
            let (docCount, frameworkCount) = try await getDocumentStats()
            Release.Console.substep("✓ Documents: \(formatNumber(docCount))")
            Release.Console.substep("✓ Frameworks: \(frameworkCount)")

            // Step 3: Update README.md
            Release.Console.step(3, "Update README.md with new counts")
            let statsMsg = "\(formatNumber(docCount))+ documentation pages across \(frameworkCount) frameworks"
            if dryRun {
                Release.Console.substep("Would update to: '\(statsMsg)'")
            } else {
                try updateReadmeStats(at: readmePath, documents: docCount, frameworks: frameworkCount)
                Release.Console.substep("✓ Updated to '\(statsMsg)'")
            }

            // Step 4: Bump minor version
            Release.Console.step(4, "Bump minor version")
            let currentVersion = try readCurrentVersion(from: constantsPath)
            let newVersion = currentVersion.bumped(.minor)
            Release.Console.substep("Release.Version: \(currentVersion) → \(newVersion)")

            var bumpCmd = Release.Command.Bump()
            bumpCmd.versionOrType = newVersion.description
            bumpCmd.dryRun = dryRun
            bumpCmd.repoRoot = root.path
            try await bumpCmd.run()

            // Step 5: Optionally continue with release
            if release {
                Release.Console.step(5, "Continue with tag and upload")

                if !dryRun {
                    Release.Console.info("\n    Please edit CHANGELOG.md to add release notes.")
                    Release.Console.info("    Press Enter when done...")
                    _ = readLine()
                }

                var tagCmd = Release.Command.Tag()
                tagCmd.version = newVersion.description
                tagCmd.dryRun = dryRun
                tagCmd.push = true
                tagCmd.repoRoot = root.path
                try await tagCmd.run()

                Release.Console.substep("Waiting for GitHub Actions...")
                if !dryRun {
                    Release.Console.info("\n    Wait for GitHub Actions to complete, then run:")
                    Release.Console.info("    cupertino-rel databases")
                    Release.Console.info("    cupertino-rel homebrew --version \(newVersion)")
                }
            } else {
                Release.Console.info("\nNext steps:")
                Release.Console.info("  1. Review changes: git diff")
                Release.Console.info("  2. Edit CHANGELOG.md")
                Release.Console.info("  3. Tag and release: cupertino-rel tag --version \(newVersion) --push")
                Release.Console.info("  4. After GitHub Actions: cupertino-rel databases")
                Release.Console.info("  5. Update Homebrew: cupertino-rel homebrew --version \(newVersion)")
            }

            Release.Console.info("")
            Release.Console.success("Documentation update prepared: \(formatNumber(docCount))+ docs, \(frameworkCount) frameworks")
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
                throw DocsUpdateError.versionNotFound
            }
            return version
        }

        private func getDocumentStats() async throws -> (documents: Int, frameworks: Int) {
            // Always query - we need the counts even in dry-run to show what would be written
            // Query using cupertino list-frameworks and parse output
            let output = try Release.Shell.run("cupertino list-frameworks 2>/dev/null || echo 'error'")

            if output.contains("error") || output.isEmpty {
                throw DocsUpdateError.databaseQueryFailed
            }

            // Parse output like:
            // Available Frameworks (284 total, 200725 documents):

            var totalDocs = 0
            var frameworkCount = 0

            // Look for "Available Frameworks (X total, Y documents):"
            let pattern = #"\((\d+)\s+total,\s+(\d+)\s+documents\)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                if let fwRange = Range(match.range(at: 1), in: output),
                   let docRange = Range(match.range(at: 2), in: output) {
                    frameworkCount = Int(output[fwRange]) ?? 0
                    totalDocs = Int(output[docRange]) ?? 0
                }
            }

            if totalDocs == 0 {
                throw DocsUpdateError.databaseQueryFailed
            }

            return (totalDocs, frameworkCount)
        }

        private func updateReadmeStats(at url: URL, documents: Int, frameworks: Int) throws {
            var content = try String(contentsOf: url, encoding: .utf8)

            // Update pattern: "X+ documentation pages across Y frameworks"
            // or "X,XXX+ documentation pages across Y frameworks"
            let pattern = #"(\d+[,\d]*\+?\s+documentation pages across\s+)\d+(\s+frameworks)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw DocsUpdateError.readmeUpdateFailed
            }

            let formattedDocs = formatNumber(documents)
            let replacement = "\(formattedDocs)+ documentation pages across \(frameworks) frameworks"

            // Find and replace the pattern
            if let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range, in: content) {
                content.replaceSubrange(range, with: replacement)
            } else {
                throw DocsUpdateError.readmeUpdateFailed
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        private func formatNumber(_ number: Int) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
        }
    }
}

// MARK: - Errors

enum DocsUpdateError: Error, CustomStringConvertible {
    case versionNotFound
    case databaseQueryFailed
    case readmeUpdateFailed

    var description: String {
        switch self {
        case .versionNotFound:
            return "Could not find version in Constants.swift"
        case .databaseQueryFailed:
            return "Failed to query database. Make sure 'cupertino list-frameworks' works."
        case .readmeUpdateFailed:
            return "Failed to update README.md - pattern not found"
        }
    }
}

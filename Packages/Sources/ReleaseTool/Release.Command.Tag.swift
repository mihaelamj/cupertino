import ArgumentParser
import Foundation

// MARK: - Tag Command

extension Release.Command {
    struct Tag: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tag",
            abstract: "Commit changes and create git tag"
        )

        @Option(name: .long, help: "Release.Version to tag (e.g., 0.5.0)")
        var version: String?

        @Flag(name: .long, help: "Preview commands without executing")
        var dryRun: Bool = false

        @Flag(name: .long, help: "Push tag to origin after creation")
        var push: Bool = false

        @Option(name: .long, help: "Path to repository root")
        var repoRoot: String?

        // MARK: - Run

        mutating func run() async throws {
            let root = try findRepoRoot()
            let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants/Shared.Constants.swift")

            // Get version from Constants.swift or argument
            let tagVersion: Release.Version
            if let versionString = version {
                guard let parsed = Release.Version(versionString) else {
                    throw TagError.invalidVersion(versionString)
                }
                tagVersion = parsed
            } else {
                tagVersion = try readCurrentVersion(from: constantsPath)
            }

            Release.Console.info("📦 Tagging version: \(tagVersion)")

            // Check for uncommitted changes
            let status = try Release.Shell.run("git status --porcelain")
            let hasChanges = !status.isEmpty

            if hasChanges {
                Release.Console.step(1, "Staging and committing changes...")
                if dryRun {
                    Release.Console.substep("Would run: git add -A")
                    Release.Console.substep("Would run: git commit -m \"chore: bump version to \(tagVersion)\"")
                } else {
                    try Release.Shell.run("git add -A")
                    try Release.Shell.run("git commit -m \"chore: bump version to \(tagVersion)\"")
                    Release.Console.substep("✓ Changes committed")
                }
            } else {
                Release.Console.step(1, "No uncommitted changes")
            }

            // Verify version in committed code matches
            Release.Console.step(2, "Verifying version in source...")
            if dryRun {
                Release.Console.substep("Would verify version matches \(tagVersion)")
            } else {
                let committedVersion = try readCurrentVersion(from: constantsPath)
                guard committedVersion.description == tagVersion.description else {
                    throw TagError.versionMismatch(expected: tagVersion.description, found: committedVersion.description)
                }
                Release.Console.substep("✓ Release.Version verified: \(committedVersion)")
            }

            // Create tag
            Release.Console.step(3, "Creating tag \(tagVersion.tag)...")
            if dryRun {
                Release.Console.substep("Would run: git tag -a \(tagVersion.tag) -m \"\(tagVersion.tag)\"")
            } else {
                // Check if tag exists
                let tagExists = (try? Release.Shell.run("git rev-parse \(tagVersion.tag)")) != nil
                if tagExists {
                    throw TagError.tagExists(tagVersion.tag)
                }

                try Release.Shell.run("git tag -a \(tagVersion.tag) -m \"\(tagVersion.tag)\"")
                Release.Console.substep("✓ Tag created")
            }

            // Push if requested
            if push {
                Release.Console.step(4, "Pushing to origin...")
                if dryRun {
                    Release.Console.substep("Would run: git push origin main")
                    Release.Console.substep("Would run: git push origin \(tagVersion.tag)")
                } else {
                    try Release.Shell.run("git push origin main")
                    Release.Console.substep("✓ Pushed main branch")
                    try Release.Shell.run("git push origin \(tagVersion.tag)")
                    Release.Console.substep("✓ Pushed tag \(tagVersion.tag)")
                }
            }

            Release.Console.success("Tag \(tagVersion.tag) created")

            if !push {
                Release.Console.info("\nTo push:")
                Release.Console.info("  git push origin main && git push origin \(tagVersion.tag)")
            }

            Release.Console.info("\nNext steps:")
            Release.Console.info("  1. Wait for GitHub Actions to build the CLI binary")
            Release.Console.info("  2. Run: cupertino-rel homebrew --version \(tagVersion)")
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
                throw TagError.versionNotFound
            }
            return version
        }
    }
}

// MARK: - Errors

enum TagError: Error, CustomStringConvertible {
    case invalidVersion(String)
    case versionNotFound
    case versionMismatch(expected: String, found: String)
    case tagExists(String)

    var description: String {
        switch self {
        case .invalidVersion(let version):
            return "Invalid version: \(version)"
        case .versionNotFound:
            return "Could not find version in Constants.swift"
        case .versionMismatch(let expected, let found):
            return "Release.Version mismatch: expected \(expected), found \(found) in Constants.swift"
        case .tagExists(let tag):
            return "Tag \(tag) already exists. Delete it first: git tag -d \(tag)"
        }
    }
}

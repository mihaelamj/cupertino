import ArgumentParser
import Foundation

// MARK: - Bump Command

extension Release.Command {
    struct Bump: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bump",
            abstract: "Bump version in all required files"
        )

        @Argument(help: "New version (e.g., 0.5.0) or bump type (major, minor, patch)")
        var versionOrType: String

        @Flag(name: .long, help: "Preview changes without modifying files")
        var dryRun: Bool = false

        @Option(name: .long, help: "Path to repository root")
        var repoRoot: String?

        // MARK: - File Paths

        private struct FilePaths {
            let constants: URL
            let readme: URL
            let changelog: URL
            let deployment: URL

            init(root: URL) {
                constants = root.appendingPathComponent("Packages/Sources/Shared/Constants.swift")
                readme = root.appendingPathComponent("README.md")
                changelog = root.appendingPathComponent("CHANGELOG.md")
                deployment = root.appendingPathComponent("docs/DEPLOYMENT.md")
            }
        }

        private func filePaths(root: URL) -> FilePaths {
            FilePaths(root: root)
        }

        // MARK: - Run

        mutating func run() async throws {
            let root = try findRepoRoot()
            let paths = filePaths(root: root)

            // Get current version
            let currentVersion = try readCurrentVersion(from: paths.constants)
            Console.info("📦 Current version: \(currentVersion)")

            // Determine new version
            let newVersion: Version
            if let bumpType = BumpType(rawValue: versionOrType.lowercased()) {
                newVersion = currentVersion.bumped(bumpType)
            } else if let explicit = Version(versionOrType) {
                newVersion = explicit
            } else {
                throw BumpError.invalidVersion(versionOrType)
            }

            Console.info("🎯 New version: \(newVersion)")

            if dryRun {
                Console.info("\n🏃 Dry run - would update:")
                Console.substep("Constants.swift: \(currentVersion) → \(newVersion)")
                Console.substep("README.md: Version badge")
                Console.substep("CHANGELOG.md: Add \(newVersion) section")
                Console.substep("DEPLOYMENT.md: Version header")
                return
            }

            // Update files
            Console.step(1, "Updating Constants.swift...")
            try updateConstants(at: paths.constants, to: newVersion)
            Console.substep("✓ Updated version = \"\(newVersion)\"")

            Console.step(2, "Updating README.md...")
            try updateReadme(at: paths.readme, to: newVersion)
            Console.substep("✓ Updated Version: \(newVersion)")

            Console.step(3, "Updating CHANGELOG.md...")
            try updateChangelog(at: paths.changelog, version: newVersion)
            Console.substep("✓ Added ## \(newVersion) section")

            Console.step(4, "Updating DEPLOYMENT.md...")
            try updateDeployment(at: paths.deployment, to: newVersion)
            Console.substep("✓ Updated Version: \(newVersion)")

            Console.success("Version bumped to \(newVersion)")
            Console.info("\nNext steps:")
            Console.info("  1. Edit CHANGELOG.md to add release notes")
            Console.info("  2. Run: cupertino-rel tag --version \(newVersion)")
        }

        // MARK: - Find Repo Root

        private func findRepoRoot() throws -> URL {
            if let root = repoRoot {
                return URL(fileURLWithPath: root)
            }

            // Try to find git root
            let output = try Shell.run("git rev-parse --show-toplevel")
            return URL(fileURLWithPath: output)
        }

        // MARK: - Read Current Version

        private func readCurrentVersion(from url: URL) throws -> Version {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Match: public static let version = "X.Y.Z"
            let pattern = #"public\s+static\s+let\s+version\s*=\s*"(\d+\.\d+\.\d+)""#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let versionRange = Range(match.range(at: 1), in: content) else {
                throw BumpError.versionNotFound(url.path)
            }

            guard let version = Version(String(content[versionRange])) else {
                throw BumpError.invalidVersion(String(content[versionRange]))
            }

            return version
        }

        // MARK: - Update Constants.swift

        private func updateConstants(at url: URL, to version: Version) throws {
            var content = try String(contentsOf: url, encoding: .utf8)

            let pattern = #"(public\s+static\s+let\s+version\s*=\s*")(\d+\.\d+\.\d+)(")"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw BumpError.updateFailed(url.path)
            }

            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(version)$3"
            )

            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        // MARK: - Update README.md

        private func updateReadme(at url: URL, to version: Version) throws {
            var content = try String(contentsOf: url, encoding: .utf8)

            // Update **Version:** X.Y.Z
            let pattern = #"(\*\*Version:\*\*\s*)\d+\.\d+\.\d+"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw BumpError.updateFailed(url.path)
            }

            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(version)"
            )

            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        // MARK: - Update CHANGELOG.md

        private func updateChangelog(at url: URL, version: Version) throws {
            var content = try String(contentsOf: url, encoding: .utf8)

            // Find first ## heading (existing version) and insert new section before it
            let today = ISO8601DateFormatter.string(
                from: Date(),
                timeZone: .current,
                formatOptions: [.withFullDate, .withDashSeparatorInDate]
            )

            let newSection = """
            ## \(version) (\(today))

            ### Added
            -

            ### Changed
            -

            ### Fixed
            -

            """

            // Insert after # Changelog header
            if let range = content.range(of: "\n## ") {
                content.insert(contentsOf: "\n\(newSection)", at: range.lowerBound)
            } else if let range = content.range(of: "# Changelog\n") {
                content.insert(contentsOf: "\n\(newSection)", at: range.upperBound)
            } else {
                // Prepend if no existing structure
                content = "# Changelog\n\n\(newSection)\n\(content)"
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        // MARK: - Update DEPLOYMENT.md

        private func updateDeployment(at url: URL, to version: Version) throws {
            var content = try String(contentsOf: url, encoding: .utf8)

            // Update **Version:** X.Y.Z
            let pattern = #"(\*\*Version:\*\*\s*)\d+\.\d+\.\d+"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw BumpError.updateFailed(url.path)
            }

            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(version)"
            )

            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Errors

enum BumpError: Error, CustomStringConvertible {
    case invalidVersion(String)
    case versionNotFound(String)
    case updateFailed(String)

    var description: String {
        switch self {
        case .invalidVersion(let version):
            return "Invalid version format: '\(version)'. Expected X.Y.Z or bump type (major, minor, patch)"
        case .versionNotFound(let path):
            return "Could not find version in \(path)"
        case .updateFailed(let path):
            return "Failed to update \(path)"
        }
    }
}

import ArgumentParser
import Foundation

// MARK: - Homebrew Command

struct HomebrewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "homebrew",
        abstract: "Update Homebrew formula with new version"
    )

    @Option(name: .long, help: "Version to release (e.g., 0.5.0)")
    var version: String?

    @Flag(name: .long, help: "Preview changes without modifying files")
    var dryRun: Bool = false

    @Option(name: .long, help: "Path to homebrew-tap repository")
    var tapPath: String?

    @Option(name: .long, help: "GitHub repository for CLI releases")
    var repo: String = "mihaelamj/cupertino"

    @Option(name: .long, help: "Path to repository root")
    var repoRoot: String?

    // MARK: - Run

    mutating func run() async throws {
        let root = try findRepoRoot()

        // Get version
        let releaseVersion: Version
        if let versionString = version {
            guard let parsed = Version(versionString) else {
                throw HomebrewError.invalidVersion(versionString)
            }
            releaseVersion = parsed
        } else {
            releaseVersion = try readCurrentVersion(from: root)
        }

        Console.info("🍺 Updating Homebrew formula for version \(releaseVersion)")

        // Get SHA256 from GitHub release
        Console.step(1, "Fetching SHA256 from GitHub release...")
        let sha256 = try await fetchSHA256(version: releaseVersion)
        Console.substep("SHA256: \(sha256)")

        // Clone or update tap repository
        let tapURL: URL
        if let path = tapPath {
            tapURL = URL(fileURLWithPath: path)
        } else {
            Console.step(2, "Cloning homebrew-tap repository...")
            tapURL = try cloneTap()
        }

        let formulaPath = tapURL.appendingPathComponent("Formula/cupertino.rb")

        // Update formula
        Console.step(3, "Updating formula...")
        if dryRun {
            Console.substep("Would update: \(formulaPath.path)")
            Console.substep("  url → .../\(releaseVersion.tag)/cupertino-\(releaseVersion.tag)-macos-universal.tar.gz")
            Console.substep("  sha256 → \(sha256)")
            Console.substep("  version → \(releaseVersion)")
        } else {
            try updateFormula(at: formulaPath, version: releaseVersion, sha256: sha256)
            Console.substep("✓ Formula updated")
        }

        // Commit and push
        Console.step(4, "Committing changes...")
        if dryRun {
            Console.substep("Would run: git add Formula/cupertino.rb")
            Console.substep("Would run: git commit -m \"chore: bump cupertino to \(releaseVersion)\"")
            Console.substep("Would run: git push")
        } else {
            let originalDir = FileManager.default.currentDirectoryPath
            FileManager.default.changeCurrentDirectoryPath(tapURL.path)

            try Shell.run("git add Formula/cupertino.rb")
            try Shell.run("git commit -m \"chore: bump cupertino to \(releaseVersion)\"")
            try Shell.run("git push")

            FileManager.default.changeCurrentDirectoryPath(originalDir)
            Console.substep("✓ Changes pushed to homebrew-tap")
        }

        // Cleanup temp directory if we cloned
        if tapPath == nil {
            try? FileManager.default.removeItem(at: tapURL)
        }

        Console.success("Homebrew formula updated to \(releaseVersion)")
        Console.info("\nUsers can now run:")
        Console.info("  brew update && brew upgrade cupertino")
    }

    // MARK: - Helpers

    private func findRepoRoot() throws -> URL {
        if let root = repoRoot {
            return URL(fileURLWithPath: root)
        }
        let output = try Shell.run("git rev-parse --show-toplevel")
        return URL(fileURLWithPath: output)
    }

    private func readCurrentVersion(from root: URL) throws -> Version {
        let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants.swift")
        let content = try String(contentsOf: constantsPath, encoding: .utf8)
        let pattern = #"public\s+static\s+let\s+version\s*=\s*"(\d+\.\d+\.\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let versionRange = Range(match.range(at: 1), in: content),
              let version = Version(String(content[versionRange])) else {
            throw HomebrewError.versionNotFound
        }
        return version
    }

    private func fetchSHA256(version: Version) async throws -> String {
        let sha256URL = URL.knownGood(
            "https://github.com/\(repo)/releases/download/\(version.tag)/cupertino-\(version.tag)-macos-universal.tar.gz.sha256"
        )

        let (data, response) = try await URLSession.shared.data(from: sha256URL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HomebrewError.sha256NotFound(version.tag)
        }

        guard let content = String(data: data, encoding: .utf8),
              let sha256 = content.split(separator: " ").first else {
            throw HomebrewError.invalidSHA256
        }

        return String(sha256).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cloneTap() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("homebrew-tap-\(UUID().uuidString)")
        try Shell.run("git clone https://github.com/mihaelamj/homebrew-tap.git \(tempDir.path)")
        return tempDir
    }

    private func updateFormula(at url: URL, version: Version, sha256: String) throws {
        var content = try String(contentsOf: url, encoding: .utf8)

        // Update URL
        let urlPattern = #"(url\s+")https://github\.com/[^"]+/releases/download/v[\d.]+/"#
            + #"cupertino-v[\d.]+-macos-universal\.tar\.gz(")"#
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let newURL = "https://github.com/\(repo)/releases/download/\(version.tag)/"
                + "cupertino-\(version.tag)-macos-universal.tar.gz"
            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(newURL)$2"
            )
        }

        // Update SHA256
        let sha256Pattern = #"(sha256\s+")[a-f0-9]+(")"#
        if let regex = try? NSRegularExpression(pattern: sha256Pattern) {
            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(sha256)$2"
            )
        }

        // Update version
        let versionPattern = #"(version\s+")[\d.]+(")"#
        if let regex = try? NSRegularExpression(pattern: versionPattern) {
            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(version)$2"
            )
        }

        // Update test assertion
        let testPattern = #"(assert_match\s+")[\d.]+(",)"#
        if let regex = try? NSRegularExpression(pattern: testPattern) {
            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(content.startIndex..., in: content),
                withTemplate: "$1\(version)$2"
            )
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

enum HomebrewError: Error, CustomStringConvertible {
    case invalidVersion(String)
    case versionNotFound
    case sha256NotFound(String)
    case invalidSHA256

    var description: String {
        switch self {
        case .invalidVersion(let version):
            return "Invalid version: \(version)"
        case .versionNotFound:
            return "Could not find version in Constants.swift"
        case .sha256NotFound(let tag):
            return "SHA256 file not found for release \(tag). Is the GitHub Actions build complete?"
        case .invalidSHA256:
            return "Could not parse SHA256 from release"
        }
    }
}

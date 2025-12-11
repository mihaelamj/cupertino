import ArgumentParser
import Foundation
import Shared

// MARK: - Release CLI

@main
struct ReleaseCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cupertino-rel",
        abstract: "Automate the Cupertino CLI release process",
        discussion: """
        Automates the full release workflow:
        1. Update version in Constants.swift, README.md, CHANGELOG.md
        2. Commit version bump
        3. Create and push git tag
        4. Wait for GitHub Actions to build
        5. Upload databases via cupertino release
        6. Update Homebrew formula

        Requires GITHUB_TOKEN environment variable with repo scope.
        """,
        version: Shared.Constants.App.version,
        subcommands: [
            BumpCommand.self,
            TagCommand.self,
            DatabaseReleaseCommand.self,
            HomebrewCommand.self,
            DocsUpdateCommand.self,
            FullCommand.self,
        ],
        defaultSubcommand: FullCommand.self
    )
}

// MARK: - Shell Helpers

enum Shell {
    @discardableResult
    static func run(_ command: String, quiet: Bool = false) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw ShellError.commandFailed(command, output)
        }

        return output
    }

    static func runInteractive(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ShellError.commandFailed(command, "Process exited with code \(process.terminationStatus)")
        }
    }
}

enum ShellError: Error, CustomStringConvertible {
    case commandFailed(String, String)

    var description: String {
        switch self {
        case .commandFailed(let cmd, let output):
            return "Command failed: \(cmd)\n\(output)"
        }
    }
}

// MARK: - Version Helpers

struct Version: CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    var tag: String {
        "v\(description)"
    }

    init?(_ string: String) {
        let parts = string.replacingOccurrences(of: "v", with: "").split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    func bumped(_ type: BumpType) -> Version {
        switch type {
        case .major:
            return Version(major: major + 1, minor: 0, patch: 0)
        case .minor:
            return Version(major: major, minor: minor + 1, patch: 0)
        case .patch:
            return Version(major: major, minor: minor, patch: patch + 1)
        }
    }
}

enum BumpType: String, ExpressibleByArgument, CaseIterable {
    case major
    case minor
    case patch
}

// MARK: - Console Output

enum Console {
    static func info(_ message: String) {
        print(message)
    }

    static func success(_ message: String) {
        print("✅ \(message)")
    }

    static func warning(_ message: String) {
        print("⚠️  \(message)")
    }

    static func error(_ message: String) {
        print("❌ \(message)")
    }

    static func step(_ number: Int, _ message: String) {
        print("\n[\(number)] \(message)")
    }

    static func substep(_ message: String) {
        print("    \(message)")
    }
}

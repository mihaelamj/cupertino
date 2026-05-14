import ArgumentParser
import Foundation
import SharedConstants
import SharedCore

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
            Release.Command.Bump.self,
            Release.Command.Tag.self,
            Release.Command.Database.self,
            Release.Command.Homebrew.self,
            Release.Command.DocsUpdate.self,
            Release.Command.Full.self,
        ],
        defaultSubcommand: Release.Command.Full.self
    )
}

// Helpers moved to per-type files:
//   Release.Shell.swift            (was Shell)
//   Release.Shell.Error.swift      (was ShellError)
//   Release.Version.swift          (was Version)
//   Release.Version.BumpType.swift (was BumpType)
//   Release.Console.swift          (was Console)

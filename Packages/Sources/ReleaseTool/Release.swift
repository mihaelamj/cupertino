import ArgumentParser

// MARK: - Release Namespace

/// Namespace for the `cupertino-rel` binary (the release-automation tool).
/// Holds every subcommand under `Release.Command.<Name>`, mirroring the
/// `Command.<Name>` pattern used for the main `cupertino` CLI (#352).
///
/// The root `ReleaseCLI` (the `AsyncParsableCommand` that holds
/// `subcommands: [...]`) stays at file scope in `ReleaseCLI.swift` — it's
/// the dispatcher, not a subcommand. The helper enums
/// `Release.Publishing` and `Release.Publishing.Error` also stay where they
/// are for now (a follow-up may fold them into `Release.Publishing.*`).
enum Release {
    /// Sub-namespace for `AsyncParsableCommand` subcommands of `cupertino-rel`:
    /// `Release.Command.Bump`, `.Tag`, `.Database`, `.Homebrew`, `.DocsUpdate`,
    /// `.Full`.
    enum Command {}
}

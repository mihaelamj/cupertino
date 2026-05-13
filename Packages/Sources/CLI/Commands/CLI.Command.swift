import ArgumentParser

// MARK: - CLI.Command Namespace

/// Namespace for CLI subcommands. Each subcommand lives as
/// `CLI.Command.<Name>` and ships in its own
/// `CLI.Command.<Name>.swift` file under `Sources/CLI/Commands/`.
///
/// The root `AsyncParsableCommand` (entry point holding `subcommands:`) is
/// `Cupertino` in `Cupertino.swift` — it isn't a subcommand itself, it's the
/// dispatcher, so it sits at file scope rather than under `CLI.Command`.
///
/// `swift-argument-parser` conformance stays on the individual subcommand
/// structs; the namespace is purely an organising shell.
extension CLI {
    public enum Command {}
}

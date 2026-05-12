import ArgumentParser

// MARK: - Command Namespace

/// Namespace for every CLI subcommand. Each subcommand lives as
/// `Command.<Name>` (matching its `<Name>Command.swift` filename minus the
/// "Command" suffix), e.g. `Command.Cleanup`, `Command.Doctor`,
/// `Command.Search`. `swift-argument-parser` conformance stays on the
/// individual structs; the namespace is just an organising shell.
///
/// The root `AsyncParsableCommand` (the entry point that holds
/// `subcommands: [...]`) is `Cupertino` in `Cupertino.swift` — it doesn't
/// live under `Command` because it isn't a subcommand itself, it's the
/// dispatcher.
enum Command {}

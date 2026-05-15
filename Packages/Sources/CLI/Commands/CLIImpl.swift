import Foundation

// MARK: - CLI Namespace

/// Namespace for the CLI target. Hosts `CLIImpl.Command.<Name>` subcommand
/// structs (see `CLIImpl.Command.swift`). The root `AsyncParsableCommand`
/// (`Cupertino`) is the dispatcher and stays at file scope.
public enum CLIImpl {}

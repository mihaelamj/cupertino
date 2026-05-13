import Foundation

// MARK: - CLI Namespace

/// Namespace for the CLI target. Hosts `CLI.Command.<Name>` subcommand
/// structs (see `CLI.Command.swift`). The root `AsyncParsableCommand`
/// (`Cupertino`) is the dispatcher and stays at file scope.
public enum CLI {}

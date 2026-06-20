import Foundation
import SearchModels
import SharedConstants

// MARK: - Serve startup database-health banner (#1162)

extension CLIImpl {
    /// Build the per-source database-health banner that `cupertino serve`
    /// prints to **stderr** on startup.
    ///
    /// #1162: the actionable "run `cupertino setup`" diagnostics used to go
    /// only through the `Recording` abstraction with the console sink
    /// disabled (to keep stdout a clean JSON-RPC channel), so they landed
    /// only in the unified log under `com.cupertino.cli` / `mcp` — a channel
    /// the operator has no reason to watch. Meanwhile the MCP request/response
    /// and lifecycle lines go straight to stderr, which is the operator's
    /// server-output panel. The net effect was that search silently did
    /// nothing and the one message explaining why was invisible.
    ///
    /// stderr is safe to write: stdout is the protocol channel, not stderr
    /// (the getting-started guide and the server's own lifecycle lines
    /// already use stderr). This is a startup summary, not per-request noise.
    ///
    /// Pure function (no I/O) so it is unit-testable; `serve` writes the
    /// returned lines to stderr.
    ///
    /// - Parameters:
    ///   - inventory: the registry-derived active-source inventory
    ///     (`CLIImpl.activeSourceInventory()`): one row per per-source DB
    ///     with on-disk presence and schema version.
    ///   - searchIndexDisabledReason: the reason the primary search index
    ///     failed to open (schema mismatch, unopenable file, …), or `nil`
    ///     when it opened (or is legitimately absent).
    ///   - commandName: the binary name, for the remediation hint.
    /// - Returns: the lines to write to stderr (already without trailing
    ///   newlines). Empty only never — there is always at least the summary.
    static func serveDatabaseHealthBanner(
        inventory: Search.SourceInventory,
        searchIndexDisabledReason: String?,
        commandName: String = Shared.Constants.App.commandName
    ) -> [String] {
        var lines: [String] = []

        if inventory.isComplete, searchIndexDisabledReason == nil {
            lines.append("📚 Databases: all \(inventory.expected) installed.")
            return lines
        }

        let missing = inventory.sources.filter { !$0.present }.map(\.id)
        var summary = "📚 Databases: \(inventory.installed) of \(inventory.expected) installed."
        if !missing.isEmpty {
            summary += " Missing: \(missing.joined(separator: ", "))."
        }
        lines.append(summary)

        if let reason = searchIndexDisabledReason {
            lines.append("⚠️  Search index unavailable: \(reason)")
        }

        if !inventory.isComplete {
            lines.append("→ Run `\(commandName) setup` to download the missing databases.")
        }

        return lines
    }
}

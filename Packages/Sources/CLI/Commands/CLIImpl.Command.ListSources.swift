import ArgumentParser
import Foundation
import SearchModels
import SharedConstants

// MARK: - List Sources Command

/// CLI command for listing the installed per-source databases. Mirrors the `list_sources` MCP
/// tool (#1277): both render `CLIImpl.activeSourceInventory()`, the registry-derived canonical
/// active set (excludes the legacy unified `search.db`, correct across the per-source-DB-split
/// migration), each annotated with on-disk presence and schema version. Human-runnable and
/// smoke-testable, unlike the MCP-only tool.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct ListSources: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-sources",
            abstract: "List the installed documentation sources (per-source databases) and their schema versions"
        )

        @Option(
            name: .long,
            help: CLIImpl.Command.OutputFormatArgument.textDefaultHelp
        )
        var format: OutputFormat = .text

        mutating func run() async throws {
            let inventory = CLIImpl.activeSourceInventory()
            let output: String
            switch format {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(inventory), let text = String(data: data, encoding: .utf8) {
                    output = text
                } else {
                    output = #"{"sources":[]}"#
                }
            case .text:
                var lines = ["\(inventory.installed) of \(inventory.expected) databases installed:"]
                for source in inventory.sources {
                    let mark = source.present ? "✓" : "✗"
                    let version = source.present ? " (schema \(source.schemaVersion))" : ""
                    lines.append("  \(mark) \(source.id): \(source.displayName)\(version) [\(source.filename)]")
                }
                output = lines.joined(separator: "\n")
            }
            CLIImpl.writeStdout(output)
        }
    }
}

// MARK: - Output Format

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command.ListSources {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }
}

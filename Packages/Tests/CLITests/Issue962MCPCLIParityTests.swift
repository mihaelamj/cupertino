import ArgumentParser
@testable import CLI
import Foundation
import SharedConstants
import Testing

// MARK: - #962 MCP/CLI parity

/// Enforces the invariant "everything MCP has, CLI must have": every MCP tool the
/// server dispatches has a sibling `cupertino` subcommand. Pre-#948 the 5 AST
/// tools had no CLI command; #948 added them. This guard stops the gap from
/// reopening when a future MCP tool is introduced without its CLI wrapper.
///
/// `mcpTools` mirrors the `CompositeToolProvider.callTool` dispatch surface. The
/// server is independently pinned to exactly these names by
/// `Issue645ToolsListHonestyTests` (its `tools.count == 12` assertion fails the
/// moment a tool is added or removed), so a new tool forces a visit here too.
@Suite("#962 MCP/CLI parity: every MCP tool has a CLI command")
struct Issue962MCPCLIParityTests {
    private static let mcpTools: [String] = [
        Shared.Constants.Search.toolSearch,
        Shared.Constants.Search.toolListFrameworks,
        Shared.Constants.Search.toolReadDocument,
        Shared.Constants.Search.toolListSamples,
        Shared.Constants.Search.toolReadSample,
        Shared.Constants.Search.toolReadSampleFile,
        Shared.Constants.Search.toolSearchSymbols,
        Shared.Constants.Search.toolSearchPropertyWrappers,
        Shared.Constants.Search.toolSearchConcurrency,
        Shared.Constants.Search.toolSearchConformances,
        Shared.Constants.Search.toolSearchGenerics,
        Shared.Constants.Search.toolGetInheritance,
    ]

    /// MCP tool names whose CLI command name is not a literal `_` -> `-` transform.
    private static let cliNameOverrides: [String: String] = [
        Shared.Constants.Search.toolReadDocument: "read",
        Shared.Constants.Search.toolGetInheritance: "inheritance",
    ]

    private func expectedCLIName(for tool: String) -> String {
        Self.cliNameOverrides[tool] ?? tool.replacingOccurrences(of: "_", with: "-")
    }

    @Test("every MCP tool has a registered CLI subcommand")
    func everyMCPToolHasCLICommand() {
        // NB: a plain loop, not `.compactMap(\.configuration.commandName)`. The
        // keypath-on-metatype form crashes the Swift 6.3 SILGen keypath lowering.
        var cliCommandNames: Set<String> = []
        for command in Cupertino.configuration.subcommands {
            if let name = command.configuration.commandName {
                cliCommandNames.insert(name)
            }
        }

        for tool in Self.mcpTools {
            let cliName = expectedCLIName(for: tool)
            #expect(
                cliCommandNames.contains(cliName),
                "MCP tool '\(tool)' has no CLI command '\(cliName)' (#962): add a CLIImpl.Command.* subcommand, or a cliNameOverrides entry if the name differs."
            )
        }
    }

    /// The 5 AST search tools merge `platformFilterProperties` (min_ios / min_macos
    /// / min_tvos / min_watchos / min_visionos) into their MCP input schema, so each
    /// CLI sibling must expose the matching `--min-*` options for full option-level
    /// parity. Introspects the command help via ArgumentParser's `helpMessage()`
    /// (no binary spawn) so a dropped option fails the build.
    @Test("AST search CLI commands expose the platform-floor options their MCP tools declare")
    func astCommandsExposePlatformFloors() {
        let floors = ["--min-ios", "--min-macos", "--min-tvos", "--min-watchos", "--min-visionos"]
        let helps: [(name: String, help: String)] = [
            ("search-symbols", CLIImpl.Command.SearchSymbols.helpMessage()),
            ("search-property-wrappers", CLIImpl.Command.SearchPropertyWrappers.helpMessage()),
            ("search-concurrency", CLIImpl.Command.SearchConcurrency.helpMessage()),
            ("search-conformances", CLIImpl.Command.SearchConformances.helpMessage()),
            ("search-generics", CLIImpl.Command.SearchGenerics.helpMessage()),
        ]
        for entry in helps {
            for floor in floors {
                #expect(
                    entry.help.contains(floor),
                    "CLI '\(entry.name)' is missing \(floor) (#962 option parity with its MCP tool)."
                )
            }
        }
    }
}

import ArgumentParser

// MARK: - Shared output format argument helpers

extension CLIImpl.Command {
    enum OutputFormatArgument {
        static let textDefaultHelp: ArgumentHelp = .init(
            "Output format: text (human-readable, default), json (machine-parseable), " +
            "markdown / md (MCP wire shape)"
        )
        static let jsonDefaultHelp: ArgumentHelp = .init(
            "Output format: json (machine-parseable, default), " +
            "markdown / md (MCP wire shape)"
        )

        static func normalize(_ argument: String) -> String {
            argument == "md" ? "markdown" : argument
        }
    }
}

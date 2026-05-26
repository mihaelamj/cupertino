import Foundation

// MARK: - Search Result Format Configuration

extension Services.Formatter {
    /// Configuration for search result formatting
    public struct Config: Sendable {
        public let showScore: Bool
        public let showWordCount: Bool
        public let showSource: Bool
        public let showAvailability: Bool
        public let showSeparators: Bool
        public let emptyMessage: String

        public init(
            showScore: Bool = false,
            showWordCount: Bool = false,
            showSource: Bool = true,
            showAvailability: Bool = false,
            showSeparators: Bool = false,
            emptyMessage: String = "No results found"
        ) {
            self.showScore = showScore
            self.showWordCount = showWordCount
            self.showSource = showSource
            self.showAvailability = showAvailability
            self.showSeparators = showSeparators
            self.emptyMessage = emptyMessage
        }
    }
}

// #976: `Services.Formatter.Config.shared` + `.cliDefault` + `.mcpDefault`
// statics were removed per `gof-di-rules.md` Rule 1. Pre-#976
// consumers reached into the static as a Service Locator; the rule
// forbids that even on Sendable value types. The canonical
// "standard" configuration is constructed inline at the 2
// composition-root call sites (`CLI/Commands/CLIImpl.Command.Search.SourceRunners.swift`
// and `SearchToolProvider/CompositeToolProvider.swift`); both pass
// the resulting Config down to the formatter as an explicit init
// parameter rather than letting the formatter reach into a holder.

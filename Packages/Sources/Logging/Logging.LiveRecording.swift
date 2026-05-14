import Foundation
import LoggingModels
import OSLog
import SharedConstants
// MARK: - Logging.LiveRecording

extension Logging {
    /// Production conformer for `Logging.Recording` (the GoF Strategy
    /// protocol in `LoggingModels`, 1994 p. 315). Wraps the actor-isolated
    /// `Logging.Unified` so callers can hold `any Logging.Recording`
    /// without reaching for the actor singleton.
    ///
    /// One `Logging.LiveRecording` instance is constructed at the
    /// composition root of each binary (CLI / TUI / MCP / MockAIAgent)
    /// and passed down through constructor injection. Tests substitute
    /// `Logging.NoopRecording` (the inert conformer in `LoggingModels`)
    /// or a custom spy, exactly the same way mocked
    /// `Search.DatabaseFactory` / `Crawler.HTMLParserStrategy` etc.
    /// flow through the rest of the codebase.
    ///
    /// Pure addition — no consumer migration in this PR. The legacy
    /// `Logging.Log` / `Logging.ConsoleLogger` / `Logging.Unified.shared`
    /// surface stays live for the 600+ existing call sites that the
    /// followup PRs migrate one feature target at a time.
    public struct LiveRecording: LoggingModels.Logging.Recording, Sendable {
        public init() {}

        public func record(
            _ message: String,
            level: LoggingModels.Logging.Level,
            category: LoggingModels.Logging.Category
        ) {
            // Fire-and-forget through the shared actor. We map the
            // Models-side Level / Category to the actor's own Level /
            // Category nested enums (deliberately kept separate during
            // migration so a typo in the Models-side enum can't break
            // the legacy static path).
            let actorLevel = mapLevel(level)
            let actorCategory = mapCategory(category)
            Task.detached {
                let unified = Logging.Unified.shared
                switch actorLevel {
                case .debug:
                    await unified.debug(message, category: actorCategory)
                case .info:
                    await unified.info(message, category: actorCategory)
                case .warning:
                    await unified.warning(message, category: actorCategory)
                case .error:
                    await unified.error(message, category: actorCategory)
                }
            }
        }

        public func output(_ message: String) {
            // Synchronous stdout passthrough — mirrors `Logging.Log.output`
            // and `Logging.ConsoleLogger.output` which both bypass log
            // levels entirely and exist for user-facing dumps (search
            // results, doctor output, formatted JSON).
            print(message)
        }

        // MARK: - Bridges between LoggingModels and Logging.Unified

        private func mapLevel(_ level: LoggingModels.Logging.Level) -> Logging.Unified.Level {
            switch level {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .warning
            case .error: return .error
            }
        }

        private func mapCategory(_ category: LoggingModels.Logging.Category) -> Logging.Unified.Category {
            switch category {
            case .crawler: return .crawler
            case .mcp: return .mcp
            case .search: return .search
            case .cli: return .cli
            case .transport: return .transport
            case .evolution: return .evolution
            case .samples: return .samples
            case .packages: return .packages
            case .archive: return .archive
            case .hig: return .hig
            }
        }
    }
}

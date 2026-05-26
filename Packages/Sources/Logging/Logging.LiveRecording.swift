import Foundation
import LoggingModels
import OSLog
import SharedConstants

// MARK: - Logging.LiveRecording

extension Logging {
    /// Production conformer for `Logging.Recording` (the GoF Strategy
    /// protocol in `LoggingModels`, 1994 p. 315). Bridge (GoF p. 151)
    /// abstraction: the protocol surface is the abstraction, the held
    /// `Logging.Unified` actor is the implementation. The two are
    /// pluggable independently.
    ///
    /// **Construction.** Each binary's composition root (typically a
    /// `Logging.Composition` value, which itself lives inside a
    /// `Cupertino.Composition` Mediator) builds one `Logging.Unified`
    /// instance, wraps it with `LiveRecording(unified:)`, and threads
    /// the resulting `any LoggingModels.Logging.Recording` downstream
    /// via constructor injection. Constructor injection only —
    /// `LiveRecording` has no no-arg init.
    ///
    /// Tests substitute `Logging.NoopRecording` (the inert conformer
    /// in `LoggingModels`) or a custom spy, exactly the same way
    /// mocked `Search.DatabaseFactory` / `Crawler.HTMLParserStrategy`
    /// etc. flow through the rest of the codebase.
    public struct LiveRecording: LoggingModels.Logging.Recording, Sendable {
        /// The actor that carries OSLog + console + file-output state.
        /// Held by reference (actors are reference types in Swift).
        /// Multiple `LiveRecording` adapters can share one `Unified`.
        public let unified: Logging.Unified

        /// Constructor-injected init. Each binary's composition root
        /// builds one `Logging.Unified` (or, more typically, one
        /// `Logging.Composition` which owns the actor) and passes that
        /// instance here.
        public init(unified: Logging.Unified) {
            self.unified = unified
        }

        public func record(
            _ message: String,
            level: LoggingModels.Logging.Level,
            category: LoggingModels.Logging.Category
        ) {
            // Fire-and-forget through the held actor. We map the
            // Models-side Level / Category to the actor's own Level /
            // Category nested enums (deliberately kept separate during
            // migration so a typo in the Models-side enum can't break
            // the legacy static path).
            let actorLevel = mapLevel(level)
            let actorCategory = mapCategory(category)
            let target = unified
            Task.detached {
                switch actorLevel {
                case .debug:
                    await target.debug(message, category: actorCategory)
                case .info:
                    await target.info(message, category: actorCategory)
                case .warning:
                    await target.warning(message, category: actorCategory)
                case .error:
                    await target.error(message, category: actorCategory)
                }
            }
        }

        public func output(_ message: String) {
            // Synchronous stdout passthrough — mirrors `Logging.Log.output`
            // and `Logging.ConsoleLogger.output` which both bypass log
            // levels entirely and exist for user-facing dumps (search
            // results, doctor output, formatted JSON).
            //
            // #780: prefix with the same ISO 8601 timestamp used by the
            // actor-side `logToConsole` path so every line of a save /
            // fetch log has a wall-clock anchor. Blank messages stay
            // blank (the formatter prefix is dropped for empty input)
            // so spacer lines used as visual separators don't bloat
            // into "<timestamp>  ".
            if message.isEmpty {
                print(message)
            } else {
                print("\(Logging.timestampPrefix())\(message)")
            }
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

        // #1042 Cluster 10: post-LoggingModels Category enum→struct
        // conversion, this mapping is a dict lookup keyed by the
        // LoggingModels.Logging.Category raw value. Unknown categories
        // (a future source registering its own category outside the 10
        // shipped) fall through to the `.cli` bucket — the safe default
        // for "general CLI output" rather than crashing in a switch.
        private static let categoryMap: [LoggingModels.Logging.Category: Logging.Unified.Category] = [
            .crawler: .crawler,
            .mcp: .mcp,
            .search: .search,
            .cli: .cli,
            .transport: .transport,
            .evolution: .evolution,
            .samples: .samples,
            .packages: .packages,
            .archive: .archive,
            .hig: .hig,
        ]

        private func mapCategory(_ category: LoggingModels.Logging.Category) -> Logging.Unified.Category {
            Self.categoryMap[category] ?? .cli
        }
    }
}

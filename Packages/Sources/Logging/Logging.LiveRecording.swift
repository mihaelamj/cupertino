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
            // 2026-05-26 post-#1056: the previous shape mapped the
            // Models-side Category to a separate inner-enum Category
            // via `Self.categoryMap` (10 hardcoded entries) +
            // `mapCategory()` helper. Post-fix
            // `Logging.Unified.Category` is a typealias for
            // `LoggingModels.Logging.Category`; the dict + helper are
            // gone. The `actorLevel` mapper stays — Level remains a
            // closed 4-case enum (debug/info/warning/error) that's
            // deliberately not user-pluggable.
            let actorLevel = mapLevel(level)
            let target = unified
            Task.detached {
                switch actorLevel {
                case .debug:
                    await target.debug(message, category: category)
                case .info:
                    await target.info(message, category: category)
                case .warning:
                    await target.warning(message, category: category)
                case .error:
                    await target.error(message, category: category)
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

        // 2026-05-26 post-#1056: `categoryMap` + `mapCategory()`
        // deleted. The two Category types collapsed into a single
        // `LoggingModels.Logging.Category` (foundation tier open
        // struct, Cluster 10). The `Logging.Unified.Category`
        // typealias keeps the inner-actor signatures stable while
        // routing through the same rawValue. The osLogger dispatch
        // moved to a dict in `Logging.Logger.osLogger(for:)`; unknown
        // categories still fall through to `.cli`.
    }
}

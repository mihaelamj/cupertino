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
    /// **Construction (post-#548 Phase A).** Prefer the
    /// `init(unified:)` form, which takes the implementation via
    /// constructor injection. The composition root (typically through
    /// `Logging.Composition`) builds one `Logging.Unified` instance,
    /// wraps it with `LiveRecording`, and threads the resulting
    /// `any Logging.Recording` downstream.
    ///
    /// The no-arg `init()` is preserved during the #548 migration as
    /// a transition shim that delegates to `Logging.Unified.shared`.
    /// It is deleted in the final phase of #548 once every binary's
    /// composition root has been rewritten to build a `Composition`
    /// explicitly.
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
        /// instance here. Phase A of #548 added this initializer.
        public init(unified: Logging.Unified) {
            self.unified = unified
        }

        /// Transition shim preserved during #548's per-binary migration.
        /// Delegates to `Logging.Unified.shared` so the ~500 existing
        /// inline `Logging.LiveRecording()` call sites in CLI / TUI / MCP /
        /// ReleaseTool / MockAIAgent keep working while their composition
        /// roots are rewritten one PR at a time. Removed in the final
        /// phase of #548.
        public init() {
            unified = .shared
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

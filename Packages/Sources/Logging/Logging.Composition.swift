import Foundation
import LoggingModels

// MARK: - Logging.Composition

extension Logging {
    /// Abstract Factory (GoF p. 87) for the logging subsystem. Owns one
    /// `Logging.Unified` actor (the implementation half of the
    /// `Logging.LiveRecording` Bridge, GoF p. 151) and exposes:
    ///
    /// - `recording`: a ready-to-use `any LoggingModels.Logging.Recording`
    ///   value to thread downstream through constructor injection.
    /// - Façade methods (`configure(_:)`, `disableConsole()`,
    ///   `enableConsole()`, `enableFileLogging(at:)`,
    ///   `disableFileLogging()`) that forward to the held actor so a
    ///   binary's composition root configures logging once, in one place.
    ///
    /// Each binary (`cupertino` CLI, TUI, MCP server entry, ReleaseTool,
    /// MockAIAgent) constructs exactly one `Logging.Composition` at its
    /// composition root and threads `recording` into producers. Tests
    /// either build a `Composition` with custom `Logging.Unified.Options`
    /// or substitute `Logging.NoopRecording` for the `recording` parameter.
    ///
    /// Replaces the previous `Logging.Unified.shared` Singleton (GoF p.
    /// 127) which was rejected as a Service Locator (Seemann, *Dependency
    /// Injection*, 2011, ch. 5). Shipped across #548 phases A-H; the
    /// `.shared` accessor and the no-arg `Logging.LiveRecording()` shim
    /// are deleted.
    ///
    /// Sendable because every stored property is Sendable (actors are
    /// reference-typed and Sendable; `LiveRecording` is a Sendable struct
    /// holding the same actor reference).
    public struct Composition: Sendable {
        /// The actor that carries OSLog + console + file-output state.
        /// Held by reference; multiple `LiveRecording` adapters or other
        /// consumers can share this instance.
        public let unified: Logging.Unified

        /// The Bridge adapter ready to thread downstream as
        /// `any LoggingModels.Logging.Recording`. Wraps `unified`.
        public let recording: any LoggingModels.Logging.Recording

        /// Build one logging subsystem for this binary.
        public init(options: Logging.Unified.Options = .default) {
            let actor = Logging.Unified(options: options)
            unified = actor
            recording = Logging.LiveRecording(unified: actor)
        }

        // MARK: - Façade: actor configuration

        /// Replace the actor's options. Forwards to `Unified.configure`.
        public func configure(_ options: Logging.Unified.Options) async {
            await unified.configure(options)
        }

        /// Silence stdout/stderr console output. Used by the MCP server
        /// entry to keep the JSON-RPC stdio stream parseable.
        public func disableConsole() async {
            await unified.disableConsole()
        }

        /// Re-enable stdout/stderr console output after a prior
        /// `disableConsole()`.
        public func enableConsole() async {
            await unified.enableConsole()
        }

        /// Turn on file logging at the given URL. Caller supplies the
        /// path (`nil` uses the actor's default-options fallback, which
        /// is itself nil after #535 — the caller must pass an explicit
        /// URL in production code).
        public func enableFileLogging(at url: URL? = nil) async {
            await unified.enableFileLogging(at: url)
        }

        /// Close the log file and stop writing to disk.
        public func disableFileLogging() async {
            await unified.disableFileLogging()
        }
    }
}

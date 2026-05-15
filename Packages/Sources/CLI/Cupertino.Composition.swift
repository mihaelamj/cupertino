import Foundation
import Logging
import SharedConstants

// MARK: - Cupertino.Composition

//
// `import LoggingModels` is deliberately omitted: the `Logging` and
// `LoggingModels` modules both declare a `public enum Logging` namespace
// (intentional, see the doc comment in `Logging.swift`), so importing
// both into the same file makes `Logging.X` ambiguous. CLI command
// bodies that need to pass the recorder downstream do so by value —
// the parameter's declared type at the producer's init resolves to
// `LoggingModels.Logging.Recording` through that producer's own
// `import LoggingModels`. CLI never has to name the protocol.

extension Cupertino {
    /// **Mediator** (GoF p. 273) for the `cupertino` CLI binary. Owns the
    /// cross-cutting dependencies every command body needs: the logging
    /// subsystem (`Logging.Composition`) and the binary's path resolver
    /// (`Shared.Paths`). One instance is constructed in
    /// `Cupertino.main()` and bound to `Cupertino.Context.composition`
    /// via SE-0311 `@TaskLocal` so subcommand `run()` bodies see exactly
    /// that instance for the lifetime of the program.
    ///
    /// **Why TaskLocal and not constructor injection.** Swift's
    /// `AsyncParsableCommand` framework constructs command structs
    /// itself from `argv`; init parameters are structurally forbidden
    /// by the macro. `@TaskLocal` is the modern Swift idiom for this
    /// exact problem (swift-distributed-tracing's
    /// `InstrumentationSystem` uses the same shape). The binding is
    /// value-typed, structurally bound, scoped to the task — **not a
    /// Singleton**: there's no process-wide mutable accessor, only a
    /// structurally-scoped value within `Cupertino.main()`'s
    /// `withValue { … }` block.
    ///
    /// Producer-layer code still takes its collaborators via explicit
    /// constructor injection; command bodies are the only place that
    /// reads from the TaskLocal, and they thread the resolved values
    /// into producers as ordinary parameters.
    ///
    /// Replaces the inline `Logging.LiveRecording()` Bastard Injection
    /// (Seemann 2011 ch. 5.4) that was distributed across ~488 sites
    /// in the CLI before #548.
    public struct Composition: Sendable {
        /// Logging subsystem composed at the binary root. Owns the
        /// `Logging.Unified` actor + the `LiveRecording` Bridge wrapper.
        public let logging: Logging.Composition

        /// Resolved path graph for this binary (`baseDirectory` derived
        /// from `BinaryConfig.load(from:)` exactly once).
        public let paths: Shared.Paths

        /// Build the CLI binary's dependency graph.
        public init(
            logging: Logging.Composition = Logging.Composition(),
            paths: Shared.Paths = .live()
        ) {
            self.logging = logging
            self.paths = paths
        }
    }

    /// Namespace for binary-scoped `@TaskLocal` bindings. The
    /// `composition` binding is set inside `Cupertino.main()` and read
    /// by every command's `run()`.
    ///
    /// The default value (an idle `Composition()` constructed lazily on
    /// first access) exists so unit tests that instantiate a command
    /// directly without going through `Cupertino.main()` still get a
    /// reachable composition. Integration tests that need a custom
    /// composition wrap their work in `Cupertino.Context.$composition.withValue(...)`.
    public enum Context {
        @TaskLocal public static var composition: Cupertino.Composition = .init()
    }
}

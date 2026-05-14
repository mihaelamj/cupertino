import Foundation
import SharedConstants

// MARK: - Sample.Index.SamplesIndexingRunner

/// Runner for a complete `samples.db` indexing pass: open the
/// database, optionally clear it, load the sample-code catalog,
/// walk the on-disk sample ZIPs, write project + file + symbol
/// rows, and close. GoF Strategy pattern (Gamma et al, 1994): a
/// family of algorithms (production `Sample.Index.Database` +
/// `Sample.Index.Builder` + `Sample.Core.Catalog` pipeline, test
/// fixture stubs) interchangeable behind a named protocol.
///
/// The runner emits lifecycle events through the supplied `onPhase`
/// callback so `Indexer.SamplesService` can forward them to its
/// `Event` API without inspecting the indexer's internals.
///
/// `Indexer.SamplesService` accepts a conformer at run-time so the
/// Indexer SPM target keeps its dependency graph free of the
/// concrete sample-indexing actors. The composition root (the CLI's
/// `save` command) supplies a `LiveSamplesIndexingRunner` backed by
/// the standard concrete wiring.
///
/// This replaces the previous
/// `Sample.Index.SamplesIndexingRun = @Sendable (Input, phaseCallback) async throws -> Outcome`
/// closure typealias. The protocol form names the contract at the
/// constructor site (`samplesIndexingRunner:`), makes captured-state
/// surface explicit on the conforming type's stored properties, and
/// produces one-line test mocks instead of multi-arg async closures.
///
/// The phase callback stays a closure — it's a genuine lifecycle
/// event stream, not a strategy seam.
public extension Sample.Index {
    protocol SamplesIndexingRunner: Sendable {
        /// Run one full indexing pass and return its outcome.
        ///
        /// - Parameters:
        ///   - input: Paths + clear / force flags.
        ///   - onPhase: Callback that receives each lifecycle event
        ///     (`.loadingCatalog`, `.projectProgress(...)`, …) so the
        ///     caller can forward them to its event API.
        /// - Returns: The aggregated `SamplesIndexingOutcome`.
        func run(
            input: SamplesIndexingInput,
            onPhase: @escaping @Sendable (SamplesIndexingPhase) -> Void
        ) async throws -> SamplesIndexingOutcome
    }
}

// MARK: - Sample.Index.SamplesIndexingInput

/// Parameter bundle for `Sample.Index.SamplesIndexingRunner.run`. Mirrors
/// `Indexer.SamplesService.Request` field-for-field; the Indexer
/// service translates one to the other.
public extension Sample.Index {
    struct SamplesIndexingInput: Sendable {
        public let sampleCodeDir: URL
        public let samplesDB: URL
        public let clear: Bool
        public let force: Bool

        public init(
            sampleCodeDir: URL,
            samplesDB: URL,
            clear: Bool,
            force: Bool
        ) {
            self.sampleCodeDir = sampleCodeDir
            self.samplesDB = samplesDB
            self.clear = clear
            self.force = force
        }
    }
}

// MARK: - Sample.Index.SamplesIndexingPhase

/// Lifecycle events emitted by a `Sample.Index.SamplesIndexingRunner`
/// closure. Indexer.SamplesService translates each phase into its
/// matching public `Event` case (`.clearingExistingIndex`,
/// `.existingIndexNotice(...)`, `.loadingCatalog`,
/// `.catalogLoaded(entryCount:)`, `.indexingStart`,
/// `.projectProgress(name:percent:phase:)`).
public extension Sample.Index {
    enum SamplesIndexingPhase: Sendable {
        case clearingExistingIndex
        case existingIndexNotice(projects: Int, files: Int)
        case loadingCatalog
        case catalogLoaded(entryCount: Int)
        case indexingStart
        case projectProgress(name: String, percent: Double, phase: ProgressPhase)

        public enum ProgressPhase: String, Sendable {
            case extracting
            case indexingFiles
            case completed
            case failed
        }
    }
}

// MARK: - Sample.Index.SamplesIndexingOutcome

/// Statistics emitted by a completed `Sample.Index.SamplesIndexingRunner` run.
public extension Sample.Index {
    struct SamplesIndexingOutcome: Sendable {
        public let projectsIndexedThisRun: Int
        public let projectsTotal: Int
        public let filesTotal: Int
        public let symbolsTotal: Int
        public let importsTotal: Int
        public let durationSeconds: Double

        public init(
            projectsIndexedThisRun: Int,
            projectsTotal: Int,
            filesTotal: Int,
            symbolsTotal: Int,
            importsTotal: Int,
            durationSeconds: Double
        ) {
            self.projectsIndexedThisRun = projectsIndexedThisRun
            self.projectsTotal = projectsTotal
            self.filesTotal = filesTotal
            self.symbolsTotal = symbolsTotal
            self.importsTotal = importsTotal
            self.durationSeconds = durationSeconds
        }
    }
}

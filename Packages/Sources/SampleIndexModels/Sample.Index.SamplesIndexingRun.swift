import Foundation
import SharedConstants

// MARK: - Sample.Index.SamplesIndexingRun

/// Closure shape for running a complete `samples.db` indexing pass:
/// open the database, optionally clear it, load the sample-code
/// catalog, walk the on-disk sample ZIPs, write project + file +
/// symbol rows, and close. The closure also emits lifecycle events
/// through the supplied `onPhase` callback so `Indexer.SamplesService`
/// can forward them to its `Event` API without inspecting the
/// indexer's internals.
///
/// `Indexer.SamplesService` accepts one of these instead of reaching
/// directly into `Sample.Index.Database` / `Sample.Index.Builder` /
/// `Sample.Core.Catalog`. The composition root (the CLI's `save`
/// command) supplies the closure with the standard concrete wiring.
///
/// Mirrors the `Search.DocsIndexingRun` / `Search.PackageIndexingRun`
/// pattern.
public extension Sample.Index {
    typealias SamplesIndexingRun = @Sendable (
        _ input: SamplesIndexingInput,
        _ onPhase: @escaping @Sendable (SamplesIndexingPhase) -> Void
    ) async throws -> SamplesIndexingOutcome
}

// MARK: - Sample.Index.SamplesIndexingInput

/// Parameter bundle for `Sample.Index.SamplesIndexingRun`. Mirrors
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

/// Lifecycle events emitted by a `Sample.Index.SamplesIndexingRun`
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

/// Statistics emitted by a completed `Sample.Index.SamplesIndexingRun`.
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

import Foundation
import SharedConstants

// MARK: - Distribution.SetupService — value types + Observer protocol

extension Distribution {
    /// `cupertino setup` orchestrator namespace. The concrete
    /// `run(...)` static function lives in the `Distribution` producer
    /// target as an extension on this enum. The value types
    /// (`Request`, `Outcome`, `Event`) plus the GoF Observer protocol
    /// (`EventObserving`) stay here in `DistributionModels` so any
    /// conformer can implement the protocol without `import Distribution`.
    public enum SetupService {
        /// What the caller asked for. Mirrors the `cupertino setup`
        /// flag shape so the CLI maps argv to this struct directly.
        public struct Request: Sendable {
            public let baseDir: URL
            public let currentDocsVersion: String
            public let docsReleaseBaseURL: String
            public let keepExisting: Bool

            public init(
                baseDir: URL,
                currentDocsVersion: String = Shared.Constants.App.databaseVersion,
                docsReleaseBaseURL: String = Shared.Constants.App.docsReleaseBaseURL,
                keepExisting: Bool = false
            ) {
                self.baseDir = baseDir
                self.currentDocsVersion = currentDocsVersion
                self.docsReleaseBaseURL = docsReleaseBaseURL
                self.keepExisting = keepExisting
            }
        }

        /// Outcome of a single `run` invocation. The CLI uses this to
        /// render the success summary and decide what hint to print.
        public struct Outcome: Sendable, Equatable {
            public let searchDBPath: URL
            public let samplesDBPath: URL
            public let packagesDBPath: URL
            public let docsVersionWritten: String
            /// Hits when `keepExisting: true` and every DB was already
            /// present. The CLI uses this to skip the "downloaded" log.
            public let skippedDownload: Bool
            public let priorStatus: Distribution.InstalledVersion.Status

            public init(
                searchDBPath: URL,
                samplesDBPath: URL,
                packagesDBPath: URL,
                docsVersionWritten: String,
                skippedDownload: Bool,
                priorStatus: Distribution.InstalledVersion.Status
            ) {
                self.searchDBPath = searchDBPath
                self.samplesDBPath = samplesDBPath
                self.packagesDBPath = packagesDBPath
                self.docsVersionWritten = docsVersionWritten
                self.skippedDownload = skippedDownload
                self.priorStatus = priorStatus
            }
        }

        /// Progress events emitted while the pipeline runs. CLI
        /// subscribes via an `EventObserving` conformer; tests can
        /// collect them.
        public enum Event: Sendable {
            case starting(Request)
            case statusResolved(Distribution.InstalledVersion.Status)
            /// A pre-existing DB was renamed to a
            /// `.backup-<version>-<iso8601>` sibling before extraction
            /// would overwrite it (#249).
            case dbBackedUp(filename: String, from: URL, to: URL)
            case downloadStart(label: String)
            case downloadProgress(label: String, Distribution.ArtifactDownloader.Progress)
            case downloadComplete(label: String, sizeBytes: Int64)
            case extractStart(label: String)
            case extractTick(label: String)
            case extractComplete(label: String)
            case finished(Outcome)
        }

        /// GoF Observer (1994 p. 293) for `SetupService.run` lifecycle
        /// events. Replaces the previous
        /// `handler: @escaping @Sendable (Event) -> Void` closure
        /// parameter. Per the standing cupertino rule "no closures,
        /// they ate magic."
        public protocol EventObserving: Sendable {
            /// Called once per lifecycle transition. Implementations
            /// should be non-blocking; the service waits for return
            /// before continuing.
            func observe(event: Event)
        }
    }
}

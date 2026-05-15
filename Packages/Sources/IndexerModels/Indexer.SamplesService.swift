import Foundation

// MARK: - Indexer.SamplesService — value types + Observer protocol

extension Indexer {
    /// Builds `samples.db` from extracted sample-code zips at
    /// `~/.cupertino/sample-code/`.
    ///
    /// The value types here (`Request`, `Outcome`, `Event`, `Phase`,
    /// `ServiceError`, `EventObserving`) form the foundation-only seam.
    /// The `static func run(...)` orchestrator that consumes them lives
    /// in the `Indexer` producer target as an extension on this enum.
    public enum SamplesService {
        public struct Request: Sendable {
            public let sampleCodeDir: URL
            public let samplesDB: URL
            public let clear: Bool
            public let force: Bool

            public init(
                sampleCodeDir: URL,
                samplesDB: URL,
                clear: Bool = false,
                force: Bool = false
            ) {
                self.sampleCodeDir = sampleCodeDir
                self.samplesDB = samplesDB
                self.clear = clear
                self.force = force
            }
        }

        public struct Outcome: Sendable {
            public let samplesDBPath: URL
            public let projectsIndexedThisRun: Int
            public let projectsTotal: Int
            public let filesTotal: Int
            public let symbolsTotal: Int
            public let importsTotal: Int
            public let durationSeconds: Double

            public init(
                samplesDBPath: URL,
                projectsIndexedThisRun: Int,
                projectsTotal: Int,
                filesTotal: Int,
                symbolsTotal: Int,
                importsTotal: Int,
                durationSeconds: Double
            ) {
                self.samplesDBPath = samplesDBPath
                self.projectsIndexedThisRun = projectsIndexedThisRun
                self.projectsTotal = projectsTotal
                self.filesTotal = filesTotal
                self.symbolsTotal = symbolsTotal
                self.importsTotal = importsTotal
                self.durationSeconds = durationSeconds
            }
        }

        public enum Event: Sendable {
            public enum Phase: String, Sendable {
                case extracting
                case indexingFiles
                case completed
                case failed
            }

            case starting(sampleCodeDir: URL, samplesDB: URL)
            case removingExistingDB(URL)
            case clearingExistingIndex
            case existingIndexNotice(projects: Int, files: Int)
            case loadingCatalog
            case catalogLoaded(entryCount: Int)
            case indexingStart
            case projectProgress(name: String, percent: Double, phase: Phase)
            case finished(Outcome)
        }

        public enum ServiceError: Error, CustomStringConvertible {
            case sampleCodeDirectoryNotFound(URL)

            public var description: String {
                switch self {
                case .sampleCodeDirectoryNotFound(let url):
                    return "Sample code directory not found: \(url.path)"
                }
            }
        }

        /// GoF Observer (1994 p. 293) for `Indexer.SamplesService`
        /// lifecycle events. Replaces the inline
        /// `handler: @escaping @Sendable (Event) -> Void` closure
        /// parameter previously taken by
        /// `Indexer.SamplesService.run`. See
        /// `Indexer.DocsService.EventObserving` for the full rationale.
        public protocol EventObserving: Sendable {
            /// Called once per lifecycle transition. Implementations
            /// should be non-blocking; the service waits for return
            /// before continuing.
            func observe(event: Event)
        }
    }
}
